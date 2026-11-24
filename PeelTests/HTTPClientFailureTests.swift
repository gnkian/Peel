import Foundation
import Testing
@testable import Peel

private final class StubHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let status = url.path.contains("limited") ? 429 : 200
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                            headerFields: ["Retry-After": "120"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 20))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct HTTPClientFailureTests {
    @Test func streamingResponseCannotExceedByteLimit() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHTTPProtocol.self]
        let client = URLSessionHTTPClient(configuration: configuration)
        let url = try #require(URL(string: "https://www.instagram.com/fixture/"))
        await #expect(throws: PeelError.tooLarge) {
            try await client.data(for: URLRequest(url: url), maxBytes: 4)
        }
    }

    @Test func transportClassifies429BeforeReadingBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubHTTPProtocol.self]
        let client = URLSessionHTTPClient(configuration: configuration)
        let url = try #require(URL(string: "https://www.instagram.com/limited/"))
        do { _ = try await client.data(for: URLRequest(url: url), maxBytes: 4); Issue.record("429 accepted") }
        catch { #expect((error as? PeelError)?.retryAfter != nil) }
    }

    @Test func untrustedURLIsRejectedWithoutNetwork() async throws {
        let client = URLSessionHTTPClient()
        let url = try #require(URL(string: "https://instagram.com.evil.example/"))
        await #expect(throws: PeelError.invalidURL) {
            try await client.data(for: URLRequest(url: url), maxBytes: 4)
        }
    }

    @Test func gateCancellationDoesNotConsumeAnExtraPermit() async throws {
        let gate = AvatarRequestGate()
        for _ in 0..<4 { try await gate.acquire() }
        let blocked = Task { try await gate.acquire() }
        blocked.cancel()
        do { try await blocked.value; Issue.record("Cancelled waiter acquired permit") }
        catch { #expect(error is CancellationError) }
        for _ in 0..<4 { await gate.release() }
        try await gate.acquire()
        await gate.release()
    }
}
