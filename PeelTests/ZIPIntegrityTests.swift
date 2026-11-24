import Foundation
import Testing
@testable import Peel

private final class ZIPFixtureBundle: NSObject {}

struct ZIPIntegrityTests {
    private func archive() throws -> Data {
        let url = try #require(Bundle(for: ZIPFixtureBundle.self).url(forResource: "stored-json", withExtension: "zip"))
        return try Data(contentsOf: url)
    }

    @Test func corruptedPayloadIsRejectedByCRC() throws {
        var bytes = try archive()
        let range = try #require(bytes.range(of: Data("Peel_Fixture_A".utf8)))
        bytes[range.lowerBound] = 88
        #expect(throws: InstagramZIPError.invalidFile) { try InstagramZIPReader.extractLists(from: bytes) }
    }

    @Test func mismatchedLocalFilenameIsRejected() throws {
        var bytes = try archive()
        bytes[30] = 88
        #expect(throws: InstagramZIPError.invalidArchive) { try InstagramZIPReader.extractLists(from: bytes) }
    }

    @Test func unsupportedMethodIsRejected() throws {
        var bytes = try archive()
        let central = try #require(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02]))?.lowerBound)
        bytes[8] = 99
        bytes[central + 10] = 99
        #expect(throws: InstagramZIPError.unsupportedCompression) { try InstagramZIPReader.extractLists(from: bytes) }
    }

    @Test func oversizedDeclaredOutputIsRejectedBeforeAllocation() throws {
        var bytes = try archive()
        let central = try #require(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02]))?.lowerBound)
        for i in 24..<28 { bytes[central + i] = 255 }
        #expect(throws: InstagramZIPError.tooLarge) { try InstagramZIPReader.extractLists(from: bytes) }
    }

    @Test func encryptedArchiveIsRejected() throws {
        var bytes = try archive()
        let central = try #require(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02]))?.lowerBound)
        bytes[6] = 1
        bytes[central + 8] = 1
        #expect(throws: InstagramZIPError.invalidArchive) { try InstagramZIPReader.extractLists(from: bytes) }
    }
}
