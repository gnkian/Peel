import Foundation
import OSLog

protocol ImportServicing: Sendable {
    func importZIP(_ url: URL) async throws -> ImportResult
    func importList(_ urls: [URL], kind: ListKind) async throws -> [String]
    func restore(_ url: URL, current: SavedSnapshot) async throws -> SavedSnapshot
}

struct ImportService: ImportServicing {
    /// Detached work has explicit cancellation propagation; file access remains scoped
    /// for the entire read. No model or UserDefaults crosses into this worker.
    func work<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        let worker = Task.detached(priority: .userInitiated, operation: body)
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }

    static func read(_ url: URL, limit: Int) throws -> Data {
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var result: Result<Data, Error>?
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
                let type = (try? readableURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier ?? "unknown"
                ImportDiagnostics.logger.debug("Reading selected document; type=\(type, privacy: .public), scoped=\(scoped)")
                result = Result { try readContents(readableURL, limit: limit) }
            }
            try Task.checkCancellation()
            if let coordinationError { throw coordinationError }
            guard let result else { throw PeelError.unreadableFile }
            return try result.get()
        } catch is CancellationError { throw CancellationError() }
        catch let error as PeelError { throw error }
        catch {
            let underlying = error as NSError
            ImportDiagnostics.logger.error("Document read failed; domain=\(underlying.domain, privacy: .public), code=\(underlying.code)")
            throw PeelError.unreadableFile
        }
    }

    private static func readContents(_ url: URL, limit: Int) throws -> Data {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Data()
        while let chunk = try handle.read(upToCount: min(65_536, limit + 1 - result.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            result.append(chunk)
            guard result.count <= limit else { throw PeelError.tooLarge }
        }
        return result
    }

    func importZIP(_ url: URL) async throws -> ImportResult {
        try await work {
            let files = try InstagramZIPReader.extractLists(from: Self.read(url, limit: 100 * 1024 * 1024))
            var following: [String] = []
            var followers: [String] = []
            var kinds = Set<String>()
            for (name, data) in files {
                try Task.checkCancellation()
                guard let text = String(data: data, encoding: .utf8) else { throw InstagramZIPError.invalidFile }
                guard let kind = InstagramExportParser.detectType(text: text, filename: URL(fileURLWithPath: name).lastPathComponent) else {
                    throw PeelError.unsupportedFormat
                }
                let names = try InstagramExportParser.parse(text: text, filename: name)
                kinds.insert(kind.rawValue)
                if kind == .following { following += names } else { followers += names }
            }
            guard kinds == ["following", "followers"] else { throw InstagramZIPError.missingLists }
            return ImportResult(following: UsernameRules.unique(following), followers: UsernameRules.unique(followers))
        }
    }

    func importList(_ urls: [URL], kind: ListKind) async throws -> [String] {
        try await work {
            var names: [String] = []
            var total = 0
            for url in urls {
                let data = try Self.read(url, limit: 16 * 1024 * 1024)
                total += data.count
                guard total <= 40 * 1024 * 1024 else { throw PeelError.tooLarge }
                guard let text = String(data: data, encoding: .utf8) else { throw PeelError.unsupportedFormat }
                if let detected = InstagramExportParser.detectType(text: text, filename: url.lastPathComponent), detected != kind {
                    throw ImportError.wrongType(url.lastPathComponent)
                }
                names += try InstagramExportParser.parse(text: text, filename: url.lastPathComponent)
            }
            guard !urls.isEmpty else { throw PeelError.unreadableFile }
            return UsernameRules.unique(names)
        }
    }

    func restore(_ url: URL, current: SavedSnapshot) async throws -> SavedSnapshot {
        try await work {
            let data = try Self.read(url, limit: 40 * 1024 * 1024)
            let file: ProgressFile
            do { file = try JSONDecoder().decode(ProgressFile.self, from: data) }
            catch { throw PeelError.invalidBackup }
            return try SavedStateValidator.backup(file, merging: current)
        }
    }
}
