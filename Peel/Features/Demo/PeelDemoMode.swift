import SwiftUI

// Demo data stays isolated unless the user explicitly keeps an imported sample.
@MainActor final class PeelDemoMode: ObservableObject {
    @Published var isEnabled = false
    @Published var exitRequested = false

    func toggle() {
        if isEnabled { exitRequested = true }
        else { isEnabled = true }
    }

    func exit() {
        exitRequested = false
        isEnabled = false
    }
}
