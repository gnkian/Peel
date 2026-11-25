import Foundation
import Testing
@testable import Peel

@MainActor
struct ReleaseUpdateCheckerTests {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": draft, "prerelease": prerelease,
            "html_url": "https://untrusted.example/install",
            "assets": [["browser_download_url": "https://untrusted.example/update.ipa"]]
        ])
    }

    @Test func newerReleasePromptsAndOnlyRequestsMetadataOnce() async throws {
        let client = MockHTTPClient([.data(try release("v1.0.3"))])
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        await checker.checkAtStartup()
        #expect(checker.showsUpdate)
        #expect(checker.availableUpdate?.version == "1.0.3")
        #expect(checker.availableUpdate?.url.absoluteString == "https://github.com/gnkian/Peel/releases/tag/v1.0.3")
        checker.showsUpdate = false
        await checker.checkAtStartup()
        #expect(!checker.showsUpdate)
        #expect(await client.requests == 1)
        let request = try #require(await client.recordedRequests.first)
        #expect(request.request.url?.absoluteString == "https://api.github.com/repos/gnkian/Peel/releases/latest")
        #expect(request.request.httpMethod == "GET")
        #expect(request.request.httpBody == nil)
        #expect(request.request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.request.timeoutInterval == 8)
        #expect(request.maxBytes == 256 * 1_024)
    }

    @Test(arguments: ["v1.0.2", "v1.0.1", "v0.9.9", "v1.0.2-beta", "latest", "v1..3", "v1.0.3/path", "v1.0.3+build4"])
    func equalOlderAndInvalidTagsNeverPrompt(_ tag: String) async throws {
        let client = MockHTTPClient([.data(try release(tag))])
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        await checker.checkAtStartup()
        #expect(!checker.showsUpdate)
        #expect(checker.availableUpdate == nil)
    }

    @Test(arguments: [true, false])
    func unpublishedAndPrereleaseResponsesNeverPrompt(draft: Bool) async throws {
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2",
            client: MockHTTPClient([.data(try release("v2.0.0", draft: draft, prerelease: !draft))]))
        await checker.checkAtStartup()
        #expect(!checker.showsUpdate)
    }

    @Test func numericComparisonAndNormalization() throws {
        #expect(try #require(ReleaseVersion("v1.10.0")) > #require(ReleaseVersion("1.9.9")))
        #expect(ReleaseVersion("1.0") == ReleaseVersion("1.0.0"))
        #expect(ReleaseVersion("2")?.description == "2.0.0")
        for invalid in ["", "v", "-1.2.3", "1.2.3.4", "1. 2.3", "1.٢.3", String(repeating: "9", count: 70)] {
            #expect(ReleaseVersion(invalid) == nil)
        }
    }

    @Test(arguments: [PeelError.offline, .http(404), .http(500), .rateLimited(Date.distantFuture)])
    func failedCheckIsSilentAndDoesNotRetryDuringLaunch(_ error: PeelError) async {
        let client = MockHTTPClient([.failure(error)])
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        await checker.checkAtStartup()
        await checker.checkAtStartup()
        #expect(!checker.showsUpdate)
        #expect(checker.availableUpdate == nil)
        #expect(await client.requests == 1)
    }

    @Test(arguments: ["{broken", "{}", "{\"tag_name\":\"v9.0.0\"}"])
    func malformedResponsesStaySilent(_ response: String) async {
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2",
            client: MockHTTPClient([.data(Data(response.utf8))]))
        await checker.checkAtStartup()
        #expect(!checker.showsUpdate)
    }

    @Test func newLaunchChecksAgainAndConcurrentCallsShareOneCheck() async throws {
        let client = MockHTTPClient([.data(try release("v1.0.3"))], holdingReplies: true)
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        let first = Task { await checker.checkAtStartup() }
        await client.waitForRequests(1)
        await checker.checkAtStartup()
        #expect(await client.requests == 1)
        await client.resumeReplies()
        await first.value
        #expect(checker.showsUpdate)
        await client.append([.data(try release("v1.0.4"))])
        let nextLaunch = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        await nextLaunch.checkAtStartup()
        #expect(await client.requests == 2)
        #expect(nextLaunch.availableUpdate?.version == "1.0.4")
    }

    @Test func cancelledCheckNeverPrompts() async throws {
        let client = MockHTTPClient([.data(try release("v1.0.3"))], holdingReplies: true)
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        let task = Task { await checker.checkAtStartup() }
        await client.waitForRequests(1)
        task.cancel()
        await client.resumeReplies()
        await task.value
        #expect(!checker.showsUpdate)
        #expect(checker.availableUpdate == nil)
    }

    @Test func manualCheckReportsLatestVersionAndCanRunAfterStartup() async throws {
        let client = MockHTTPClient([.data(try release("v1.0.2")), .data(try release("v1.0.3"))])
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        await checker.checkAtStartup()
        #expect(!checker.showsUpdate)
        let result = await checker.checkManually()
        #expect(result == .available(.init(version: "1.0.3", url: try #require(URL(string: "https://github.com/gnkian/Peel/releases/tag/v1.0.3")))))
        #expect(await client.requests == 2)
        #expect(!checker.isChecking)
    }

    @Test(arguments: ["v1.0.2", "v1.0.1"])
    func manualCheckReportsInstalledAndLatestVersions(_ tag: String) async throws {
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: MockHTTPClient([.data(try release(tag))]))
        let result = await checker.checkManually()
        #expect(result == .current(installed: "1.0.2", latest: String(tag.dropFirst())))
        #expect(!checker.showsUpdate)
    }

    @Test func manualFailureIsReportedAndAnExplicitRetryCanSucceed() async throws {
        let client = MockHTTPClient([.failure(.offline), .data(try release("v1.0.2"))])
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        #expect(await checker.checkManually() == .unavailable)
        #expect(!checker.isChecking)
        #expect(await checker.checkManually() == .current(installed: "1.0.2", latest: "1.0.2"))
        #expect(await client.requests == 2)
    }

    @Test func manualCheckDoesNotOverlapStartupRequest() async throws {
        let client = MockHTTPClient([.data(try release("v1.0.3"))], holdingReplies: true)
        let checker = ReleaseUpdateChecker(currentVersion: "1.0.2", client: client)
        let startup = Task { await checker.checkAtStartup() }
        await client.waitForRequests(1)
        #expect(checker.isChecking)
        #expect(await checker.checkManually() == nil)
        #expect(await client.requests == 1)
        await client.resumeReplies()
        await startup.value
        #expect(!checker.isChecking)
        #expect(checker.showsUpdate)
    }
}
