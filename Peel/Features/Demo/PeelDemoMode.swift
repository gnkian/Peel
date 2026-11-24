import SwiftUI

// Demo data is generated locally, never loaded from a real Instagram account.
@MainActor final class PeelDemoMode: ObservableObject {
    @Published var isEnabled = false
    func toggle() { isEnabled.toggle() }
}
