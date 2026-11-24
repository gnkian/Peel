import Foundation

// Preserve existing error identity, cases and descriptions for callers.
typealias InstagramZIPError = ZIPArchiveError

/// Composes offline export selection with generic ZIP validation.
enum InstagramZIPReader {
    static func extractLists(from data: Data) throws -> [(String, Data)] {
        try ZIPArchiveReader.extract(from: data, selecting: InstagramExportParser.isArchiveList)
    }

    static func crc32(_ data: Data) throws -> UInt32 {
        try ZIPArchiveReader.crc32(data)
    }
}
