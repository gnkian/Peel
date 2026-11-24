import Foundation
@testable import Peel

actor ControlledImporter: ImportServicing {
    private var continuations: [CheckedContinuation<ImportResult, Error>] = []
    var count: Int { continuations.count }

    func importZIP(_ url: URL) async throws -> ImportResult {
        // Deliberately ignores cancellation to exercise the model's generation guard.
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func importList(_ urls: [URL], kind: ListKind) async throws -> [String] { throw PeelError.unreadableFile }
    func restore(_ url: URL, current: SavedSnapshot) async throws -> SavedSnapshot { throw PeelError.invalidBackup }
    func finish(_ index: Int, following: [String]) {
        continuations[index].resume(returning: ImportResult(following: following, followers: []))
    }
}
