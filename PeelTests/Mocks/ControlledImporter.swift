import Foundation
@testable import Peel

actor ControlledImporter: ImportServicing {
    private var continuations: [CheckedContinuation<ImportResult, Error>] = []
    var count: Int { continuations.count }

    func importZIP(_ url: URL) async throws -> ImportResult {
        // Deliberately ignores cancellation to exercise the model's generation guard.
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func importList(_ urls: [URL], kind: ListKind) async throws -> [String] {
        guard let url = urls.first else { throw PeelError.unreadableFile }
        return try await importZIP(url).following
    }

    func restore(_ url: URL, current: SavedSnapshot) async throws -> SavedSnapshot {
        let result = try await importZIP(url)
        return SavedSnapshot(
            queue: QueueState(users: result.following, following: result.following.count, followers: 0, mode: "comparison"),
            preferences: PeelPreferences(excluded: [], nonMutualReviewed: [], mutualReviewed: [],
                                         followers: [], following: result.following))
    }
    func finish(_ index: Int, following: [String]) {
        continuations[index].resume(returning: ImportResult(following: following, followers: []))
    }
}
