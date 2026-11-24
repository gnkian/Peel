import SwiftUI
import UniformTypeIdentifiers
import OSLog

enum DocumentImportKind: String, Identifiable {
    case archive, backup
    var id: String { rawValue }
    var contentTypes: [UTType] { self == .archive ? [.zip] : [.json] }
    var operation: FileOperation { self == .archive ? .chooseZIP : .chooseRestore }

    @MainActor @discardableResult
    func receive(_ result: Result<URL, Error>?, model: PeelModel) -> Task<Void, Never>? {
        guard let result else { return nil }
        switch result {
        case .success(let url):
            return self == .archive ? model.importZIP(url) : model.restore(url)
        case .failure(let error):
            model.report(error, operation: operation)
            return nil
        }
    }
}

enum ImportDiagnostics {
    static let logger = Logger(subsystem: "Peel", category: "DocumentImport")
}

/// Copy a selected document instead of retaining an external document for editing.
@MainActor
struct DocumentImportPicker: UIViewControllerRepresentable {
    let kind: DocumentImportKind
    let completion: (Result<URL, Error>?) -> Void

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var completion: ((Result<URL, Error>?) -> Void)?
        private let kind: DocumentImportKind

        init(kind: DocumentImportKind, completion: @escaping (Result<URL, Error>?) -> Void) {
            self.kind = kind
            self.completion = completion
        }

        private func finish(_ result: Result<URL, Error>?) {
            guard let callback = completion else { return }
            completion = nil
            callback(result)
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard completion != nil else { return }
            ImportDiagnostics.logger.info("Selection received for \(self.kind.rawValue, privacy: .public)")
            guard urls.count == 1, let url = urls.first, url.isFileURL else {
                finish(.failure(PeelError.unreadableFile))
                return
            }
            finish(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            ImportDiagnostics.logger.info("Selection cancelled for \(self.kind.rawValue, privacy: .public)")
            finish(nil)
        }

        // A dismissed picker must not deliver a late selection to a different screen.
        func invalidate() { completion = nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator(kind: kind, completion: completion) }

    func makePicker(coordinator: Coordinator) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: kind.contentTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = coordinator
        ImportDiagnostics.logger.info("Presenting copy picker for \(self.kind.rawValue, privacy: .public)")
        return picker
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        makePicker(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: UIDocumentPickerViewController, coordinator: Coordinator) {
        controller.delegate = nil
        coordinator.invalidate()
    }
}

extension View {
    func documentImporter(request: Binding<DocumentImportKind?>, model: PeelModel) -> some View {
        sheet(item: request) { kind in
            DocumentImportPicker(kind: kind) { result in
                request.wrappedValue = nil
                kind.receive(result, model: model)
            }
        }
    }
}
