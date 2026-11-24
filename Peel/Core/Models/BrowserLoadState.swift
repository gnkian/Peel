import SwiftUI

enum BrowserPhase: Equatable {
    case idle, loading, loaded, failed(PeelError)
}

@MainActor
final class BrowserLoadState: ObservableObject {
    @Published private(set) var phase: BrowserPhase = .idle
    @Published private(set) var requestID = UUID()
    @Published var showError = false
    var reload: (() -> Void)?
    var onProfileLoaded: ((String, UUID) -> Void)?
    var reviewToken: UUID?

    @discardableResult
    func begin() -> UUID {
        requestID = UUID()
        phase = .loading
        showError = false
        return requestID
    }

    func fail(_ error: PeelError, id: UUID) {
        guard id == requestID else { return }
        phase = .failed(error)
        showError = true
    }

    func finish(_ url: URL?, username: String?, id: UUID) {
        guard id == requestID else { return }
        guard phase == .loading else { return }
        if let username {
            guard InstagramEndpoints.isProfile(url, username: username) else {
                fail(InstagramEndpoints.needsLogin(url) ? .loginRequired : .unavailable, id: id)
                return
            }
        }
        phase = .loaded
        if let username, let reviewToken { onProfileLoaded?(username, reviewToken) }
    }

    var error: PeelError? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    var canRetry: Bool { error?.retryAfter.map { $0 <= Date() } ?? true }

    func retry() {
        guard canRetry else { return }
        showError = false
        reload?()
    }

    func cancel() {
        requestID = UUID()
        phase = .idle
        showError = false
        reload = nil
    }
}
