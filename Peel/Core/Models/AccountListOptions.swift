import Foundation

/// UI-only choices; these identifiers are never written into saved progress.
enum AccountListFilter: CaseIterable, Identifiable {
    case remaining, all, reviewed, excluded
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .remaining: "Remaining"
        case .all: "All"
        case .reviewed: "Reviewed"
        case .excluded: "Excluded"
        }
    }

    func includes(_ username: String, reviewed: Set<String>, excluded: Set<String>,
                  mode: ReviewMode = .unfollow) -> Bool {
        switch self {
        case .remaining: !reviewed.contains(username) && (mode != .unfollow || !excluded.contains(username))
        case .all: true
        case .reviewed: reviewed.contains(username)
        case .excluded: excluded.contains(username)
        }
    }
}

enum AccountListSort: CaseIterable, Identifiable {
    case original, ascending, descending
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .original: "Original order"
        case .ascending: "A–Z"
        case .descending: "Z–A"
        }
    }

    /// Preserve the existing lexical Unfollowers order and natural relationship-list order.
    func ordered(_ usernames: [String], naturally: Bool = false) -> [String] {
        switch self {
        case .original: usernames
        case .ascending:
            naturally ? usernames.sorted { $0.localizedStandardCompare($1) == .orderedAscending } : usernames.sorted()
        case .descending:
            naturally ? usernames.sorted { $0.localizedStandardCompare($1) == .orderedDescending } : usernames.sorted(by: >)
        }
    }
}
