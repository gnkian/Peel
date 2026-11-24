import Foundation
import Testing
@testable import Peel

@MainActor
struct PersistenceFailureTests {
    @Test func usernameValidationPreservesExistingAcceptanceRules() {
        let boundaryCases = ["", "a", "A_0.z", String(repeating: "a", count: 30),
                             String(repeating: "a", count: 31), "a/b", "@apple",
                             "a\n", "a\r\n", "é", "😀", "a b", "a\u{2028}"]
        let byteCases = (0...127).compactMap { UnicodeScalar($0).map { "a" + String($0) } }
        for value in boundaryCases + byteCases {
            let previous = value.range(of: "^[a-zA-Z0-9._]{1,30}$", options: .regularExpression) != nil
            #expect(UsernameRules.valid(value) == previous, "Changed acceptance for \(value.debugDescription)")
        }
    }

    @Test(arguments: [-1, Int.min, Int.max])
    func unsafeCursorsAreRejected(_ cursor: Int) throws {
        var state = SavedSnapshot.empty
        state.queue = QueueState(users: ["peel_a"], cursor: cursor)
        #expect(throws: PeelError.invalidBackup) { try SavedStateValidator.validate(state) }
    }

    @Test func invalidNamesAndDuplicateReviewMarksAreRejected() throws {
        var state = SavedSnapshot.empty
        state.queue = QueueState(users: ["peel_a"], done: ["peel_a", "peel_a"])
        #expect(throws: PeelError.invalidBackup) { try SavedStateValidator.validate(state) }
        state.queue = QueueState()
        state.preferences.following = ["bad/path"]
        #expect(throws: PeelError.invalidBackup) { try SavedStateValidator.validate(state) }
    }

    @Test func corruptStartupDoesNotOverwriteAnySavedBytes() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let bad = Data("{broken".utf8)
        fixture.defaults.set(bad, forKey: DefaultsProgressStore.queueKey)
        let model = try await fixture.restoredModel()
        #expect(model.failure?.error == .corruptSavedData)
        #expect(model.exportFile() == nil)
        model.toggleExclude("peel_a")
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.queueKey) == bad)
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == nil)
    }

    @Test func checkpointRecoversInterruptedLegacyKeyUpdate() throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let store = DefaultsProgressStore(defaults: fixture.defaults)
        var state = SavedSnapshot.empty
        state.queue = QueueState(users: ["peel_a"])
        try store.save(state)
        fixture.defaults.set(Data("partial".utf8), forKey: DefaultsProgressStore.queueKey)
        let decoded = try DefaultsProgressStore.decode(store.read())
        #expect(decoded.queue.users == ["peel_a"])
    }

    @Test func failedStoreWriteRestoresLastCommittedState() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let store = MockProgressStore()
        let model = PeelModel(defaults: fixture.defaults, progressStore: store)
        await model.reloadSavedData().value
        model.queue = QueueState(users: ["peel_a"])
        let before = store.bytes.2
        store.failWrites = true
        model.queue = QueueState(users: ["peel_b"])
        #expect(model.queue.users == ["peel_a"])
        #expect(model.failure?.error == .persistence)
        #expect(store.bytes.2 == before)
    }

    @Test func failedExportReturnsNoShareURLAndShowsError() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = PeelModel(defaults: fixture.defaults, writeExport: { _, _ in throw PeelError.exportFailed })
        await model.reloadSavedData().value
        #expect(model.exportFile() == nil)
        #expect(model.failure?.error == .exportFailed)
    }

    @Test func nextWaitsForProfileLoadBeforeMarkingReviewed() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["peel_a"])
        #expect(model.openNext())
        #expect(model.queue.done.isEmpty)
        model.profileDidLoad("peel_a", requestID: model.browserRequestID)
        #expect(model.queue.done == ["peel_a"])
    }

    @Test func retrySavesTheFailedCandidateInsteadOfTheRollback() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let store = MockProgressStore()
        let model = PeelModel(defaults: fixture.defaults, progressStore: store)
        await model.reloadSavedData().value
        model.queue = QueueState(users: ["peel_a"])
        store.failWrites = true
        model.queue = QueueState(users: ["peel_b"])
        #expect(model.queue.users == ["peel_a"])
        store.failWrites = false
        model.retryLastOperation()
        #expect(model.queue.users == ["peel_b"])
        #expect(model.failure == nil)
    }

    @Test func filePickerCancellationIsNotAnError() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.report(CocoaError(.userCancelled), operation: .chooseZIP)
        model.report(URLError(.cancelled), operation: .chooseRestore)
        #expect(model.failure == nil)
    }

    @Test func extremeBrowserHistoryIndexCannotOverflow() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.browserIndex = Int.max
        model.previousInBrowser()
        #expect(!model.nextInBrowser())
    }

    @Test func invalidBackupCannotReplaceExistingSavedProgress() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["peel_a"])
        let before = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var file = try JSONDecoder().decode(ProgressFile.self, from: LegacyFixtures.backup)
        file.state.cursor = Int.min
        try JSONEncoder().encode(file).write(to: url)
        await model.restore(url).value
        #expect(model.failure?.error == .invalidBackup)
        #expect(model.queue.users == ["peel_a"])
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == before)
    }
}
