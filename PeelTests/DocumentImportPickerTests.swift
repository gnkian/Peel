import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Peel

@MainActor
struct DocumentImportPickerTests {
    @Test(arguments: [DocumentImportKind.archive, .backup])
    func pickerUsesExplicitTypesAndCopiesOneDocument(_ kind: DocumentImportKind) {
        let wrapper = DocumentImportPicker(kind: kind) { _ in }
        let coordinator = wrapper.makeCoordinator()
        let picker = wrapper.makePicker(coordinator: coordinator)
        #expect(kind.contentTypes == (kind == .archive ? [.zip] : [.json]))
        // UIKit exposes the selected copy/open mode through this legacy read-only property.
        #expect(picker.documentPickerMode == .import)
        #expect(!picker.allowsMultipleSelection)
        #expect(picker.delegate === coordinator)
    }

    @Test func selectionIsDeliveredExactlyOnceAndTeardownIgnoresLateCallbacks() {
        var selections: [URL] = []
        var cancellations = 0
        let wrapper = DocumentImportPicker(kind: .archive) { result in
            if case .success(let url) = result { selections.append(url) }
            if result == nil { cancellations += 1 }
        }
        let coordinator = wrapper.makeCoordinator()
        let picker = wrapper.makePicker(coordinator: coordinator)
        let url = URL(fileURLWithPath: "/selected.zip")
        coordinator.documentPicker(picker, didPickDocumentsAt: [url])
        coordinator.documentPicker(picker, didPickDocumentsAt: [url])
        coordinator.documentPickerWasCancelled(picker)
        #expect(selections == [url])
        #expect(cancellations == 0)

        let dismissed = wrapper.makeCoordinator()
        DocumentImportPicker.dismantleUIViewController(picker, coordinator: dismissed)
        dismissed.documentPicker(picker, didPickDocumentsAt: [url])
        #expect(selections == [url])
        #expect(picker.delegate == nil)
    }

    @Test func cancellationPreservesListsAndDoesNotStartAnImport() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["kept"])
        let before = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        var callbacks = 0
        let wrapper = DocumentImportPicker(kind: .archive) { result in
            callbacks += 1
            #expect(DocumentImportKind.archive.receive(result, model: model) == nil)
        }
        let coordinator = wrapper.makeCoordinator()
        let picker = wrapper.makePicker(coordinator: coordinator)
        coordinator.documentPickerWasCancelled(picker)
        coordinator.documentPicker(picker, didPickDocumentsAt: [URL(fileURLWithPath: "/late.zip")])
        #expect(callbacks == 1)
        #expect(model.queue.users == ["kept"])
        #expect(model.failure == nil)
        #expect(!model.operationState.isRunning)
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == before)
    }

    @Test(arguments: [[], [URL(fileURLWithPath: "/one.zip"), URL(fileURLWithPath: "/two.zip")],
                      [URL(string: "https://example.com/archive.zip")].compactMap { $0 }])
    func invalidSelectionsReportFailureWithoutChangingSavedData(_ urls: [URL]) async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["kept"])
        let before = fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey)
        let wrapper = DocumentImportPicker(kind: .archive) {
            DocumentImportKind.archive.receive($0, model: model)
        }
        let coordinator = wrapper.makeCoordinator()
        coordinator.documentPicker(wrapper.makePicker(coordinator: coordinator), didPickDocumentsAt: urls)
        #expect(model.failure?.error == .unreadableFile)
        #expect(model.queue.users == ["kept"])
        #expect(fixture.defaults.data(forKey: DefaultsProgressStore.checkpointKey) == before)
    }

    @Test func selectedArchiveAndBackupUseProductionPipelines() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        let url = try #require(Bundle(for: PeelModel.self).url(forResource: "Peel-Sample-Archive", withExtension: "zip"))
        var pending: Task<Void, Never>?
        let wrapper = DocumentImportPicker(kind: .archive) {
            pending = DocumentImportKind.archive.receive($0, model: model)
        }
        let coordinator = wrapper.makeCoordinator()
        coordinator.documentPicker(wrapper.makePicker(coordinator: coordinator), didPickDocumentsAt: [url])
        await pending?.value
        #expect(model.failure == nil)
        #expect(model.queue.users.count == 20)
        #expect((try await fixture.restoredModel()).mutualUsers.count == 15)

        let backup = try #require(model.exportFile())
        defer { model.discardUnsharedExport(backup) }
        model.resetLists()
        await DocumentImportKind.backup.receive(.success(backup), model: model)?.value
        #expect(model.failure == nil)
        #expect(model.queue.users.count == 20)
        #expect((try await fixture.restoredModel()).reverseUsers.count == 15)
    }

    @Test func selectedUnreadableFileKeepsPreviouslySavedState() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["kept"])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await DocumentImportKind.archive.receive(.success(url), model: model)?.value
        #expect(model.failure?.error == .unreadableFile)
        #expect(model.queue.users == ["kept"])
        #expect((try await fixture.restoredModel()).queue.users == ["kept"])
    }
}
