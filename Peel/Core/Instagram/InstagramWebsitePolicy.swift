import Foundation

/// Live website rules only. Export HTML and metadata acceptance have separate owners.
enum InstagramWebsitePolicy {
    static let login = URL(string: "https://www.instagram.com/accounts/login/")
    static let export = URL(string: "https://accountscenter.instagram.com/info_and_permissions/dyi/")

    static func profile(_ username: String) -> URL? {
        guard UsernameParser.valid(username) else { return nil }
        return URL(string: "https://www.instagram.com/\(username)/")
    }

    /// HTTP transport validation. Deliberately not the metadata parser's URL rule.
    static func allowedImageURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return ["instagram.com", "cdninstagram.com", "fbcdn.net"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    static func isProfile(_ url: URL?, username: String) -> Bool {
        guard let url, url.scheme == "https",
              ["instagram.com", "www.instagram.com"].contains(url.host?.lowercased() ?? "") else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.count == 1 && parts[0].lowercased() == username.lowercased()
    }

    static func needsLogin(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased(),
              host == "instagram.com" || host.hasSuffix(".instagram.com") else { return false }
        return ["/accounts/login", "/challenge", "/checkpoint"].contains { url.path.hasPrefix($0) }
    }

    static func matchesWebsiteDataRecord(_ displayName: String) -> Bool {
        let name = displayName.lowercased()
        return ["instagram.com", "facebook.com", "fbcdn.net", "cdninstagram.com"].contains {
            name == $0 || name.hasSuffix("." + $0)
        }
    }
}

// Production avatar transport composition lives with Instagram, not generic networking.
// Retains the existing initializer used by callers and the exact configuration mutation.
extension URLSessionHTTPClient {
    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 4
        self.init(configuration: config, allowsURL: { url in InstagramWebsitePolicy.allowedImageURL(url) })
    }
}
