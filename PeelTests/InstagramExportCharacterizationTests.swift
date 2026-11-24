import Foundation
import Testing
@testable import Peel

struct InstagramExportCharacterizationTests {
    @Test func strictArchiveFilenamesAndCentralDirectoryOrder() throws {
        let names = ["nested/FOLLOWERS_02.JSON", "following.htm", "followers.html", "followers_0.htm",
                     "following_1.json", "my_followers.json", "followers2.json", "followers.txt",
                     "following.csv", "followers_.json", "followers_1.json.bak"]
        let files = try InstagramZIPReader.extractLists(from: archive(names.map { ($0, Data("[]".utf8)) }))
        #expect(files.map(\.0) == Array(names.prefix(4)))
    }

    @Test func standaloneDetectionKeepsFilenamePrecedenceAndBroaderRecognition() {
        #expect(UsernameParser.detectType(text: "relationships_following", filename: "MY-FOLLOWERS2.csv") == .followers)
        #expect(UsernameParser.detectType(text: "relationships_followers", filename: "following_1.txt") == .following)
        #expect(UsernameParser.detectType(text: "", filename: "notfollowers.json") == nil)
        #expect(UsernameParser.detectType(text: "<TITLE>FOLLOWING", filename: "data") == .following)
        #expect(UsernameParser.detectType(text: "relationships_following relationships_followers", filename: "data") == .following)
        #expect(UsernameParser.detectType(text: String(repeating: " ", count: 500) + "relationships_followers", filename: "data") == nil)
    }

    @Test func normalizationValidationAndStableDeduplication() {
        #expect(UsernameParser.normalize(" \n@Peel_Fictional.1\t") == "peel_fictional.1")
        #expect(UsernameParser.normalize("@@Peel") == "@peel")
        #expect(UsernameParser.valid("Peel_1."))
        #expect(UsernameParser.valid(String(repeating: "a", count: 30)))
        for value in ["", "a-b", "@peel", "a b", "é", String(repeating: "a", count: 31)] {
            #expect(!UsernameParser.valid(value))
        }
        #expect(UsernameParser.unique(["B", "a", "B", "A", "a"]) == ["B", "a", "A"])
    }

    @Test func jsonArrayOrderNormalizationAndReservedNames() throws {
        let text = #"[{"string_list_data":[{"value":" @Peel_B "},{"value":"PEEL_A"},{"value":"peel_b"},{"value":"followers"},{"value":"bad-name"}]},{"username":"Peel_C"}]"#
        #expect(try UsernameParser.parse(text: text, filename: "FOLLOWING.JSON") == ["peel_b", "peel_a", "peel_c"])
    }

    @Test func jsonSameObjectKeepsStringListBeforeUsername() throws {
        #expect(try UsernameParser.parse(text: #"{"username":"Peel_C","string_list_data":[{"value":"Peel_B"},{"value":"Peel_A"}]}"#,
                                        filename: "list.json") == ["peel_b", "peel_a", "peel_c"])
    }

    @Test func recognizedEmptyStructuresStayDistinctFromUnknownOrInvalidEntries() throws {
        for text in ["[]", #"{"relationships_following":[]}"#, #"{"relationships_followers":[]}"#, #"{"string_list_data":[]}"#] {
            #expect(try UsernameParser.parse(text: text, filename: "list.json") == [])
        }
        for text in ["{}", #"{"unknown":[]}"#, #"{"string_list_data":[{"value":42}]}"#, #"{"username":"followers"}"#] {
            #expect(throws: PeelError.unsupportedFormat) { try UsernameParser.parse(text: text, filename: "list.json") }
        }
        #expect(throws: PeelError.invalidJSON) { try UsernameParser.parse(text: "{broken", filename: "list.json") }
    }

    @Test func jsonDepthLimitIsPreserved() {
        let text = String(repeating: "[", count: 66) + "{}" + String(repeating: "]", count: 66)
        #expect(throws: PeelError.unsupportedFormat) { try UsernameParser.parse(text: text, filename: "list.json") }
    }

    @Test func htmlRegexOrderVariantsAndReservedPaths() throws {
        let html = #"<a href="HTTP://WWW.INSTAGRAM.COM/_u/Peel_B/">B</a><a href='instagram.com/Peel_A?x=1'>A</a><a href="https://instagram.com/peel_b">B</a><a href="https://instagram.com/explore/">X</a>"#
        #expect(try UsernameParser.parse(text: html, filename: "followers.HTM") == ["peel_b", "peel_a"])
        #expect(throws: PeelError.unsupportedFormat) { try UsernameParser.parse(text: "<html>empty</html>", filename: "list.html") }
    }

    @Test func textDelimitersURLPathsAndFirstOccurrenceOrder() throws {
        let text = "username\n'@Peel_B';ignored\nhttps://www.instagram.com/_u/Peel_A/\nPEEL_B,ignored\nhttps://instagram.com/Peel_C/extra\ninvalid-name\nPeel_D\tignored"
        #expect(try UsernameParser.parse(text: text, filename: "list.csv") == ["peel_b", "peel_a", "peel_c", "peel_d"])
        // Unknown extensions intentionally keep the existing text branch.
        #expect(try UsernameParser.parse(text: "@Peel_A", filename: "list.unknown") == ["peel_a"])
        for text in ["", "username\nfollowers", "https://example.com/peel_a"] {
            #expect(throws: PeelError.unsupportedFormat) { try UsernameParser.parse(text: text, filename: "list.txt") }
        }
    }

    @Test func byteLimitAndCancellationRemainErrors() async {
        #expect(throws: PeelError.tooLarge) {
            try UsernameParser.parse(text: String(repeating: "a", count: 16 * 1024 * 1024 + 1), filename: "list.txt")
        }
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try UsernameParser.parse(text: "peel_a", filename: "list.txt")
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled parser succeeded") }
        catch { #expect(error is CancellationError) }
    }

    @Test func archiveImportKeepsEntryOrderAndDeduplicatesAcrossFiles() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try archive([
            ("followers_2.json", Data(#"[{"username":"Peel_B"},{"username":"Peel_A"}]"#.utf8)),
            ("following.json", Data(#"[{"username":"Peel_C"}]"#.utf8)),
            ("followers_1.json", Data(#"[{"username":"PEEL_B"},{"username":"Peel_D"}]"#.utf8))
        ]).write(to: url)
        let result = try await ImportService().importZIP(url)
        #expect(result.followers == ["peel_b", "peel_a", "peel_d"])
        #expect(result.following == ["peel_c"])
    }

    @Test func emptyArchiveListsRemainValidAndUTF8FailureKeepsItsError() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try archive([("following.json", Data("[]".utf8)), ("followers.json", Data("[]".utf8))]).write(to: url)
        let result = try await ImportService().importZIP(url)
        #expect(result.following.isEmpty && result.followers.isEmpty)
        try archive([("following.json", Data([0xff])), ("followers.json", Data("[]".utf8))]).write(to: url)
        do { _ = try await ImportService().importZIP(url); Issue.record("Invalid UTF-8 succeeded") }
        catch { #expect(error as? InstagramZIPError == .invalidFile) }
    }

    // Fictional stored ZIP fixture; CRC is independent of production ZIP code.
    private func archive(_ entries: [(String, Data)]) -> Data {
        var body = Data()
        var directory = Data()
        func append(_ value: Int, bytes: Int, to data: inout Data) {
            for shift in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) }
        }
        for (name, payload) in entries {
            let filename = Data(name.utf8)
            let offset = body.count
            var crc: UInt32 = 0xffff_ffff
            for byte in payload {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb8_8320) }
            }
            let checksum = Int(crc ^ 0xffff_ffff)
            for (value, size) in [(0x04034b50,4),(20,2),(0,2),(0,2),(0,2),(0,2),(checksum,4),
                                  (payload.count,4),(payload.count,4),(filename.count,2),(0,2)] {
                append(value, bytes: size, to: &body)
            }
            body.append(filename); body.append(payload)
            for (value, size) in [(0x02014b50,4),(20,2),(20,2),(0,2),(0,2),(0,2),(0,2),(checksum,4),
                                  (payload.count,4),(payload.count,4),(filename.count,2),(0,2),(0,2),(0,2),(0,2),(0,4),(offset,4)] {
                append(value, bytes: size, to: &directory)
            }
            directory.append(filename)
        }
        let offset = body.count
        body.append(directory)
        for (value, size) in [(0x06054b50,4),(0,2),(0,2),(entries.count,2),(entries.count,2),(directory.count,4),(offset,4),(0,2)] {
            append(value, bytes: size, to: &body)
        }
        return body
    }
}
