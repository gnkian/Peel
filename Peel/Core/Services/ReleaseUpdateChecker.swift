import Foundation
import Observation

/// Checks public release metadata only; never retrieves or installs release assets.
@MainActor @Observable
final class ReleaseUpdateChecker {
    struct Update: Equatable, Sendable {
        let version: String
        let url: URL
    }

    enum Result: Equatable, Sendable {
        case available(Update)
        case current(installed: String, latest: String)
        case unavailable
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    private let currentVersion: String
    private let client: any HTTPClient
    private var hasChecked = false
    private(set) var availableUpdate: Update?
    var showsUpdate = false
    private(set) var isChecking = false

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         client: (any HTTPClient)? = nil) {
        self.currentVersion = currentVersion
        if let client {
            self.client = client
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            self.client = URLSessionHTTPClient(configuration: configuration) { url in
                url.scheme == "https" && url.host == "api.github.com" &&
                    url.path == "/repos/gnkian/Peel/releases/latest" &&
                    url.user == nil && url.password == nil && url.port == nil && url.query == nil
            }
        }
    }

    func checkAtStartup() async {
        guard !hasChecked else { return }
        hasChecked = true
        guard let result = await checkManually() else { return }
        if case .available(let update) = result {
            availableUpdate = update
            showsUpdate = true
        }
    }

    /// Manual checks can run again, but never overlap an existing request.
    func checkManually() async -> Result? {
        guard !isChecking else { return nil }
        isChecking = true
        defer { isChecking = false }
        guard let installed = ReleaseVersion(currentVersion),
              let endpoint = URL(string: "https://api.github.com/repos/gnkian/Peel/releases/latest") else { return .unavailable }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Peel-Release-Check", forHTTPHeaderField: "User-Agent")
        do {
            let data = try await client.data(for: request, maxBytes: 256 * 1_024)
            try Task.checkCancellation()
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard !release.draft, !release.prerelease,
                  let latest = ReleaseVersion(release.tag_name),
                  let releases = URL(string: "https://github.com/gnkian/Peel/releases/tag/") else { return .unavailable }
            guard latest > installed else { return .current(installed: installed.description, latest: latest.description) }
            return .available(Update(version: latest.description,
                                     url: releases.appendingPathComponent(release.tag_name)))
        } catch is CancellationError {
            return nil
        } catch {
            // Startup remains usable offline, during rate limits and when GitHub is unavailable.
            return .unavailable
        }
    }
}

/// Stable numeric release tags such as v1.0.2; comparison never uses string ordering.
struct ReleaseVersion: Comparable, Sendable {
    private let parts: [Int]
    var description: String { parts.map(String.init).joined(separator: ".") }

    init?(_ value: String) {
        guard value.count <= 64 else { return nil }
        let tag = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = tag.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count) else { return nil }
        var numbers: [Int] = []
        for field in fields {
            guard !field.isEmpty, field.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(field) else { return nil }
            numbers.append(number)
        }
        parts = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}
