import SwiftUI

@MainActor
final class InstagramAvatarStore: ObservableObject {
    static let shared = InstagramAvatarStore(diskCache: AvatarDiskCache())
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var failures: [String: PeelError] = [:]
    @Published private(set) var cacheBytes: Int64 = 0
    @Published private(set) var cacheRevision = 0
    @Published private(set) var isClearingCache = false
    private let diskCache: AvatarDiskCache?
    private struct PendingImage {
        let id: UUID
        let task: Task<UIImage?, Error>
        var consumers: Set<UUID>
        var resolved = false
    }
    private var tasks: [String: PendingImage] = [:]
    private var retryDates: [String: Date] = [:]
    private var order: [String] = []
    private struct Observer {
        let wake: AsyncStream<Void>.Continuation
        let receive: (UIImage) -> Void
    }
    private var observers: [String: [UUID: Observer]] = [:]
    private var retryTasks: [String: Task<Void, Never>] = [:]
    private var consecutiveFailures: [String: Int] = [:]
    private let sleep: (TimeInterval) async throws -> Void
    private let measurements: AvatarMeasurements
    private var cooldown = Date.distantPast
    private let loader: AvatarLoader
    private let gate: AvatarRequestGate
    private let capacity: Int
    private let now: () -> Date

    init(client: any HTTPClient = URLSessionHTTPClient(), capacity: Int = 150,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         measurements: AvatarMeasurements = AvatarMeasurements(),
         gate: AvatarRequestGate = AvatarRequestGate(), diskCache: AvatarDiskCache? = nil) {
        self.diskCache = diskCache
        self.gate = gate
        self.sleep = sleep
        self.measurements = measurements
        loader = AvatarLoader(client: client, measurements: measurements)
        self.capacity = max(1, capacity)
        self.now = now
    }

    func image(for username: String) -> UIImage? { images[username] }

    /// Remains attached for the row's lifetime, including while a retry is deferred.
    /// The displayed thumbnail belongs to the row, so eviction never blanks a visible photo.
    func observe(_ username: String, allowsNetwork: Bool = true,
                 receive: @escaping (UIImage) -> Void) async {
        guard allowsNetwork, UsernameParser.valid(username), !username.hasPrefix("peeldemo_") else { return }
        let id = UUID()
        let events = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var hasDisplayedImage = false
        observers[username, default: [:]][id] = Observer(wake: events.continuation, receive: { image in
            hasDisplayedImage = true
            receive(image)
        })
        defer {
            events.continuation.finish()
            observers[username]?[id] = nil
            if observers[username]?.isEmpty == true {
                observers[username] = nil
                retryTasks.removeValue(forKey: username)?.cancel()
            }
        }
        if let image = images[username] {
            hasDisplayedImage = true
            receive(image)
        } else {
            // Disk hits are available even during a server cooldown.
            await load(username)
        }
        events.continuation.yield(())
        for await _ in events.stream {
            guard !Task.isCancelled else { return }
            guard !hasDisplayedImage, consecutiveFailures[username, default: 0] < 3 else { continue }
            let delay = max(cooldown, retryDates[username] ?? .distantPast).timeIntervalSince(now())
            if delay > 0 {
                scheduleRetry(username, after: delay)
            } else {
                await load(username)
            }
        }
    }

    private func wake(_ username: String) {
        for observer in observers[username]?.values ?? [:].values { observer.wake.yield(()) }
    }

    private func scheduleRetry(_ username: String, after delay: TimeInterval) {
        guard retryTasks[username] == nil else { return }
        let sleep = sleep
        retryTasks[username] = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.retryTasks[username] = nil
            self.wake(username)
        }
    }

    func retryAvailableAt(_ username: String) -> Date? {
        let date = max(cooldown, retryDates[username] ?? .distantPast)
        return date > now() ? date : nil
    }

    func load(_ username: String, allowsNetwork: Bool = true) async {
        guard allowsNetwork, UsernameParser.valid(username), !username.hasPrefix("peeldemo_"),
              images[username] == nil, !isClearingCache else { return }
        let consumer = UUID()
        let pending: PendingImage
        if var existing = tasks[username] {
            existing.consumers.insert(consumer)
            tasks[username] = existing
            pending = existing
        } else {
            let loader = loader
            let gate = gate
            let measurements = measurements
            let diskCache = diskCache
            let canRequest = { [weak self] in
                guard let self else { return false }
                return !self.isClearingCache && self.now() >= self.cooldown &&
                    self.now() >= (self.retryDates[username] ?? .distantPast)
            }
            let task = Task<UIImage?, Error> {
                try Task.checkCancellation()
                let generation = await diskCache?.currentGeneration()
                if let data = await diskCache?.data(for: username), let image = UIImage(data: data) { return image }
                try Task.checkCancellation()
                guard canRequest() else { return nil }
                try await measurements.measure(.queue) { try await gate.acquire() }
                do {
                    let image = try await loader.image(username)
                    try Task.checkCancellation()
                    if let diskCache, let generation, let data = image.pngData() {
                        // Persistence is best-effort; a full disk must not hide a successfully loaded photo.
                        try? await diskCache.save(data, for: username, generation: generation)
                    }
                    await gate.release()
                    return image
                } catch {
                    if let until = (error as? PeelError)?.retryAfter { await gate.pause(until: until) }
                    await gate.release()
                    throw error
                }
            }
            pending = PendingImage(id: UUID(), task: task, consumers: [consumer])
            tasks[username] = pending
        }
        let requestID = pending.id
        defer { releaseConsumer(consumer, username: username, requestID: requestID) }
        await withTaskCancellationHandler {
            do {
                let result = try await pending.task.value
                try Task.checkCancellation()
                guard tasks[username]?.id == requestID, tasks[username]?.resolved == false, images[username] == nil else { return }
                tasks[username]?.resolved = true
                guard let image = result else { return }
                if images.count >= capacity, let first = order.first {
                    images[first] = nil
                    order.removeFirst()
                }
                images[username] = image
                order.append(username)
                failures[username] = nil
                retryDates[username] = nil
                consecutiveFailures[username] = nil
                for observer in observers[username]?.values ?? [:].values { observer.receive(image) }
                await updateCacheSize()
            } catch is CancellationError {
                recordTransportCancellation(username, requestID: requestID)
            } catch let error as URLError where error.code == .cancelled {
                recordTransportCancellation(username, requestID: requestID)
            } catch {
                guard !Task.isCancelled, tasks[username]?.id == requestID, tasks[username]?.resolved == false else { return }
                tasks[username]?.resolved = true
                let error = PeelError.map(error)
                consecutiveFailures[username, default: 0] += 1
                failures[username] = error
                let retry = error.retryAfter ?? now().addingTimeInterval(error == .unsupportedFormat ? 300 : 10)
                retryDates[username] = retry
                if error.retryAfter != nil { cooldown = max(cooldown, retry) }
                if failures.count > 300, let key = failures.keys.first {
                    failures[key] = nil
                    retryDates[key] = nil
                    consecutiveFailures[key] = nil
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.releaseConsumer(consumer, username: username, requestID: requestID)
            }
        }
    }

    /// Saves thumbnails already in memory, including any loaded before persistent caching was enabled.
    func refreshCacheSize() async throws {
        guard !isClearingCache, let diskCache else { return }
        let revision = cacheRevision
        let generation = await diskCache.currentGeneration()
        for (username, image) in images {
            guard !isClearingCache, cacheRevision == revision else { return }
            if let data = image.pngData() { try await diskCache.save(data, for: username, generation: generation) }
        }
        let bytes = try await diskCache.byteCount(reconcile: true)
        if !isClearingCache, revision == cacheRevision { cacheBytes = bytes }
    }

    private func updateCacheSize() async {
        guard let diskCache else { return }
        let revision = cacheRevision
        if let bytes = try? await diskCache.byteCount(), !isClearingCache, revision == cacheRevision { cacheBytes = bytes }
    }

    func clearCache() async throws {
        guard !isClearingCache else { return }
        isClearingCache = true
        for pending in tasks.values { pending.task.cancel() }
        tasks.removeAll()
        for timer in retryTasks.values { timer.cancel() }
        retryTasks.removeAll()
        images.removeAll()
        order.removeAll()
        defer {
            isClearingCache = false
            cacheRevision += 1
        }
        // Keep retry deadlines and the server cooldown; clearing storage must not bypass rate limits.
        do {
            try await diskCache?.clear()
            cacheBytes = 0
        } catch {
            if let bytes = try? await diskCache?.byteCount() { cacheBytes = bytes }
            throw error
        }
    }

    private func recordTransportCancellation(_ username: String, requestID: UUID) {
        // Row cancellation is teardown; transport cancellation with a live row is recoverable.
        guard !Task.isCancelled, tasks[username]?.id == requestID, tasks[username]?.resolved == false else { return }
        tasks[username]?.resolved = true
        consecutiveFailures[username, default: 0] += 1
        retryDates[username] = now().addingTimeInterval(1)
        if consecutiveFailures[username, default: 0] >= 3 { failures[username] = .unavailable }
    }

    /// A row owns its subscription, not the shared request used by other visible rows.
    private func releaseConsumer(_ consumer: UUID, username: String, requestID: UUID) {
        guard var pending = tasks[username], pending.id == requestID else { return }
        pending.consumers.remove(consumer)
        if pending.consumers.isEmpty {
            tasks[username] = nil
            pending.task.cancel()
            wake(username)
        } else {
            tasks[username] = pending
        }
    }

    func retry(_ username: String, allowsNetwork: Bool = true) async {
        guard allowsNetwork, UsernameParser.valid(username), !username.hasPrefix("peeldemo_") else { return }
        consecutiveFailures[username] = nil
        // Manual retry also respects per-account delays and server-wide Retry-After.
        if let date = retryAvailableAt(username) {
            if observers[username] != nil { scheduleRetry(username, after: date.timeIntervalSince(now())) }
            return
        }
        await load(username, allowsNetwork: allowsNetwork)
        wake(username)
    }
}

private struct AvatarTaskIdentity: Equatable {
    let username: String
    let allowsNetwork: Bool
    let cacheRevision: Int
}

struct InstagramAvatar: View {
    let username: String
    let allowsNetwork: Bool
    @State private var displayedImage: UIImage?
    @State private var retryDate: Date?
    @State private var showsRetryFeedback = false
    @ObservedObject var store: InstagramAvatarStore = .shared

    func load() async { await store.load(username, allowsNetwork: allowsNetwork) }
    func retry() async { await store.retry(username, allowsNetwork: allowsNetwork) }

    var body: some View {
        Group {
            if !allowsNetwork || username.hasPrefix("peeldemo_") {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            } else if let image = displayedImage ?? store.image(for: username) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .contextMenu {
            if allowsNetwork && !username.hasPrefix("peeldemo_") && (store.failures[username] != nil || store.retryAvailableAt(username) != nil) {
                Button("Retry Photo") {
                    retryDate = store.retryAvailableAt(username)
                    showsRetryFeedback = retryDate != nil
                    Task { await retry() }
                }
            }
        }
        .accessibilityHidden(true)
        .alert("Photo Requests Paused", isPresented: $showsRetryFeedback) {
            Button("OK", role: .cancel) { }
        } message: {
            if let retryDate {
                Text("Photo requests can resume after \(retryDate.formatted(date: .omitted, time: .standard)). Keep this list open to retry automatically.",
                     comment: "The variable is the local time when a profile photo retry becomes available.")
            }
        }
        .task(id: AvatarTaskIdentity(username: username, allowsNetwork: allowsNetwork, cacheRevision: store.cacheRevision)) {
            displayedImage = nil
            defer { displayedImage = nil }
            await store.observe(username, allowsNetwork: allowsNetwork) { displayedImage = $0 }
        }
    }
}
