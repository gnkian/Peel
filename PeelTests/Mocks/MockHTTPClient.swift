import Foundation
@testable import Peel

actor MockHTTPClient: HTTPClient {
    enum Reply: Sendable {
        case data(Data)
        case failure(PeelError)
    }
    private var replies: [Reply]
    struct RecordedRequest: Sendable {
        let request: URLRequest
        let maxBytes: Int
    }

    private(set) var requests = 0
    private(set) var recordedRequests: [RecordedRequest] = []
    private var holdingReplies: Bool
    private var replyWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(_ replies: [Reply], holdingReplies: Bool = false) {
        self.replies = replies
        self.holdingReplies = holdingReplies
    }

    func waitForRequests(_ count: Int) async {
        guard requests < count else { return }
        await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }

    func resumeReplies() {
        holdingReplies = false
        let waiters = replyWaiters
        replyWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
    func append(_ replies: [Reply]) { self.replies += replies }

    func data(for request: URLRequest, maxBytes: Int) async throws -> Data {
        try Task.checkCancellation()
        requests += 1
        recordedRequests.append(RecordedRequest(request: request, maxBytes: maxBytes))
        let ready = requestWaiters.filter { requests >= $0.count }
        requestWaiters.removeAll { requests >= $0.count }
        for waiter in ready { waiter.continuation.resume() }
        if holdingReplies {
            await withCheckedContinuation { replyWaiters.append($0) }
        }
        try Task.checkCancellation()
        guard !replies.isEmpty else { throw PeelError.unavailable }
        switch replies.removeFirst() {
        case .data(let data):
            guard data.count <= maxBytes else { throw PeelError.tooLarge }
            return data
        case .failure(let error): throw error
        }
    }
}
