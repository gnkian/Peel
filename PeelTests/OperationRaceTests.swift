import Foundation
import Testing
@testable import Peel

@MainActor
struct OperationRaceTests {
    private func wait(_ importer: ControlledImporter, count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await importer.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await importer.count == count)
    }

    enum ImportSource: CaseIterable { case zip, following, followers, restore, sample }

    @Test(arguments: ImportSource.allCases)
    func importRejectsConflictingEditsAndUnlocksAfterCompletion(source: ImportSource) async throws {
        let demo = source == .sample
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let importer = ControlledImporter()
        let model = PeelModel(demo: demo, defaults: fixture.defaults, importer: importer)
        if !demo { await model.reloadSavedData().value }
        model.followingNames = ["existing", "mutual"]
        model.followerNames = ["follower", "mutual"]
        model.compare()
        let url = URL(fileURLWithPath: "/fixture")
        let task: Task<Void, Never>
        switch source {
        case .zip: task = model.importZIP(url)
        case .following: task = model.importList([url], kind: .following)
        case .followers: task = model.importList([url], kind: .followers)
        case .restore: task = model.restore(url)
        case .sample: task = model.importSampleArchive()
        }
        try await wait(importer, count: 1)
        #expect(!model.canEditLists)
        model.toggleExclude("existing")
        model.markReviewed("existing", mode: .unfollow)
        model.markReviewed("follower", mode: .followers)
        model.markReviewed("mutual", mode: .mutual)
        model.start(at: "mutual")
        model.compare()
        model.startBrowser(mode: .unfollow)
        #expect(!model.openNext())
        #expect(!model.nextInBrowser())
        #expect(model.operationState.isRunning)
        #expect(!model.excluded.contains("existing"))
        #expect(!model.doneSet.contains("existing"))
        #expect(!model.nonMutualReviewed.contains("follower"))
        #expect(!model.mutualReviewed.contains("mutual"))
        #expect(model.queue.users == ["existing"])
        #expect(model.instagramUser == nil)
        await importer.finish(0, following: ["replacement"])
        await task.value
        #expect(model.failure == nil)
        #expect(model.canEditLists)
        if source == .following || source == .followers {
            #expect(model.queue.users == ["existing"])
        } else {
            #expect(model.queue.users == ["replacement"])
        }
        if source == .followers {
            #expect(model.followerNames == ["replacement"])
        } else {
            #expect(model.followingNames == ["replacement"])
        }
        model.toggleExclude("replacement")
        #expect(model.excluded.contains("replacement"))
        if !demo {
            let restored = try await fixture.restoredModel()
            #expect(restored.queue.users == model.queue.users)
            #expect(restored.followingNames == model.followingNames)
            #expect(restored.followerNames == model.followerNames)
        }
    }

    @Test func cancellingImportReenablesEditsAndRejectsLateResult() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let importer = ControlledImporter()
        let model = PeelModel(defaults: fixture.defaults, importer: importer)
        await model.reloadSavedData().value
        let task = model.importZIP(URL(fileURLWithPath: "/fixture.zip"))
        try await wait(importer, count: 1)
        model.cancelOperation()
        #expect(model.canEditLists)
        model.toggleExclude("kept")
        await importer.finish(0, following: ["stale"])
        await task.value
        #expect(model.excluded == ["kept"])
        #expect(model.followingNames.isEmpty)
        #expect((try await fixture.restoredModel()).excluded == ["kept"])
    }

    @Test func cancelledImportCannotOverwriteReset() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let importer = ControlledImporter()
        let model = PeelModel(defaults: fixture.defaults, importer: importer)
        await model.reloadSavedData().value
        let old = model.importZIP(URL(fileURLWithPath: "/fixture.zip"))
        try await wait(importer, count: 1)
        model.resetLists()
        await importer.finish(0, following: ["peel_old"])
        await old.value
        #expect(model.queue.users.isEmpty)
        #expect((try await fixture.restoredModel()).queue.users.isEmpty)
        #expect(model.failure == nil)
    }

    @Test func olderImportCannotOverwriteNewerImport() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let importer = ControlledImporter()
        let model = PeelModel(defaults: fixture.defaults, importer: importer)
        await model.reloadSavedData().value
        let old = model.importZIP(URL(fileURLWithPath: "/old.zip"))
        try await wait(importer, count: 1)
        let new = model.importZIP(URL(fileURLWithPath: "/new.zip"))
        try await wait(importer, count: 2)
        await importer.finish(1, following: ["peel_new"])
        await new.value
        await importer.finish(0, following: ["peel_old"])
        await old.value
        #expect(model.queue.users == ["peel_new"])
        #expect((try await fixture.restoredModel()).queue.users == ["peel_new"])
    }

    @Test func failedImportCommitPreservesSavedAndInMemoryState() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let importer = ControlledImporter()
        let store = MockProgressStore()
        let model = PeelModel(defaults: fixture.defaults, progressStore: store, importer: importer)
        await model.reloadSavedData().value
        model.queue = QueueState(users: ["peel_existing"])
        let before = store.bytes.2
        store.failWrites = true
        let task = model.importZIP(URL(fileURLWithPath: "/fixture.zip"))
        try await wait(importer, count: 1)
        await importer.finish(0, following: ["peel_replacement"])
        await task.value
        #expect(model.failure?.error == .persistence)
        #expect(model.canEditLists)
        #expect(model.queue.users == ["peel_existing"])
        #expect(store.bytes.2 == before)
    }
}
