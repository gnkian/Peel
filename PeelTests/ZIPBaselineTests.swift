import Foundation
import Testing
@testable import Peel

private final class FixtureBundle: NSObject {}

@MainActor
struct ZIPBaselineTests {
    private func fixtureURL(_ name: String) throws -> URL {
        try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "zip"))
    }

    @Test(arguments: ["stored-json", "deflated-json", "deflated-html"])
    func validExportsImportBothListsAndCompare(_ name: String) async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        await model.importZIP(try fixtureURL(name)).value
        #expect(model.followingNames == ["peel_fixture_a", "peel_fixture_mutual"])
        #expect(model.followerNames == ["peel_fixture_mutual", "peel_fixture_b"])
        #expect(model.queue.users == ["peel_fixture_a"])
        #expect(model.queue.following == 2)
        #expect(model.queue.followers == 2)
        #expect(model.queue.mode == "comparison")
        let reloaded = try await fixture.restoredModel()
        #expect(reloaded.followingNames == model.followingNames)
        #expect(reloaded.followerNames == model.followerNames)
        #expect(reloaded.queue.users == model.queue.users)
    }

    @Test(arguments: ["malformed-json", "missing-followers"])
    func invalidExportsDoNotPartiallyReplaceSavedState(_ name: String) async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["peel_existing"]
        model.followerNames = ["peel_other"]
        model.persistPreferences()
        model.compare()
        await model.importZIP(try fixtureURL(name)).value
        #expect(model.message.hasPrefix("ZIP import failed:"))
        #expect(model.followingNames == ["peel_existing"])
        #expect(model.followerNames == ["peel_other"])
        #expect(model.queue.users == ["peel_existing"])
        let reloaded = try await fixture.restoredModel()
        #expect(reloaded.followingNames == ["peel_existing"])
        #expect(reloaded.queue.users == ["peel_existing"])
    }
}
