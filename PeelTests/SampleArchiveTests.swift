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

    @Test func sampleAvatarsUseTheNormalProfilePhotoLoader() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let demo = PeelModel(demo: true, defaults: fixture.defaults)
        await demo.importSampleArchive().value
        try #require(demo.failure == nil)
        let page = Data(#"<meta property="og:image" content="https://cdninstagram.com/fixture.png">"#.utf8)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg=="))
        let names = Set(demo.followingNames + demo.followerNames)
        #expect(names.count == 50)
        let replies: [MockHTTPClient.Reply] = names.flatMap { _ in [.data(page), .data(png)] }
        let mock = MockHTTPClient(replies)
        let store = InstagramAvatarStore(client: mock)
        for username in names {
            let avatar = InstagramAvatar(username: username, allowsNetwork: true, store: store)
            await avatar.load()
            #expect(store.image(for: username) != nil)
            await avatar.retry() // Already loaded photos reuse the normal memory cache.
        }
        #expect(await mock.requests == 100)
        #expect(store.images.count == 50)
        #expect(store.failures.isEmpty)
        let requests = await mock.recordedRequests
        let profileURLs = Set(requests.compactMap { $0.request.url }.filter { $0.host == "www.instagram.com" })
        #expect(profileURLs == Set(names.compactMap { InstagramEndpoints.profile($0) }))
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
    @Test func keepingSamplePersistsProgressWithoutCopyingDemoLoginAndEnablesLiveReview() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let live = try await fixture.restoredModel()
        let demo = PeelModel(demo: true, defaults: fixture.defaults)
        await demo.importSampleArchive().value
        let user = try #require(demo.queue.users.first)
        demo.markReviewed(user, mode: .unfollow)
        demo.toggleExclude(user)
        let mutual = try #require(demo.mutualUsers.first)
        demo.markReviewed(mutual, mode: .mutual)
        try live.retainSampleLists(from: demo)
        #expect(!live.isDemo)
        #expect(!live.instagramLoginConfirmed)
        #expect(live.queue.users.count == 20)
        #expect(live.doneSet.contains(user))
        #expect(live.excluded.contains(user))
        #expect(live.mutualReviewed.contains(mutual))
        let restored = try await fixture.restoredModel()
        #expect(restored.mutualUsers.count == 15)
        #expect(restored.doneSet.contains(user))
        #expect(restored.excluded.contains(user))
        #expect(!restored.instagramLoginConfirmed)
        live.instagramLoginConfirmed = true
        live.startBrowser(mode: .mutual, at: mutual)
        #expect(live.instagramUser == mutual)
        #expect(live.browserUsers.count == 15)
        #expect(!live.demoRestrictionRequested)
    }

    @Test func keepingSampleNeverReplacesPersonalListsOrProgress() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let live = try await fixture.restoredModel()
        live.excluded = ["personal"]
        let before = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        let demo = PeelModel(demo: true, defaults: fixture.defaults)
        await demo.importSampleArchive().value
        #expect(!live.canReceiveSampleLists)
        #expect(throws: PeelError.invalidBackup) { try live.retainSampleLists(from: demo) }
        #expect(live.excluded == ["personal"])
        #expect(live.followingNames.isEmpty)
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == before)
    }

    @Test func failedSampleSaveLeavesBothWorkspacesIntactAndCanBeRetried() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let store = MockProgressStore()
        let live = PeelModel(defaults: fixture.defaults, progressStore: store)
        await live.reloadSavedData().value
        let demo = PeelModel(demo: true, defaults: fixture.defaults)
        await demo.importSampleArchive().value
        store.failWrites = true
        #expect(throws: PeelError.persistence) { try live.retainSampleLists(from: demo) }
        #expect(live.queue.users.isEmpty)
        #expect(live.followingNames.isEmpty)
        #expect(store.bytes.2 == nil)
        #expect(demo.queue.users.count == 20)
        #expect(live.canReceiveSampleLists)
        store.failWrites = false
        try live.retainSampleLists(from: demo)
        #expect(live.queue.users.count == 20)
        #expect(store.writes == 1)
    }

    @Test func onlyCompletedSampleImportsCanBeKeptAndResetClearsEligibility() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let live = try await fixture.restoredModel()
        let demo = PeelModel(demo: true, defaults: fixture.defaults)
        #expect(throws: PeelError.invalidBackup) { try live.retainSampleLists(from: demo) }
        await demo.importSampleArchive().value
        #expect(demo.hasImportedSample)
        demo.resetLists()
        #expect(!demo.hasImportedSample)
        #expect(throws: PeelError.invalidBackup) { try live.retainSampleLists(from: demo) }
        #expect(throws: PeelError.invalidBackup) { try live.retainSampleLists(from: live) }
    }

    @Test func restoringOrCorruptPersonalWorkspaceCannotReceiveSample() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data("{broken".utf8), forKey: DefaultsProgressStore.queueKey)
        let live = PeelModel(defaults: fixture.defaults)
        let demo = PeelModel(demo: true, defaults: fixture.defaults)
        #expect(!live.canReceiveSampleLists)
        await demo.importSampleArchive().value
        await live.reloadSavedData().value
        #expect(!live.canReceiveSampleLists)
        #expect(throws: PeelError.invalidBackup) { try live.retainSampleLists(from: demo) }
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.queueKey) == Data("{broken".utf8))
    }

    @Test func restrictedActionsAndCancelledExitLeaveDemoAndPersonalDataIntact() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let live = try await fixture.restoredModel()
        let before = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        let demo = PeelModel(demo: true, defaults: fixture.defaults)
        let mode = PeelDemoMode()
        mode.toggle()
        demo.startBrowser(mode: .mutual)
        #expect(demo.demoRestrictionRequested)
        #expect(demo.instagramUser == nil)
        mode.toggle()
        #expect(mode.exitRequested)
        #expect(mode.isEnabled)
        mode.exitRequested = false // Native Cancel dismisses only the request.
        #expect(mode.isEnabled)
        #expect(live.followingNames.isEmpty)
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == before)
        mode.exit()
        #expect(!mode.isEnabled)
    }

    @Test(arguments: [true, false])
    func transferRejectsActiveImportsInEitherWorkspace(demoIsImporting: Bool) async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let importer = ControlledImporter()
        let live = PeelModel(defaults: fixture.defaults, importer: importer)
        await live.reloadSavedData().value
        let demo = PeelModel(demo: true, defaults: fixture.defaults,
                             importer: demoIsImporting ? importer : ImportService())
        if demoIsImporting {
            let first = demo.importSampleArchive()
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while await importer.count < 1, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try #require(await importer.count == 1)
            await importer.finish(0, following: ["apple"])
            await first.value
        } else {
            await demo.importSampleArchive().value
        }
        try #require(demo.hasImportedSample)
        let task = demoIsImporting ? demo.importSampleArchive()
            : live.importZIP(URL(fileURLWithPath: "/pending.zip"))
        #expect(throws: PeelError.invalidBackup) { try live.retainSampleLists(from: demo) }
        #expect(live.followingNames.isEmpty)
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == nil)
        let expectedCount = demoIsImporting ? 2 : 1
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await importer.count < expectedCount, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await importer.count == expectedCount)
        if demoIsImporting { demo.cancelOperation() } else { live.cancelOperation() }
        await importer.finish(expectedCount - 1, following: ["stale"])
        await task.value
        #expect(live.followingNames.isEmpty)
    }

}
