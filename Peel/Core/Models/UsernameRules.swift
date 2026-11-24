import Foundation

/// Shared identity rules; persistence validation must not depend on export formats.
enum UsernameRules {
    static func valid(_ value: String) -> Bool { value.range(of: "^[a-zA-Z0-9._]{1,30}$", options: .regularExpression) != nil }
    static func normalize(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^@", with: "", options: .regularExpression).lowercased() }
    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
