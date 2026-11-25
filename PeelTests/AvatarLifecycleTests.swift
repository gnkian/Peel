import SwiftUI
import Testing
import UIKit
@testable import Peel

@MainActor
private final class AvatarTestClock {
    var date = Date()
    private var waiters: [UUID: (Date, CheckedContinuation<Void, Error>)] = [:]
    var waitingCount: Int { waiters.count }

    func sleep(_ delay: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters[id] = (date.addingTimeInterval(delay), continuation) }
            }
        } onCancel: {
            Task { @MainActor in self.waiters.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
        }
    }

    func advance(_ seconds: TimeInterval) {
        date.addTimeInterval(seconds)
        let ready = waiters.filter { $0.value.0 <= date }
        for id in ready.keys { waiters.removeValue(forKey: id)?.1.resume() }
    }
}

@MainActor
private struct HostedAvatarList: View {
    @ObservedObject var model: PeelModel
    let store: InstagramAvatarStore
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(model.queue.users, id: \.self) { user in
                    InstagramAvatar(username: user, allowsNetwork: true, store: store)
                }
            }
        }
    }
}

@MainActor
@Suite(.serialized)
struct AvatarLifecycleTests {
    private let page = Data(#"<meta property="og:image" content="https://cdninstagram.com/fixture.png">"#.utf8)
    private var picture: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    private func waitUntil(sourceLocation: SourceLocation = #_sourceLocation, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(await condition(), sourceLocation: sourceLocation)
    }

    private func host(_ model: PeelModel, store: InstagramAvatarStore) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: HostedAvatarList(model: model, store: store))
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    @Test func retainedSwiftUIRowResumesAfterCooldownAndTrimWithoutReplacementRequest() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["kept"]
        model.compare()
        let clock = AvatarTestClock()
        let mock = MockHTTPClient([.failure(.rateLimited(clock.date.addingTimeInterval(60))), .data(page), .data(picture)])
        let gate = AvatarRequestGate(now: { await clock.date }, sleep: { try await clock.sleep($0) })
        let store = InstagramAvatarStore(client: mock, now: { clock.date }, sleep: clock.sleep, gate: gate)
        let window = host(model, store: store)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { clock.waitingCount == 1 }
        // Insert an earlier row, then trim it away. The original kept row retains its identity.
        model.followingNames = ["removed", "kept"]
        model.compare()
        try await waitUntil { clock.waitingCount == 2 }
        model.start(at: "kept")
        window.layoutIfNeeded()
        #expect(store.retryAvailableAt("kept") == clock.date.addingTimeInterval(60))
        await store.retry("kept")
        #expect(await mock.requests == 1)
        clock.advance(59)
        #expect(await mock.requests == 1)
        clock.advance(1)
        try await waitUntil { store.image(for: "kept") != nil }
        #expect(model.queue.users == ["kept"])
        #expect(await mock.requests == 3)
    }

    @Test func newlyVisibleRowAutomaticallyStartsWhenGlobalCooldownExpires() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["kept"]
        model.compare()
        let clock = AvatarTestClock()
        let client = LifecycleAvatarClient(page: page, picture: picture,
                                          firstFailure: .rateLimited(clock.date.addingTimeInterval(60)))
        let gate = AvatarRequestGate(now: { await clock.date }, sleep: { try await clock.sleep($0) })
        let store = InstagramAvatarStore(client: client, now: { clock.date }, sleep: clock.sleep, gate: gate)
        let window = host(model, store: store)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { clock.waitingCount == 1 }
        model.followingNames = ["kept", "newly_visible"]
        model.compare()
        try await waitUntil { clock.waitingCount == 2 }
        #expect(await client.profileRequests(for: "newly_visible") == 0)
        clock.advance(60)
        try await waitUntil { store.image(for: "newly_visible") != nil && store.image(for: "kept") != nil }
        #expect(await client.profileRequests(for: "newly_visible") == 1)
        #expect(await client.profileRequests(for: "kept") == 2)
    }

    @Test func retainedSwiftUIRowResumesAfterFailureDelay() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["kept"]
        model.compare()
        let clock = AvatarTestClock()
        let mock = MockHTTPClient([.failure(.offline), .data(page), .data(picture)])
        let gate = AvatarRequestGate(now: { await clock.date }, sleep: { try await clock.sleep($0) })
        let store = InstagramAvatarStore(client: mock, now: { clock.date }, sleep: clock.sleep, gate: gate)
        let window = host(model, store: store)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { clock.waitingCount == 1 }
        clock.advance(10)
        try await waitUntil { store.image(for: "kept") != nil }
        #expect(await mock.requests == 3)
    }

    @Test func trimmingDuringInFlightHTMLKeepsTheOriginalRowLoading() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["removed", "kept"]
        model.compare()
        let client = LifecycleAvatarClient(page: page, picture: picture, heldUser: "kept")
        let store = InstagramAvatarStore(client: client)
        let window = host(model, store: store)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { await client.held }
        model.start(at: "kept")
        window.layoutIfNeeded()
        await client.release()
        try await waitUntil { store.image(for: "kept") != nil }
        #expect(await client.profileRequests(for: "kept") == 1)
        #expect(model.queue.users == ["kept"])
    }

    @Test func visibleThumbnailSurvivesCacheEvictionWithoutReloadLoop() async throws {
        let mock = MockHTTPClient([.data(page), .data(picture), .data(page), .data(picture)])
        let store = InstagramAvatarStore(client: mock, capacity: 1)
        var displayed: UIImage?
        let row = Task { await store.observe("kept") { displayed = $0 } }
        defer { row.cancel() }
        try await waitUntil { displayed != nil }
        let original = displayed
        await store.load("other")
        #expect(store.image(for: "kept") == nil)
        #expect(displayed === original)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await mock.requests == 4)
    }

    @Test func repeatedFailuresStopUntilExplicitRetryAndOfflineRowsNeverRequest() async throws {
        let clock = AvatarTestClock()
        let mock = MockHTTPClient(Array(repeating: .failure(.offline), count: 4))
        let gate = AvatarRequestGate(now: { await clock.date }, sleep: { try await clock.sleep($0) })
        let store = InstagramAvatarStore(client: mock, now: { clock.date }, sleep: clock.sleep, gate: gate)
        let row = Task { await store.observe("kept") { _ in } }
        let secondRow = Task { await store.observe("kept") { _ in } }
        defer { row.cancel(); secondRow.cancel() }
        for count in 1...2 {
            try await waitUntil {
                let requests = await mock.requests
                return clock.waitingCount == 1 && requests == count
            }
            clock.advance(10)
        }
        try await waitUntil { await mock.requests == 3 }
        clock.advance(1_000)
        await Task.yield()
        #expect(await mock.requests == 3)
        await store.observe("peeldemo_fictional") { _ in Issue.record("Unexpected offline image") }
        await store.observe("offline", allowsNetwork: false) { _ in Issue.record("Unexpected network") }
        #expect(await mock.requests == 3)
        await store.retry("kept")
        #expect(await mock.requests == 4)
    }

    @Test func repeatedTransportCancellationStopsAndCanBeRetriedExplicitly() async throws {
        let clock = AvatarTestClock()
        let client = LifecycleAvatarClient(page: page, picture: picture, cancellations: 3, urlCancellation: true)
        let store = InstagramAvatarStore(client: client, now: { clock.date }, sleep: clock.sleep)
        let row = Task { await store.observe("kept") { _ in } }
        defer { row.cancel() }
        for count in 1...2 {
            try await waitUntil {
                let requests = await client.profileRequests(for: "kept")
                return clock.waitingCount == 1 && requests == count
            }
            clock.advance(1)
        }
        try await waitUntil { store.failures["kept"] == .unavailable }
        clock.advance(1_000)
        await Task.yield()
        #expect(await client.profileRequests(for: "kept") == 3)
        await store.retry("kept")
        #expect(store.image(for: "kept") != nil)
        #expect(await client.profileRequests(for: "kept") == 4)
    }

    @Test func disappearingRowCancelsItsScheduledRetry() async throws {
        let clock = AvatarTestClock()
        let mock = MockHTTPClient([.failure(.offline)])
        let store = InstagramAvatarStore(client: mock, now: { clock.date }, sleep: clock.sleep)
        let row = Task { await store.observe("kept") { _ in } }
        try await waitUntil { clock.waitingCount == 1 }
        row.cancel()
        await row.value
        try await waitUntil { clock.waitingCount == 0 }
        clock.advance(1_000)
        #expect(await mock.requests == 1)
    }

    @Test func measurementsSeparateQueueHTMLAndImageDurations() async throws {
        let recorder = AvatarTimingRecorder()
        let client = LifecycleAvatarClient(page: page, picture: picture,
                                          profileDelay: .milliseconds(40), imageDelay: .milliseconds(80))
        let store = InstagramAvatarStore(client: client, measurements: AvatarMeasurements(record: recorder.record))
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<5 { group.addTask { await store.load("timing_\(index)") } }
        }
        let samples = recorder.samples
        for stage in [AvatarMeasurements.Stage.queue, .profileHTML, .image] {
            let values = samples.filter { $0.0 == stage }.map { $0.1 }
            #expect(values.count == 5)
            print("Avatar controlled measurement \(stage.rawValue): \(values)")
        }
        #expect(samples.filter { $0.0 == .profileHTML }.allSatisfy { $0.1 >= .milliseconds(40) })
        #expect(samples.filter { $0.0 == .image }.allSatisfy { $0.1 >= .milliseconds(80) })
        // Five pipelines sharing four permits must include an actual queue wait.
        #expect(samples.contains { $0.0 == .queue && $0.1 >= .milliseconds(120) })
    }

    @Test(arguments: [false, true])
    func cancelledTransportAutomaticallyRecoversForAnExistingSubscriber(urlCancellation: Bool) async throws {
        let clock = AvatarTestClock()
        let client = LifecycleAvatarClient(page: page, picture: picture, cancelFirst: true, urlCancellation: urlCancellation)
        let store = InstagramAvatarStore(client: client, now: { clock.date }, sleep: clock.sleep)
        var displayed = false
        let row = Task { await store.observe("kept") { _ in displayed = true } }
        defer { row.cancel() }
        try await waitUntil { clock.waitingCount == 1 }
        clock.advance(1)
        try await waitUntil { displayed }
        #expect(await client.profileRequests(for: "kept") == 2)
        #expect(store.failures["kept"] == nil)
    }
}

private actor LifecycleAvatarClient: HTTPClient {
    let page: Data
    let picture: Data
    var heldUser: String?
    var cancellations: Int
    let urlCancellation: Bool
    var held = false
    private var firstFailure: PeelError?
    private let profileDelay: Duration
    private let imageDelay: Duration
    private var waiter: CheckedContinuation<Void, Never>?
    private var profiles: [String: Int] = [:]

    init(page: Data, picture: Data, heldUser: String? = nil, cancelFirst: Bool = false,
         firstFailure: PeelError? = nil, cancellations: Int = 0, urlCancellation: Bool = false, profileDelay: Duration = .zero, imageDelay: Duration = .zero) {
        self.page = page
        self.picture = picture
        self.heldUser = heldUser
        self.cancellations = max(cancellations, cancelFirst ? 1 : 0)
        self.urlCancellation = urlCancellation
        self.firstFailure = firstFailure
        self.profileDelay = profileDelay
        self.imageDelay = imageDelay
    }
    func profileRequests(for username: String) -> Int { profiles[username, default: 0] }
    func release() { waiter?.resume(); waiter = nil }
    func data(for request: URLRequest, maxBytes: Int) async throws -> Data {
        if request.url?.host == "www.instagram.com", let user = request.url?.lastPathComponent {
            profiles[user, default: 0] += 1
            if let failure = firstFailure { firstFailure = nil; throw failure }
            try await Task.sleep(for: profileDelay)
            if cancellations > 0 {
                cancellations -= 1
                if urlCancellation { throw URLError(.cancelled) }
                throw CancellationError()
            }
            if user == heldUser {
                held = true
                await withCheckedContinuation { waiter = $0 }
                try Task.checkCancellation()
            }
            return page
        }
        try await Task.sleep(for: imageDelay)
        return picture
    }
}

private final class AvatarTimingRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(AvatarMeasurements.Stage, Duration)] = []
    var samples: [(AvatarMeasurements.Stage, Duration)] { lock.withLock { values } }
    func record(_ stage: AvatarMeasurements.Stage, _ duration: Duration) {
        lock.withLock { values.append((stage, duration)) }
    }
}
