import Foundation

/// Compatibility entry points for existing callers; new export code uses InstagramExportParser.
enum UsernameParser {
    static func valid(_ value: String) -> Bool { UsernameRules.valid(value) }
    static func normalize(_ value: String) -> String { UsernameRules.normalize(value) }
    static func detectType(text: String, filename: String) -> ListKind? {
        InstagramExportParser.detectType(text: text, filename: filename)
    }
    static func parse(text: String, filename: String) throws -> [String] {
        try InstagramExportParser.parse(text: text, filename: filename)
    }
    static func unique(_ names: [String]) -> [String] { UsernameRules.unique(names) }
}
