import Foundation
import Testing
@testable import Peel

/// Synthetic v1 fixtures: no real account data or credentials.
enum LegacyFixtures {
    static let queue = Data(#"{"users":["peel_fixture_a","peel_fixture_b"],"following":3,"followers":2,"done":["peel_fixture_a"],"cursor":1,"lastOpened":"peel_fixture_a","mode":"comparison"}"#.utf8)
    static let preferences = Data(#"{"excluded":["peel_fixture_b"],"nonMutualReviewed":["peel_fixture_c"],"followers":["peel_fixture_c","peel_fixture_mutual"],"following":["peel_fixture_a","peel_fixture_b","peel_fixture_mutual"]}"#.utf8)
    static let backup = Data(#"{"format":"follow-manager-backup-v1","exportedAt":"2026-01-01T00:00:00Z","state":{"users":["peel_fixture_a"],"done":[],"cursor":0,"mode":"comparison"}}"#.utf8)
}

/// Each test owns a disposable domain. App defaults are never used by model tests.
@MainActor
final class ModelFixture {
    let suiteName = "PeelTests." + UUID().uuidString
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func restoredModel() async throws -> PeelModel {
        let model = PeelModel(defaults: defaults)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isRestoring && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(!model.isRestoring, "Model restoration timed out")
        return model
    }
}

struct ParserBaselineTests {
    @Test func jsonNormalizesAndDeduplicatesInOriginalOrder() throws {
        let json = #"{"relationships_following":[{"string_list_data":[{"value":"@Peel_One"},{"value":"peel_two"},{"value":"PEEL_ONE"},{"value":"bad/name"}]}]}"#
        #expect(try UsernameParser.parse(text: json, filename: "following.json") == ["peel_one", "peel_two"])
    }

    @Test func htmlSupportsProfileAndExportURLs() throws {
        let html = #"<a href="https://www.instagram.com/_u/Peel_One">one</a><a href="https://instagram.com/peel_two/">two</a>"#
        #expect(try UsernameParser.parse(text: html, filename: "followers_1.html") == ["peel_one", "peel_two"])
    }

    @Test func textSupportsHeadersAndProfileURLs() throws {
        let text = "username\n@Peel_One\nhttps://www.instagram.com/_u/peel_two/\npeel_one\nbad/name"
        #expect(try UsernameParser.parse(text: text, filename: "list.txt") == ["peel_one", "peel_two"])
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) {
            try UsernameParser.parse(text: "{broken", filename: "followers.json")
        }
    }

    @Test func detectsMultipartAndContentKinds() {
        #expect(UsernameParser.detectType(text: "", filename: "followers_2.json") == .followers)
        #expect(UsernameParser.detectType(text: "", filename: "following.html") == .following)
        #expect(UsernameParser.detectType(text: #"{"relationships_following":[]}"#, filename: "data.json") == .following)
        #expect(UsernameParser.detectType(text: "", filename: "unknown.json") == nil)
    }
}

struct LegacyFormatTests {
    @Test func queueDecodesExistingKeys() throws {
        let queue = try JSONDecoder().decode(QueueState.self, from: LegacyFixtures.queue)
        #expect(queue.users == ["peel_fixture_a", "peel_fixture_b"])
        #expect(queue.done == ["peel_fixture_a"])
        #expect(queue.cursor == 1)
        #expect(queue.following == 3)
        #expect(queue.followers == 2)
        #expect(queue.mode == "comparison")
    }

    @Test func preferencesWithoutMutualReviewedRemainCompatible() throws {
        let prefs = try JSONDecoder().decode(PeelPreferences.self, from: LegacyFixtures.preferences)
        #expect(prefs.mutualReviewed == nil)
        #expect(prefs.excluded == ["peel_fixture_b"])
    }

    @Test func minimalV1BackupRoundTripsWithoutNewRequiredFields() throws {
        let decoder = JSONDecoder()
        let backup = try decoder.decode(ProgressFile.self, from: LegacyFixtures.backup)
        #expect(backup.format == "follow-manager-backup-v1")
        #expect(backup.importedFollowing == nil)
        #expect(backup.mutualReviewed == nil)
        let roundTrip = try decoder.decode(ProgressFile.self, from: JSONEncoder().encode(backup))
        #expect(roundTrip.state.users == backup.state.users)
        #expect(roundTrip.exportedAt == backup.exportedAt)
    }
}

@MainActor
struct ModelBaselineTests {
    @Test func comparisonPreservesOrderAndApplicableReviewMarks() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["peel_b", "removed"], done: ["peel_b", "removed"])
        model.followingNames = ["peel_a", "mutual", "peel_b"]
        model.followerNames = ["mutual", "peel_c"]
        model.compare()
        #expect(model.queue.users == ["peel_a", "peel_b"])
        #expect(model.queue.done == ["peel_b"])
        #expect(model.reverseUsers == ["peel_c"])
        #expect(model.mutualUsers == ["mutual"])
        #expect(model.queue.following == 3)
        #expect(model.queue.followers == 2)
    }

    @Test func reviewHistoryAndCountsFollowCurrentSemantics() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["peel_a", "peel_b", "peel_c"])
        model.toggleExclude("peel_b")
        #expect(model.remaining == 2)
        model.startBrowser(mode: .unfollow)
        #expect(model.instagramUser == "peel_a")
        #expect(model.browserReviewedCount == 0)
        model.profileDidLoad("peel_a", requestID: model.browserRequestID)
        #expect(model.browserReviewedCount == 1)
        #expect(model.browserRemaining == 1)
        #expect(model.nextInBrowser())
        #expect(model.instagramUser == "peel_c")
        model.profileDidLoad("peel_c", requestID: model.browserRequestID)
        #expect(model.remaining == 0)
        model.previousInBrowser()
        #expect(model.instagramUser == "peel_a")
        #expect(model.nextInBrowser())
        #expect(!model.nextInBrowser())
        #expect(model.queue.done == ["peel_a", "peel_c"])
    }

    @Test(arguments: [ReviewMode.unfollow, .followers, .mutual])
    func exclusionsSkipEveryReviewMode(_ mode: ReviewMode) async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["unfollow_excluded", "unfollow_pending", "mutual_excluded", "mutual_pending"]
        model.followerNames = ["follower_excluded", "follower_pending", "mutual_excluded", "mutual_pending"]
        model.compare()
        let excluded: Set<String> = ["unfollow_excluded", "follower_excluded", "mutual_excluded"]
        model.excluded = excluded
        let users: [String]
        let expected: [String]
        switch mode {
        case .unfollow:
            users = model.queue.users
            expected = ["unfollow_pending"]
        case .followers:
            users = model.reverseUsers
            expected = ["follower_pending"]
        case .mutual:
            users = model.mutualUsers
            expected = ["mutual_pending"]
        }
        let visible = users.filter {
            AccountListFilter.remaining.includes($0, reviewed: model.reviewed(mode), excluded: excluded, mode: mode)
        }
        #expect(visible == expected)
        #expect(model.remainingCount(mode) == expected.count)
        model.startBrowser(mode: mode)
        #expect(model.instagramUser == expected.first)
        #expect(model.browserRemaining == expected.count)
        for (index, username) in expected.enumerated() {
            #expect(model.instagramUser == username)
            model.profileDidLoad(username, requestID: model.browserRequestID)
            #expect(model.remainingCount(mode) == expected.count - index - 1)
            #expect(model.browserRemaining == model.remainingCount(mode))
            #expect(model.nextInBrowser() == (index < expected.count - 1))
        }
        #expect(model.excluded == excluded)
    }

    @Test func relationshipReviewMarksStaySeparate() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.markReviewed("peel_a", mode: .followers)
        model.markReviewed("peel_b", mode: .mutual)
        #expect(model.nonMutualReviewed == ["peel_a"])
        #expect(model.mutualReviewed == ["peel_b"])
        #expect(model.queue.done.isEmpty)
    }

    @Test(arguments: [ReviewMode.unfollow, .followers, .mutual])
    func exclusionsPersistWithoutRemovingImportedMembership(_ mode: ReviewMode) async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["unfollow", "mutual"]
        model.followerNames = ["follower", "mutual"]
        model.compare()
        let user: String
        switch mode {
        case .unfollow: user = "unfollow"
        case .followers: user = "follower"
        case .mutual: user = "mutual"
        }
        model.toggleExclude(user)
        #expect(model.remainingCount(mode) == 0)
        model.startBrowser(mode: mode)
        #expect(model.instagramUser == nil)
        let restored = try await fixture.restoredModel()
        #expect(restored.excluded == [user])
        #expect(restored.followingNames == ["unfollow", "mutual"])
        #expect(restored.followerNames == ["follower", "mutual"])
        #expect(restored.remainingCount(mode) == 0)
        restored.toggleExclude(user)
        #expect(restored.remainingCount(mode) == 1)
        restored.startBrowser(mode: mode)
        #expect(restored.instagramUser == user)
    }

    @Test func numberColumnKeepsImportedListWidthAfterTrimming() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = (1...100).map { "peel_\($0)" }
        model.compare()
        #expect(model.accountNumberColumnCount == 100)
        model.start(at: "peel_99")
        #expect(model.queue.users == ["peel_99", "peel_100"])
        #expect(model.accountNumberColumnCount == 100)
        model.toggleExclude("peel_99")
        #expect(model.accountNumberColumnCount == 100)
    }

    @Test func trimmingRetainsOnlyRemainingQueueMarks() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["peel_a", "peel_b", "peel_c"], done: ["peel_a", "peel_c"], cursor: 2)
        model.start(at: "peel_b")
        #expect(model.queue.users == ["peel_b", "peel_c"])
        #expect(model.queue.done == ["peel_c"])
        #expect(model.queue.cursor == 0)
        #expect(model.queue.lastOpened == nil)
    }

    @Test func legacyRestoreAndNewWritesUseExistingDefaultsKeys() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(LegacyFixtures.queue, forKey: "peel-native-queue-v1")
        fixture.defaults.set(LegacyFixtures.preferences, forKey: "peel-native-preferences-v1")
        fixture.defaults.set(true, forKey: "peel-instagram-login-confirmed")
        let model = try await fixture.restoredModel()
        #expect(model.queue.cursor == 1)
        #expect(model.remaining == 0)
        #expect(model.nonMutualReviewed == ["peel_fixture_c"])
        #expect(model.mutualReviewed.isEmpty)
        #expect(model.instagramLoginConfirmed)
        model.toggleExclude("peel_fixture_b")
        model.markReviewed("peel_fixture_b", mode: .unfollow)
        let reloaded = try await fixture.restoredModel()
        #expect(reloaded.queue.done == ["peel_fixture_a", "peel_fixture_b"])
        #expect(reloaded.excluded.isEmpty)
        #expect(reloaded.followingNames == model.followingNames)
        #expect(reloaded.followerNames == model.followerNames)
    }

    @Test func resetClearsListsButPreservesLogin() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.instagramLoginConfirmed = true
        model.queue = QueueState(users: ["peel_a"], done: ["peel_a"])
        model.excluded = ["peel_a"]
        model.followingNames = ["peel_a"]
        model.followerNames = ["peel_b"]
        model.resetLists()
        let reloaded = try await fixture.restoredModel()
        #expect(reloaded.queue.users.isEmpty)
        #expect(reloaded.excluded.isEmpty)
        #expect(reloaded.followingNames.isEmpty)
        #expect(reloaded.followerNames.isEmpty)
        #expect(reloaded.instagramLoginConfirmed)
    }

    @Test func demoModelCannotWriteIntoRealPersistenceOrOpenReview() throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(LegacyFixtures.queue, forKey: "peel-native-queue-v1")
        fixture.defaults.set(LegacyFixtures.preferences, forKey: "peel-native-preferences-v1")
        fixture.defaults.set(false, forKey: "peel-instagram-login-confirmed")
        let model = PeelModel(demo: true, defaults: fixture.defaults)
        #expect(model.isDemo)
        #expect(!model.isRestoring)
        model.startBrowser(mode: .unfollow)
        #expect(model.instagramUser == nil)
        model.instagramLoginConfirmed = true
        model.toggleExclude("peel_demo_extra")
        model.resetLists()
        #expect(fixture.defaults.data(forKey: "peel-native-queue-v1") == LegacyFixtures.queue)
        #expect(fixture.defaults.data(forKey: "peel-native-preferences-v1") == LegacyFixtures.preferences)
        #expect(!fixture.defaults.bool(forKey: "peel-instagram-login-confirmed"))
    }

    @Test func malformedZIPPreservesPreviousListsAndProgress() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["peel_a"]
        model.followerNames = ["peel_b"]
        model.compare()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a ZIP".utf8).write(to: url)
        await model.importZIP(url).value
        #expect(model.followingNames == ["peel_a"])
        #expect(model.followerNames == ["peel_b"])
        #expect(model.queue.users == ["peel_a"])
        #expect(model.message.hasPrefix("ZIP import failed:"))
    }
}
