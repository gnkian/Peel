import Foundation

enum SavedStateValidator {
    static func names(_ names: [String]) throws {
        guard names.count <= 500_000,
              names.allSatisfy(UsernameRules.valid),
              Set(names).count == names.count else { throw PeelError.invalidBackup }
    }

    static func validate(_ state: SavedSnapshot) throws {
        let q = state.queue
        let p = state.preferences
        for list in [q.users, q.done, p.excluded, p.nonMutualReviewed, p.mutualReviewed ?? [], p.following, p.followers] {
            try names(list)
        }
        guard ["none", "comparison"].contains(q.mode),
              q.cursor >= 0, q.cursor < max(1, q.users.count),
              q.following.map({ $0 >= 0 }) ?? true,
              q.followers.map({ $0 >= 0 }) ?? true,
              Set(q.done).isSubset(of: Set(q.users)),
              q.lastOpened.map({ q.users.contains($0) }) ?? true else {
            throw PeelError.invalidBackup
        }
    }

    static func backup(_ file: ProgressFile, merging current: SavedSnapshot) throws -> SavedSnapshot {
        guard file.format == "follow-manager-backup-v1" else { throw PeelError.invalidBackup }
        let snapshot = SavedSnapshot(queue: file.state, preferences: PeelPreferences(
            excluded: file.excluded ?? current.preferences.excluded,
            nonMutualReviewed: file.nonMutualReviewed ?? current.preferences.nonMutualReviewed,
            mutualReviewed: file.mutualReviewed ?? current.preferences.mutualReviewed,
            followers: file.importedFollowers ?? current.preferences.followers,
            following: file.importedFollowing ?? current.preferences.following))
        try validate(snapshot)
        return snapshot
    }
}
