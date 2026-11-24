import Foundation
import Testing
@testable import Peel

struct ImportFailureTests {
    @Test func truncatedZIPDoesNotReachUnsafeBuffers() {
        #expect(throws: (any Error).self) { try InstagramZIPReader.extractLists(from: Data()) }
        #expect(throws: (any Error).self) { try InstagramZIPReader.extractLists(from: Data(repeating: 0, count: 22)) }
    }

    @Test func crcUsesStandardZIPPolynomial() throws {
        #expect(try InstagramZIPReader.crc32(Data("123456789".utf8)) == 0xcbf43926)
    }

    @Test func unsupportedJSONIsNotAcceptedAsEmptyExport() {
        #expect(throws: PeelError.unsupportedFormat) {
            try UsernameParser.parse(text: #"{"unexpected":[]}"#, filename: "followers.json")
        }
    }

    @Test func recognizedEmptyListsRemainValid() throws {
        #expect(try UsernameParser.parse(text: "[]", filename: "followers.json").isEmpty)
        #expect(try UsernameParser.parse(text: #"{"relationships_following":[]}"#, filename: "following.json").isEmpty)
    }

    @Test func changedHTMLHasActionableFailure() {
        #expect(throws: PeelError.unsupportedFormat) {
            try UsernameParser.parse(text: "<html>New format</html>", filename: "followers.html")
        }
    }

    @Test func boundedReadRejectsOversizedFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 1, count: 17).write(to: url)
        #expect(throws: PeelError.tooLarge) { try ImportService.read(url, limit: 16) }
    }

    @Test func cancellationReachesAnInFlightImportWorker() async throws {
        let started = AsyncStream<Void>.makeStream()
        let observedCancellation = AsyncStream<Bool>.makeStream()
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            try await ImportService().work {
                started.continuation.yield(())
                release.wait()
                observedCancellation.continuation.yield(Task.isCancelled)
                try Task.checkCancellation()
                return 0
            }
        }
        defer {
            task.cancel()
            release.signal()
            started.continuation.finish()
            observedCancellation.continuation.finish()
        }
        var startIterator = started.stream.makeAsyncIterator()
        _ = try #require(await startIterator.next())
        task.cancel()
        release.signal()
        do { _ = try await task.value; Issue.record("Cancelled import worker succeeded") }
        catch { #expect(error is CancellationError) }
        var cancellationIterator = observedCancellation.stream.makeAsyncIterator()
        let workerWasCancelled = await cancellationIterator.next()
        #expect(workerWasCancelled == true)
    }

    @Test func invalidListEntryIsNotMistakenForAnEmptyList() {
        #expect(throws: PeelError.unsupportedFormat) {
            try UsernameParser.parse(text: #"{"relationships_following":[{"string_list_data":[{"value":42}]}]}"#,
                                     filename: "following.json")
        }
    }
}
