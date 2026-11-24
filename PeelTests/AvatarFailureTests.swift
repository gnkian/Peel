import Foundation
import Testing
@testable import Peel

@MainActor
struct AvatarFailureTests {
    private let page = Data(#"<meta property="og:image" content="https://cdninstagram.com/fixture.png">"#.utf8)
    private func png() throws -> Data {
        try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg=="))
    }

    @Test(arguments: [
        #"<meta property="og:image" content="https://cdninstagram.com/a.png?a=1&amp;b=2">"#,
        #"<meta content="https://cdninstagram.com/a.png?a=1&amp;b=2" property="og:image">"#
    ])
    func workingMetadataVariantsStaySupported(_ html: String) throws {
        #expect(try AvatarMetadata.imageURL(in: html).absoluteString == "https://cdninstagram.com/a.png?a=1&b=2")
    }

    @Test func changedMetadataAndUntrustedHostsFailSafely() {
        #expect(throws: PeelError.unsupportedFormat) { try AvatarMetadata.imageURL(in: "<html>changed</html>") }
        #expect(throws: PeelError.invalidURL) {
            try AvatarMetadata.imageURL(in: #"<meta property="og:image" content="https://cdninstagram.com.evil.example/a.png">"#)
        }
    }

    @Test func offlineAvatarCanBeRetriedWithoutRelaunch() async throws {
        let mock = MockHTTPClient([.failure(.offline)])
        let store = InstagramAvatarStore(client: mock)
        await store.load("peel_a")
        #expect(store.failures["peel_a"] == .offline)
        await mock.append([.data(page), .data(try png())])
        await store.retry("peel_a")
        #expect(store.image(for: "peel_a") != nil)
        #expect(store.failures["peel_a"] == nil)
    }

    @Test func evictionDoesNotPermanentlySuppressReload() async throws {
        let picture = try png()
        let mock = MockHTTPClient([.data(page), .data(picture), .data(page), .data(picture), .data(page), .data(picture)])
        let store = InstagramAvatarStore(client: mock, capacity: 1)
        await store.load("peel_a")
        await store.load("peel_b")
        #expect(store.image(for: "peel_a") == nil)
        await store.load("peel_a")
        #expect(store.image(for: "peel_a") != nil)
        #expect(await mock.requests == 6)
    }

    @Test func rateLimitBlocksOtherAvatarRequestsUntilCooldown() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let mock = MockHTTPClient([.failure(.rateLimited(now.addingTimeInterval(120)))])
        let store = InstagramAvatarStore(client: mock, now: { now })
        await store.load("peel_a")
        await store.retry("peel_a")
        await store.load("peel_b")
        #expect(await mock.requests == 1)
        #expect(store.image(for: "peel_a") == nil)
    }

    @Test func demoNeverRequestsAvatars() async {
        let mock = MockHTTPClient([])
        let store = InstagramAvatarStore(client: mock)
        await store.load("peeldemo_follower1")
        #expect(await mock.requests == 0)
    }

    @Test func malformedImageLeavesFallbackAndAnExplicitFailure() async {
        let mock = MockHTTPClient([.data(page), .data(Data("invalid".utf8))])
        let store = InstagramAvatarStore(client: mock)
        await store.load("peel_a")
        #expect(store.image(for: "peel_a") == nil)
        #expect(store.failures["peel_a"] == .unavailable)
    }

    @Test func queuedAvatarsPauseAfterRateLimitInsteadOfDrainingQueue() async throws {
        let until = Date().addingTimeInterval(60)
        let mock = MockHTTPClient(Array(repeating: .failure(.rateLimited(until)), count: 12), holdingReplies: true)
        let store = InstagramAvatarStore(client: mock)
        let finished = AsyncStream<Void>.makeStream()
        defer { finished.continuation.finish() }
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask { @MainActor in
                    await store.load("peel_\(index)")
                    finished.continuation.yield(())
                }
            }
            await mock.waitForRequests(4)
            await mock.resumeReplies()
            var iterator = finished.stream.makeAsyncIterator()
            for _ in 0..<4 { _ = await iterator.next() }
            group.cancelAll()
        }
        #expect(await mock.requests == 4)
    }
}
