import Foundation

enum AvatarMetadata {
    static func imageURL(in html: String) throws -> URL {
        let pattern = #"<meta[^>]+(?:property|name)=["']og:image["'][^>]+content=["']([^"']+)["']"#
        let reversePattern = #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']og:image["']"#
        let raw = [pattern, reversePattern].compactMap { pattern -> String? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }.first
        guard let raw else { throw PeelError.unsupportedFormat }
        let decoded = raw.replacingOccurrences(of: "&amp;", with: "&")
        guard let imageURL = URL(string: decoded),
              imageURL.scheme == "https",
              let host = imageURL.host?.lowercased(),
              (host == "instagram.com" || host.hasSuffix(".instagram.com") ||
               host == "cdninstagram.com" || host.hasSuffix(".cdninstagram.com") ||
               host == "fbcdn.net" || host.hasSuffix(".fbcdn.net")) else { throw PeelError.invalidURL }

        return imageURL
    }
}

