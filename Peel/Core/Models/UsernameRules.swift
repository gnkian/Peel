import Foundation

/// Shared identity rules; persistence validation must not depend on export formats.
enum UsernameRules {
    // Avoid repeated regular-expression work for ordinary ASCII usernames in large snapshots.
    static func valid(_ value: String) -> Bool {
        let bytes = value.utf8
        if (1...30).contains(bytes.count), bytes.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) ||
            (48...57).contains($0) || $0 == 46 || $0 == 95
        }) { return true }
        // Keep the previous regular-expression semantics for all other input.
        return value.range(of: "^[a-zA-Z0-9._]{1,30}$", options: .regularExpression) != nil
    }
    static func normalize(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^@", with: "", options: .regularExpression).lowercased() }
    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
