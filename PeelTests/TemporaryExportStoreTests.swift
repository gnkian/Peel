import Foundation
import UIKit
import Testing
@testable import Peel

@MainActor
struct TemporaryExportStoreTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func create(_ store: TemporaryExportStore) throws -> URL {
        try store.create(Data("fictional backup".utf8)) { try $0.write(to: $1, options: .atomic) }
    }

    @Test func activeShareAndDismissalKeepFileUntilCompletion() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let url = try create(store)
        let token = try #require(store.beginSharing(url))
        try store.discardUnshared(url)
        try store.retryCleanup()
        #expect(FileManager.default.fileExists(atPath: url.path))
        try store.finishSharing(url, token: token)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func lastConsumerControlsDeletionAndDuplicateCompletionIsHarmless() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let url = try create(store)
        let first = try #require(store.beginSharing(url))
        let second = try #require(store.beginSharing(url))
        try store.finishSharing(url, token: first)
        try store.finishSharing(url, token: first)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try store.finishSharing(url, token: second)
        try store.finishSharing(url, token: second)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func abandonedUnsharedFileIsRemovedButUnrelatedAndImportedFilesSurvive() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let url = try create(store)
        let unrelated = url.deletingLastPathComponent().appendingPathComponent("user-selected.json")
        let imported = root.appendingPathComponent("followers.zip")
        try Data("user document".utf8).write(to: unrelated)
        try Data("import".utf8).write(to: imported)
        try store.discardUnshared(unrelated)
        try store.discardUnshared(imported)
        try store.finishSharing(imported, token: UUID())
        #expect(store.beginSharing(unrelated) == nil)
        try store.discardUnshared(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: unrelated) == Data("user document".utf8))
        #expect(try Data(contentsOf: imported) == Data("import".utf8))
    }

    @Test func partialFailedWriteIsRemovedWithoutTouchingActiveExport() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let active = try create(store)
        let token = try #require(store.beginSharing(active))
        var partial: URL?
        #expect(throws: PeelError.exportFailed) {
            try store.create(Data("partial".utf8)) { data, url in
                partial = url
                try data.write(to: url)
                throw PeelError.exportFailed
            }
        }
        let failedURL = try #require(partial)
        #expect(!FileManager.default.fileExists(atPath: failedURL.path))
        #expect(FileManager.default.fileExists(atPath: active.path))
        try store.finishSharing(active, token: token)
    }

    @Test func repeatedExportsDoNotDeleteEachOthersConsumersOrSharedCopies() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let first = try create(store)
        let second = try create(store)
        let copy = root.appendingPathComponent("saved-copy.json")
        try FileManager.default.copyItem(at: first, to: copy)
        let firstToken = try #require(store.beginSharing(first))
        let secondToken = try #require(store.beginSharing(second))
        try store.finishSharing(second, token: secondToken)
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: copy.path))
        try store.finishSharing(first, token: firstToken)
        #expect(FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func newProcessRegistryRetainsUnconfirmedOldExports() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldStore = TemporaryExportStore(temporaryDirectory: root)
        let old = try create(oldStore)
        _ = oldStore.beginSharing(old)
        let relaunched = TemporaryExportStore(temporaryDirectory: root)
        try relaunched.discardUnshared(old)
        try relaunched.retryCleanup()
        let fresh = try create(relaunched)
        try relaunched.discardUnshared(fresh)
        #expect(FileManager.default.fileExists(atPath: old.path))
        #expect(!FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test func substitutedDirectoryCannotDeleteOutsideStorageAndCleanupCanRetry() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let url = try create(store)
        let token = try #require(store.beginSharing(url))
        let directory = url.deletingLastPathComponent()
        let held = root.appendingPathComponent("held", isDirectory: true)
        let documents = root.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let protected = documents.appendingPathComponent(url.lastPathComponent)
        try Data("protected".utf8).write(to: protected)
        try FileManager.default.moveItem(at: directory, to: held)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: documents)
        #expect(throws: (any Error).self) { try store.finishSharing(url, token: token) }
        #expect(try Data(contentsOf: protected) == Data("protected".utf8))
        #expect(throws: (any Error).self) { try create(store) }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: held, to: directory)
        try store.retryCleanup()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: protected) == Data("protected".utf8))
    }

    @Test func missingTemporaryFileAndUnknownTokenAreSafe() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let url = try create(store)
        let token = try #require(store.beginSharing(url))
        try store.finishSharing(url, token: UUID())
        #expect(FileManager.default.fileExists(atPath: url.path))
        try FileManager.default.removeItem(at: url)
        try store.finishSharing(url, token: token)
        try store.retryCleanup()
    }

    @Test(arguments: ["success", "cancel", "failure"])
    func activityResultWaitsForActualUIKitCompletion(_ result: String) async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let url = try create(store)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let sheet = ActivitySheet(items: [url], beginActivity: {
                guard let token = store.beginSharing(url) else {
                    Issue.record("Owned export did not acquire a consumer")
                    return { continuation.resume() }
                }
                return {
                    do { try store.finishSharing(url, token: token) }
                    catch { Issue.record(error) }
                    continuation.resume()
                }
            })
            let controller = sheet.activityController(coordinator: sheet.makeCoordinator())
            #expect(FileManager.default.fileExists(atPath: url.path))
            guard let completion = controller.completionWithItemsHandler else {
                Issue.record("Missing activity completion handler")
                continuation.resume()
                return
            }
            completion(nil, result == "success", nil,
                       result == "failure" ? CocoaError(.fileReadUnknown) : nil)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func backupPayloadAndPersistedProgressStayCompatible() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let exports = TemporaryExportStore(temporaryDirectory: root)
        let model = PeelModel(defaults: fixture.defaults, temporaryExports: exports)
        await model.reloadSavedData().value
        model.queue = QueueState(users: ["peel_fictional"])
        let before = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        let url = try #require(model.exportFile())
        let backup = try JSONDecoder().decode(ProgressFile.self, from: Data(contentsOf: url))
        #expect(backup.format == "follow-manager-backup-v1")
        #expect(backup.state.users == ["peel_fictional"])
        let finish = model.beginExportSharing(url)
        model.resetLists()
        #expect(FileManager.default.fileExists(atPath: url.path))
        let afterReset = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        finish()
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == afterReset)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(before != nil)
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) != before)
        #expect(model.queue.users.isEmpty)
    }

    @Test func cleanupFailureIsActionableAndRetryDoesNotCreateAnotherBackup() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = PeelModel(defaults: fixture.defaults,
                              temporaryExports: TemporaryExportStore(temporaryDirectory: root))
        await model.reloadSavedData().value
        model.queue = QueueState(users: ["peel_fictional"])
        let before = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        let url = try #require(model.exportFile())
        let finish = model.beginExportSharing(url)
        let directory = url.deletingLastPathComponent()
        let held = root.appendingPathComponent("held", isDirectory: true)
        let protected = root.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: directory, to: held)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: protected)
        finish()
        #expect(model.failure?.error == .exportCleanupFailed)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: held, to: directory)
        model.retryLastOperation()
        #expect(model.failure == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == before)
    }

    @Test func failedModelExportRemovesPartialFileAndPreservesSavedBytes() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        var attempted: URL?
        let model = PeelModel(defaults: fixture.defaults,
                              temporaryExports: TemporaryExportStore(temporaryDirectory: root),
                              writeExport: { data, url in
            attempted = url
            try data.prefix(4).write(to: url)
            throw PeelError.exportFailed
        })
        await model.reloadSavedData().value
        model.queue = QueueState(users: ["peel_fictional"])
        let before = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        #expect(model.exportFile() == nil)
        let partial = try #require(attempted)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        #expect(model.failure?.error == .exportFailed)
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == before)
    }

    @Test func presentationWithoutAWindowDoesNotAcquireAConsumer() {
        var acquisitions = 0
        let presenter = ActivitySheet.Presenter {
            acquisitions += 1
            return UIActivityViewController(activityItems: ["fictional"], applicationActivities: nil)
        }
        presenter.loadViewIfNeeded()
        presenter.presentIfReady()
        presenter.viewDidAppear(false)
        #expect(acquisitions == 0)
        #expect(!presenter.hasPresented)
    }

    @Test func dismissalNotificationFollowsCleanupAndIsIdempotent() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let url = try create(store)
        var dismissals = 0
        let sheet = ActivitySheet(items: [url], beginActivity: {
            guard let token = store.beginSharing(url) else {
                Issue.record("Missing owned export")
                return {}
            }
            return {
                do { try store.finishSharing(url, token: token) }
                catch { Issue.record(error) }
            }
        }, onDismiss: {
            #expect(!FileManager.default.fileExists(atPath: url.path))
            dismissals += 1
        })
        let coordinator = sheet.makeCoordinator()
        let controller = sheet.activityController(coordinator: coordinator)
        #expect(controller.completionWithItemsHandler != nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(dismissals == 0)
        coordinator.complete()
        coordinator.complete()
        #expect(dismissals == 1)
    }

    @Test func fileSymlinkCleanupDoesNotDeleteItsTarget() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TemporaryExportStore(temporaryDirectory: root)
        let url = try create(store)
        let protected = root.appendingPathComponent("document.json")
        try Data("protected".utf8).write(to: protected)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: protected)
        try store.discardUnshared(url)
        #expect(try Data(contentsOf: protected) == Data("protected".utf8))
    }
}
