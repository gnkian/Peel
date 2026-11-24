import Foundation

enum OperationState: Equatable {
    case idle, running(UUID), completed, failed
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

enum FileOperation {
    case zip(URL), list([URL], ListKind), restore(URL), chooseZIP, chooseRestore, export, cleanupExports, save, startup
}

struct OperationFailure: Identifiable {
    let id = UUID()
    let error: PeelError
    let operation: FileOperation
}
