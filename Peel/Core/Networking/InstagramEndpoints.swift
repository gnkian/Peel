import Foundation

/// Compatibility interface for existing browser, review and avatar callers.
/// Website changes belong in InstagramWebsitePolicy.
enum InstagramEndpoints {
    static let login = InstagramWebsitePolicy.login
    static let export = InstagramWebsitePolicy.export

    static func profile(_ username: String) -> URL? {
        InstagramWebsitePolicy.profile(username)
    }

    static func allowedImageURL(_ url: URL) -> Bool {
        InstagramWebsitePolicy.allowedImageURL(url)
    }

    static func isProfile(_ url: URL?, username: String) -> Bool {
        InstagramWebsitePolicy.isProfile(url, username: username)
    }

    static func needsLogin(_ url: URL?) -> Bool {
        InstagramWebsitePolicy.needsLogin(url)
    }
}
