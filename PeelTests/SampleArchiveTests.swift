import Foundation
import Testing
@testable import Peel

@MainActor
struct SampleArchiveTests {
    @Test func bundledArchiveUsesProductionParser() async throws {
        let url = try #require(Bundle(for: PeelModel.self).url(forResource: "Peel-Sample-Archive", withExtension: "zip"))
        let files = try InstagramZIPReader.extractLists(from: Data(contentsOf: url))
        #expect(Set(files.map { $0.0 }) == [
            "connections/followers_and_following/followers_1.json",
            "connections/followers_and_following/following.json"
        ])
        for (_, data) in files {
            _ = try JSONSerialization.jsonObject(with: data)
        }
        let result = try await ImportService().importZIP(url)
        let following = Set(result.following)
        let followers = Set(result.followers)
        #expect(result.following.count == 35)
        #expect(result.followers.count == 30)
        #expect(following.count == 35)
        #expect(followers.count == 30)
        #expect(following.union(followers).count == 50)
        #expect(following.intersection(followers).count == 15)
        #expect(following.subtracting(followers).count == 20)
        #expect(followers.subtracting(following).count == 15)
        #expect(Set(["apple", "google", "meta", "microsoft", "nvidia", "openai", "github", "adobe", "spotify", "figma"]).isSubset(of: following.union(followers)))
    }

    @Test func sampleAvatarDisplayAndRetryRemainOffline() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let demo = PeelModel(demo: true, defaults: fixture.defaults)
        await demo.importSampleArchive().value
        try #require(demo.failure == nil)
        let mock = MockHTTPClient([])
        let store = InstagramAvatarStore(client: mock)
        let names = Set(demo.followingNames + demo.followerNames)
        #expect(names.count == 50)
        for username in names {
            // Exercise the same loading and retry entry points used by the avatar view.
            let avatar = InstagramAvatar(username: username, allowsNetwork: !demo.isDemo, store: store)
            await avatar.load()
            await avatar.retry()
        }
        #expect(await mock.requests == 0)
        #expect(store.images.isEmpty)
        #expect(store.failures.isEmpty)
    }

    @Test func sampleImportIsIsolatedAndStartsWithFreshProgress() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(LegacyFixtures.queue, forKey: "peel-native-queue-v1")
        fixture.defaults.set(LegacyFixtures.preferences, forKey: "peel-native-preferences-v1")
        let store = MockProgressStore()
        let demo = PeelModel(demo: true, defaults: fixture.defaults, progressStore: store)
        await demo.importSampleArchive().value
        #expect(demo.failure == nil)
        #expect(demo.queue.users.count == 20)
        #expect(demo.mutualUsers.count == 15)
        #expect(demo.reverseUsers.count == 15)
        #expect(demo.queue.done.isEmpty)
        #expect(demo.excluded.isEmpty)
        #expect(demo.nonMutualReviewed.isEmpty)
        #expect(demo.mutualReviewed.isEmpty)
        let first = try #require(demo.queue.users.first)
        demo.markReviewed(first, mode: .unfollow)
        await demo.importSampleArchive().value
        #expect(demo.queue.done.isEmpty)
        #expect(store.writes == 0)
        #expect(fixture.defaults.data(forKey: "peel-native-queue-v1") == LegacyFixtures.queue)
        #expect(fixture.defaults.data(forKey: "peel-native-preferences-v1") == LegacyFixtures.preferences)
        let real = try await fixture.restoredModel()
        await real.importSampleArchive().value
        #expect(real.queue.users == ["peel_fixture_a", "peel_fixture_b"])
        #expect(real.followingNames == ["peel_fixture_a", "peel_fixture_b", "peel_fixture_mutual"])
    }
}
