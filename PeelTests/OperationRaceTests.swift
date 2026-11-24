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
        #expect(model.queue.users == ["peel_existing"])
        #expect(store.bytes.2 == before)
    }
}
