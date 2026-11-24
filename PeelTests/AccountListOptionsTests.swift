import Foundation
import Testing
@testable import Peel

struct AccountListOptionsTests {
    @Test(arguments: AccountListFilter.allCases)
    func filtersKeepOriginalMembership(_ filter: AccountListFilter) {
        let names = ["pending", "done", "excluded", "both"]
        let reviewed: Set<String> = ["done", "both"]
        let excluded: Set<String> = ["excluded", "both"]
        let expected: [String]
        switch filter {
        case .remaining: expected = ["pending"]
        case .all: expected = names
        case .reviewed: expected = ["done", "both"]
        case .excluded: expected = ["excluded", "both"]
        }
        #expect(names.filter { filter.includes($0, reviewed: reviewed, excluded: excluded) } == expected)
    }

    @Test func sortingPreservesBothExistingPolicies() {
        let names = ["peel2", "peel10", "alex"]
        #expect(AccountListSort.original.ordered(names) == names)
        #expect(AccountListSort.original.ordered(names, naturally: true) == names)
        #expect(AccountListSort.ascending.ordered(names) == ["alex", "peel10", "peel2"])
        #expect(AccountListSort.descending.ordered(names) == ["peel2", "peel10", "alex"])
        #expect(AccountListSort.ascending.ordered(names, naturally: true) == ["alex", "peel2", "peel10"])
        #expect(AccountListSort.descending.ordered(names, naturally: true) == ["peel10", "peel2", "alex"])
    }
}
