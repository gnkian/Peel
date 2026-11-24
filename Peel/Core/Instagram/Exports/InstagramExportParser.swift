import Foundation

/// Offline export rules only; independent of live website and avatar metadata behavior.
enum InstagramExportParser {
    /// Archive selection is intentionally stricter than standalone type detection.
    static func isArchiveList(_ filename: String) -> Bool {
        let leaf = URL(fileURLWithPath: filename).lastPathComponent.lowercased()
        return leaf.range(of: #"^(followers(?:_[0-9]+)?|following)\.(json|html|htm)$"#, options: .regularExpression) != nil
    }

    static func detectType(text: String, filename: String) -> ListKind? {
        let name = filename.lowercased()
        if name.range(of: "(^|[_\\-.])followers([_\\-.0-9]|$)", options: .regularExpression) != nil { return .followers }
        if name.range(of: "(^|[_\\-.])following([_\\-.0-9]|$)", options: .regularExpression) != nil { return .following }
        let prefix = String(text.prefix(500)).lowercased()
        if prefix.contains("relationships_following") || prefix.contains("<title>following") { return .following }
        if prefix.contains("relationships_followers") || prefix.contains("<title>followers") { return .followers }
        return nil
    }
    static func parse(text: String, filename: String) throws -> [String] {
        guard text.utf8.count <= 16 * 1024 * 1024 else { throw PeelError.tooLarge }
        try Task.checkCancellation()
        var found: [String] = []
        var recognized = false
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if ext == "json" {
            let json: Any
            do { json = try JSONSerialization.jsonObject(with: Data(text.utf8)) }
            catch { throw PeelError.invalidJSON }
            func walk(_ value: Any, depth: Int = 0) throws {
                try Task.checkCancellation()
                guard depth <= 64 else { throw PeelError.unsupportedFormat }
                if let array = value as? [Any] { if array.isEmpty && depth == 0 { recognized = true }
                    for item in array { try walk(item, depth: depth + 1) } }
                else if let dict = value as? [String: Any] {
                    if (dict["relationships_following"] as? [Any])?.isEmpty == true ||
                       (dict["relationships_followers"] as? [Any])?.isEmpty == true { recognized = true }
                    if let strings = dict["string_list_data"] as? [[String: Any]] {
                        recognized = true
                        for item in strings {
                            guard let s = item["value"] as? String else { throw PeelError.unsupportedFormat }
                            found.append(s)
                        }
                    }
                    if let name = dict["username"] as? String { recognized = true; found.append(name) }
                    for (key, nested) in dict where key != "string_list_data" && key != "username" { try walk(nested, depth: depth + 1) }
                }
            }
            try walk(json)
        } else if ext == "html" || ext == "htm" {
            // Only Instagram profile URLs, including the _u/username export variant.
            let pattern = #"(?:https?://)?(?:www\.)?instagram\.com/(?:_u/)?([a-zA-Z0-9._]{1,30})(?:[/\?\"'&<]|$)"#
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                recognized = true
                found.append(ns.substring(with: match.range(at: 1)))
            }
        } else {
            for line in text.components(separatedBy: .newlines) {
                var first = String(line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\t" }).first ?? "")
                first = first.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if let url = URL(string: first), ["instagram.com", "www.instagram.com"].contains(url.host?.lowercased() ?? "") {
                    let parts = url.pathComponents.filter { $0 != "/" }
                    first = parts.first == "_u" ? (parts.dropFirst().first ?? "") : (parts.first ?? "")
                }
                found.append(first)
                if UsernameRules.valid(UsernameRules.normalize(first)) { recognized = true }
            }
        }
        guard recognized else { throw PeelError.unsupportedFormat }
        let excluded: Set<String> = ["username", "usernames", "following", "followers", "profile", "url", "accounts", "explore", "reels", "direct"]
        let clean = found.map(UsernameRules.normalize).filter { UsernameRules.valid($0) && !excluded.contains($0) }
        guard !clean.isEmpty || found.isEmpty else { throw PeelError.unsupportedFormat }
        return UsernameRules.unique(clean)
    }
}
