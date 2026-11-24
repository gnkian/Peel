import Foundation

@MainActor
protocol ProgressStore: AnyObject {
    func read() throws -> (Data?, Data?, Data?)
    func save(_ snapshot: SavedSnapshot) throws
}

/// The single checkpoint is authoritative once written. Legacy keys remain readable
/// by older builds. UserDefaults has no durable-write acknowledgement.
@MainActor
final class DefaultsProgressStore: ProgressStore {
    static let queueKey = "peel-native-queue-v1"
    static let preferencesKey = "peel-native-preferences-v1"
    static let checkpointKey = "peel-native-checkpoint-v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func read() throws -> (Data?, Data?, Data?) {
        for key in [Self.queueKey, Self.preferencesKey, Self.checkpointKey] {
            if defaults.object(forKey: key) != nil && defaults.data(forKey: key) == nil {
                throw PeelError.corruptSavedData
            }
        }
        return (defaults.data(forKey: Self.queueKey),
                defaults.data(forKey: Self.preferencesKey),
                defaults.data(forKey: Self.checkpointKey))
    }

    func save(_ snapshot: SavedSnapshot) throws {
        // Encode everything before touching any saved value.
        let encoder = JSONEncoder()
        let checkpoint = try encoder.encode(snapshot)
        let queue = try encoder.encode(snapshot.queue)
        let preferences = try encoder.encode(snapshot.preferences)
        defaults.set(checkpoint, forKey: Self.checkpointKey)
        defaults.set(queue, forKey: Self.queueKey)
        defaults.set(preferences, forKey: Self.preferencesKey)
    }

    nonisolated static func decode(_ data: (Data?, Data?, Data?)) throws -> SavedSnapshot {
        do {
            let decoder = JSONDecoder()
            let snapshot: SavedSnapshot
            if let checkpoint = data.2 {
                snapshot = try decoder.decode(SavedSnapshot.self, from: checkpoint)
            } else {
                snapshot = SavedSnapshot(
                    queue: try data.0.map { try decoder.decode(QueueState.self, from: $0) } ?? QueueState(),
                    preferences: try data.1.map { try decoder.decode(PeelPreferences.self, from: $0) } ?? SavedSnapshot.empty.preferences)
            }
            try SavedStateValidator.validate(snapshot)
            return snapshot
        } catch { throw PeelError.corruptSavedData }
    }
}
