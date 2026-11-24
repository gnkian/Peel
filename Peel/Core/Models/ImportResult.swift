import Foundation

struct ImportResult: Sendable {
    var following: [String]
    var followers: [String]
}

struct SavedSnapshot: Codable, Sendable {
    var queue: QueueState
    var preferences: PeelPreferences

    static var empty: SavedSnapshot {
        SavedSnapshot(queue: QueueState(), preferences: PeelPreferences(
            excluded: [], nonMutualReviewed: [], mutualReviewed: [],
            followers: [], following: []))
    }
}
