import SwiftUI

@MainActor
final class InstagramAvatarStore: ObservableObject {
    static let shared = InstagramAvatarStore()
    @Published private(set) var images: [String: UIImage] = [:]
    @Published private(set) var failures: [String: PeelError] = [:]
    private var tasks: [String: Task<UIImage, Error>] = [:]
    private var retryDates: [String: Date] = [:]
    private var order: [String] = []
    private var cooldown = Date.distantPast
    private let loader: AvatarLoader
    private let gate = AvatarRequestGate()
    private let capacity: Int
    private let now: () -> Date

    init(client: any HTTPClient = URLSessionHTTPClient(), capacity: Int = 150,
         now: @escaping () -> Date = Date.init) {
        loader = AvatarLoader(client: client)
        self.capacity = max(1, capacity)
        self.now = now
    }

    func image(for username: String) -> UIImage? { images[username] }

    func load(_ username: String) async {
        guard UsernameParser.valid(username), !username.hasPrefix("peeldemo_"),
              images[username] == nil, now() >= cooldown,
              now() >= (retryDates[username] ?? .distantPast) else { return }
        if let existing = tasks[username] { _ = try? await existing.value; return }
        let loader = loader
        let gate = gate
        let task = Task {
            try await gate.acquire()
            do {
                let image = try await loader.image(username)
                await gate.release()
                return image
            } catch {
                if let until = (error as? PeelError)?.retryAfter { await gate.pause(until: until) }
                await gate.release()
                throw error
            }
        }
        tasks[username] = task
        defer { tasks[username] = nil }
        await withTaskCancellationHandler {
            do {
                let image = try await task.value
                try Task.checkCancellation()
                if images.count >= capacity, let first = order.first {
                    images[first] = nil
                    order.removeFirst()
                }
                images[username] = image
                order.append(username)
                failures[username] = nil
                retryDates[username] = nil
            } catch is CancellationError {
                // Cancellation remains immediately retryable.
            } catch {
                let error = PeelError.map(error)
                failures[username] = error
                let retry = error.retryAfter ?? now().addingTimeInterval(error == .unsupportedFormat ? 300 : 10)
                retryDates[username] = retry
                if error.retryAfter != nil { cooldown = max(cooldown, retry) }
                if failures.count > 300, let key = failures.keys.first {
                    failures[key] = nil
                    retryDates[key] = nil
                }
            }
        } onCancel: { task.cancel() }
    }

    func retry(_ username: String) async {
        guard now() >= cooldown else { return }
        retryDates[username] = nil
        await load(username)
    }
}

struct InstagramAvatar: View {
    let username: String
    @ObservedObject private var store = InstagramAvatarStore.shared

    var body: some View {
        Group {
            if username.hasPrefix("peeldemo_") {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            } else if let image = store.image(for: username) {
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
            if store.failures[username] != nil {
                Button("Retry Photo") { Task { await store.retry(username) } }
            }
        }
        .accessibilityHidden(true)
        .task(id: username) { if !username.hasPrefix("peeldemo_") { await store.load(username) } }
    }
}
