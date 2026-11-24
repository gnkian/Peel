import SwiftUI
import UniformTypeIdentifiers

private struct OperationFeedback: ViewModifier {
    @ObservedObject var model: PeelModel
    var startupOnly = false
    var enabled = true
    var chooseFile: (() -> Void)?
    var retryExport: (() -> Void)?
    @State private var isVisible = false
    @State private var restorePicker = false

    private var presentedFailure: OperationFailure? {
        guard enabled, isVisible, let failure = model.failure else { return nil }
        let startup: Bool
        if case .startup = failure.operation { startup = true } else { startup = false }
        return startup == startupOnly ? failure : nil
    }

    private var canChooseFile: Bool {
        guard let failure = presentedFailure else { return false }
        if failure.error == .corruptSavedData { return true }
        switch failure.operation {
        case .zip, .list, .chooseZIP: return chooseFile != nil
        case .restore, .chooseRestore, .startup: return true
        default: return false
        }
    }

    func body(content: Content) -> some View {
        content
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .overlay(alignment: .bottom) {
                if enabled && !startupOnly && model.operationState.isRunning {
                    HStack {
                        ProgressView()
                        Text("Working…")
                        Spacer()
                        Button("Cancel") { model.cancelOperation() }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
            }
            .alert("Operation Could Not Complete", isPresented: Binding(
                get: { presentedFailure != nil },
                set: { presented in
                    guard !presented else { return }
                    let id = presentedFailure?.id
                    Task { @MainActor in
                        if model.failure?.id == id { model.failure = nil }
                    }
                }
            ), presenting: presentedFailure) { failure in
                Button("Retry") {
                    switch failure.operation {
                    case .chooseZIP: chooseFile?()
                    case .chooseRestore: restorePicker = true
                    case .export: retryExport?()
                    default: model.retryLastOperation()
                    }
                }
                if canChooseFile {
                    Button(startupOnly || failure.error == .corruptSavedData ? "Restore Backup" : "Choose Another File") {
                        if failure.error == .corruptSavedData { restorePicker = true; return }
                        switch failure.operation {
                        case .restore, .chooseRestore, .startup: restorePicker = true
                        default: chooseFile?()
                        }
                    }
                }
                Button("Cancel", role: .cancel) { model.failure = nil }
            } message: { failure in
                Text(failure.error.text)
            }
            .fileImporter(isPresented: $restorePicker, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): model.restore(url)
                case .failure(let error): model.report(error, operation: .chooseRestore)
                }
            }
    }
}

extension View {
    func operationFeedback(model: PeelModel, startupOnly: Bool = false, enabled: Bool = true,
                           chooseFile: (() -> Void)? = nil, retryExport: (() -> Void)? = nil) -> some View {
        modifier(OperationFeedback(model: model, startupOnly: startupOnly, enabled: enabled,
                                   chooseFile: chooseFile, retryExport: retryExport))
    }
}
