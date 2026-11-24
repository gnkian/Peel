import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest, maxBytes: Int) async throws -> Data
}

enum HTTPStatus {
    static func error(_ response: HTTPURLResponse, now: Date = Date()) -> PeelError? {
        if response.statusCode == 429 {
            let value = response.value(forHTTPHeaderField: "Retry-After") ?? ""
            let seconds = TimeInterval(value).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            let date = seconds.map { now.addingTimeInterval(max(1, min($0, Date.distantFuture.timeIntervalSince(now)))) }
                ?? formatter.date(from: value) ?? now.addingTimeInterval(60)
            return .rateLimited(max(date, now.addingTimeInterval(1)))
        }
        if response.statusCode == 401 { return .loginRequired }
        if !(200...299).contains(response.statusCode) { return .http(response.statusCode) }
        return nil
    }
}

private final class ImageRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowsURL: @Sendable (URL) -> Bool

    init(allowsURL: @escaping @Sendable (URL) -> Bool) {
        self.allowsURL = allowsURL
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(allowsURL) == true ? request : nil)
    }
}

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let redirects: ImageRedirectPolicy
    private let allowsURL: @Sendable (URL) -> Bool

    init(configuration: URLSessionConfiguration, allowsURL: @escaping @Sendable (URL) -> Bool) {
        self.allowsURL = allowsURL
        redirects = ImageRedirectPolicy(allowsURL: allowsURL)
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest, maxBytes: Int) async throws -> Data {
        guard let url = request.url, allowsURL(url) else { throw PeelError.invalidURL }
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
            guard let response = response as? HTTPURLResponse,
                  response.url.map(allowsURL) == true else { throw PeelError.invalidURL }
            if let error = HTTPStatus.error(response) { throw error }
            guard response.expectedContentLength <= Int64(maxBytes) else { throw PeelError.tooLarge }
            var result = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard result.count < maxBytes else { throw PeelError.tooLarge }
                result.append(byte)
            }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw PeelError.map(error) }
    }
}

