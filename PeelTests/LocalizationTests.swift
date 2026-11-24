import Foundation
import Testing
@testable import Peel

struct LocalizationTests {
    @Test(arguments: [0, 1, 2])
    func englishAccountCountUsesCorrectPlural(_ count: Int) {
        let bundle = Bundle(for: PeelModel.self)
        let value = String(localized: "\(count) accounts shown", bundle: bundle, locale: Locale(identifier: "en"))
        #expect(value == "\(count) \(count == 1 ? "account" : "accounts") shown")
    }

    @Test func englishReviewNounAgreesWithTotal() {
        let bundle = Bundle(for: PeelModel.self)
        for (reviewed, total) in [(0, 1), (1, 1), (1, 2)] {
            let value = String(localized: "\(reviewed) of \(total) accounts reviewed",
                               bundle: bundle, locale: Locale(identifier: "en"))
            #expect(value == "\(reviewed) of \(total) \(total == 1 ? "account" : "accounts") reviewed")
        }
    }

    @Test func choicesResolveEnglishWithoutChangingIdentity() {
        var title = AccountListFilter.remaining.title
        title.locale = Locale(identifier: "en")
        #expect(String(localized: title) == "Remaining")
        #expect(AccountListFilter.remaining.id == .remaining)
        #expect(AccountListSort.original.id == .original)
    }
}
