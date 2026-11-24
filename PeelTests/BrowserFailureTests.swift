import Foundation
import Testing
import WebKit
@testable import Peel

@MainActor
struct BrowserFailureTests {
    @Test func oldNavigationCannotFinishOrFailNewRequest() {
        let state = BrowserLoadState()
        let old = state.begin()
        let current = state.begin()
        state.finish(InstagramEndpoints.profile("peel_a"), username: "peel_a", id: old)
        state.fail(.offline, id: old)
        #expect(state.phase == .loading)
        state.fail(.timeout, id: current)
        #expect(state.phase == .failed(.timeout))
    }

    @Test func loginRedirectDoesNotCountAsProfileLoad() {
        let state = BrowserLoadState()
        var loaded = false
        state.reviewToken = UUID()
        state.onProfileLoaded = { _, _ in loaded = true }
        let id = state.begin()
        state.finish(InstagramEndpoints.login, username: "peel_a", id: id)
        #expect(state.error == .loginRequired)
        #expect(!loaded)
    }

    @Test func unrelatedPageCannotMarkCurrentProfile() {
        let state = BrowserLoadState()
        let id = state.begin()
        state.finish(InstagramEndpoints.profile("peel_b"), username: "peel_a", id: id)
        #expect(state.error == .unavailable)
    }

    @Test func retryInvokesReloadAndRespectsRateLimit() {
        let state = BrowserLoadState()
        var retries = 0
        state.reload = { retries += 1 }
        let id = state.begin()
        state.fail(.rateLimited(Date().addingTimeInterval(60)), id: id)
        state.retry()
        #expect(retries == 0)
        state.fail(.offline, id: id)
        state.retry()
        #expect(retries == 1)
    }

    @Test func cancelledBrowserIgnoresLateCallbacks() {
        let state = BrowserLoadState()
        let id = state.begin()
        state.cancel()
        state.fail(.offline, id: id)
        state.finish(InstagramEndpoints.profile("peel_a"), username: "peel_a", id: id)
        #expect(state.phase == .idle)
    }

    @Test func webProcessTerminationIsActionableAndStopCancels() async {
        let state = BrowserLoadState()
        let coordinator = InstagramNavigationCoordinator(state: state)
        let web = WKWebView()
        coordinator.webViewWebContentProcessDidTerminate(web)
        #expect(state.error == .browserTerminated)
        coordinator.stop(web)
        await Task.yield()
        #expect(state.phase == .idle)
        #expect(state.reload == nil)
        coordinator.webViewWebContentProcessDidTerminate(web)
        #expect(state.phase == .idle)
    }

    @Test func failedProfileDoesNotAlterSavedReviewProgress() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["peel_a", "peel_b"], done: ["peel_b"])
        model.startBrowser(mode: .unfollow)
        let token = model.browserRequestID
        #expect(model.queue.done == ["peel_b"])
        let state = BrowserLoadState()
        state.reviewToken = token
        state.onProfileLoaded = { model.profileDidLoad($0, requestID: $1) }
        let id = state.begin()
        state.fail(.offline, id: id)
        #expect(model.queue.done == ["peel_b"])
        state.finish(InstagramEndpoints.profile("peel_a"), username: "peel_a", id: id)
        #expect(model.queue.done == ["peel_b"])
        let retry = state.begin()
        state.finish(InstagramEndpoints.profile("peel_a"), username: "peel_a", id: retry)
        #expect(model.queue.done == ["peel_b", "peel_a"])
        #expect((try await fixture.restoredModel()).queue.done == ["peel_b", "peel_a"])
    }

    @Test func staleProfileSuccessCannotMarkNewAccount() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.queue = QueueState(users: ["peel_a", "peel_b"])
        model.startBrowser(mode: .unfollow, at: "peel_a")
        let old = model.browserRequestID
        model.startBrowser(mode: .unfollow, at: "peel_b")
        model.profileDidLoad("peel_a", requestID: old)
        #expect(model.queue.done.isEmpty)
    }

    @Test(arguments: [401, 403, 404, 500])
    func errorHTTPResponsesAreNotSuccess(_ status: Int) throws {
        let url = try #require(InstagramEndpoints.profile("peel_a"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        #expect(HTTPStatus.error(response) != nil)
    }

    @Test func unknownBrowserErrorsDoNotSuggestChoosingAFile() {
        #expect(PeelError.map(NSError(domain: WKError.errorDomain, code: 999)) == .unavailable)
    }

    @Test func rateLimitHonorsRetryAfterSeconds() throws {
        let date = Date(timeIntervalSince1970: 1_000)
        let url = try #require(InstagramEndpoints.login)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "120"]))
        #expect(HTTPStatus.error(response, now: date)?.retryAfter == date.addingTimeInterval(120))
    }
}
