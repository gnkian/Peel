import SwiftUI
import WebKit

@MainActor
final class InstagramNavigationCoordinator: NSObject, WKNavigationDelegate {
    let state: BrowserLoadState
    var username: String?
    private var tokens: [ObjectIdentifier: UUID] = [:]
    private var target: URL?
    private var loadedURL: URL?
    private var scheduled = false
    private var stopped = false

    func update(_ url: URL?, in view: WKWebView) {
        guard !scheduled || loadedURL != url else { return }
        scheduled = true
        loadedURL = url
        Task { @MainActor [weak self, weak view] in
            guard let self, let view, !self.stopped, self.loadedURL == url else { return }
            if let url { self.load(url, in: view) }
            else { self.state.fail(.invalidURL, id: self.state.requestID) }
        }
    }


    init(state: BrowserLoadState) { self.state = state }

    func load(_ url: URL, in webView: WKWebView) {
        target = url
        let id = state.begin()
        webView.stopLoading()
        if let navigation = webView.load(URLRequest(url: url)) { tokens[ObjectIdentifier(navigation)] = id }
        state.reload = { [weak self, weak webView] in
            guard let self, let webView, let target = self.target else { return }
            self.load(target, in: webView)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !stopped, let navigation else { return }
        let key = ObjectIdentifier(navigation)
        if tokens[key] == nil { tokens[key] = state.begin() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let navigation, let id = tokens.removeValue(forKey: ObjectIdentifier(navigation)) else { return }
        state.finish(webView.url, username: username, id: id)
    }

    private func failed(_ error: Error, navigation: WKNavigation?) {
        guard let navigation, let id = tokens.removeValue(forKey: ObjectIdentifier(navigation)) else { return }
        if (error as? URLError)?.code == .cancelled { return }
        state.fail(PeelError.map(error), id: id)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error, navigation: navigation)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error, navigation: navigation)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard !stopped else { return .cancel }
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
           let error = HTTPStatus.error(response) {
            state.fail(error, id: state.requestID)
            return .cancel
        }
        return .allow
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !stopped else { return }
        state.fail(.browserTerminated, id: state.requestID)
    }

    func stop(_ webView: WKWebView) {
        stopped = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        tokens.removeAll()
        let id = state.requestID
        state.reload = nil
        Task { @MainActor [state] in
            if state.requestID == id { state.cancel() }
        }
    }
}

struct InstagramWebView: UIViewRepresentable {
    let url: URL?
    let username: String?
    @ObservedObject var state: BrowserLoadState

    func makeCoordinator() -> InstagramNavigationCoordinator { InstagramNavigationCoordinator(state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = .black
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.username = username
        context.coordinator.update(url, in: view)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: InstagramNavigationCoordinator) {
        coordinator.stop(view)
    }
}

private struct BrowserFeedback: ViewModifier {
    @ObservedObject var state: BrowserLoadState
    @State private var cooldownFinished = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if state.phase == .loading { ProgressView().padding().background(.regularMaterial, in: Capsule()) }
                if let error = state.error, error != .loginRequired {
                    VStack(spacing: 12) {
                        Text(error.text).multilineTextAlignment(.center)
                        Button("Retry") { state.retry() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!state.canRetry && !cooldownFinished)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding()
                    .task(id: error.retryAfter) {
                        cooldownFinished = false
                        if let date = error.retryAfter {
                            do { try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow))) }
                            catch { return }
                        }
                        cooldownFinished = true
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if state.error == .loginRequired {
                        Button("Retry", systemImage: "arrow.clockwise") { state.retry() }
                    }
                }
            }
            .alert("Instagram Could Not Load", isPresented: Binding(
                get: { state.showError },
                set: { presented in
                    guard !presented else { return }
                    let id = state.requestID
                    Task { @MainActor in
                        if state.requestID == id { state.showError = false }
                    }
                }
            ), presenting: state.error) { _ in
                Button("Retry") { state.retry() }.disabled(!state.canRetry)
                Button("Cancel", role: .cancel) {}
            } message: { error in Text(error.text) }
    }
}

extension View {
    func browserFeedback(_ state: BrowserLoadState) -> some View { modifier(BrowserFeedback(state: state)) }
}
