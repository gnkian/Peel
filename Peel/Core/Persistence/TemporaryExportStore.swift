import Foundation

/// Tracks only files created by this process. Unconfirmed exports from older
/// processes are retained: a share extension may outlive the host application.
@MainActor
final class TemporaryExportStore {
    static let shared = TemporaryExportStore()

    private struct Entry {
        var consumers: Set<UUID> = []
        var wasShared = false
        var finished = false
    }

    private let directory: URL
    private let fileManager: FileManager
    private var entries: [URL: Entry] = [:]

    init(temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         fileManager: FileManager = .default) {
        directory = temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("PeelExports", isDirectory: true)
        self.fileManager = fileManager
    }

    func create(_ data: Data, write: (Data, URL) throws -> Void) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try validateDirectory()
        let url = directory.appendingPathComponent("peel-progress-\(UUID().uuidString).json")
        entries[url] = Entry()
        do {
            try write(data, url)
            return url
        } catch {
            // A writer can leave a partial file. No consumer has received this URL.
            entries[url]?.finished = true
            try? retryCleanup()
            throw error
        }
    }

    func beginSharing(_ url: URL) -> UUID? {
        guard entries[url] != nil, entries[url]?.finished == false else { return nil }
        let token = UUID()
        entries[url]?.wasShared = true
        entries[url]?.consumers.insert(token)
        return token
    }

    func finishSharing(_ url: URL, token: UUID) throws {
        guard entries[url]?.consumers.remove(token) != nil else { return }
        if entries[url]?.consumers.isEmpty == true { entries[url]?.finished = true }
        try retryCleanup()
    }

    func discardUnshared(_ url: URL) throws {
        guard let entry = entries[url], !entry.wasShared, entry.consumers.isEmpty else { return }
        entries[url]?.finished = true
        try retryCleanup()
    }

    func retryCleanup() throws {
        let finished = entries.keys.filter {
            entries[$0]?.finished == true && entries[$0]?.consumers.isEmpty == true
        }
        var firstError: Error?
        for url in finished {
            do {
                try validateDirectory()
                // No supplied URL is registered for deletion unless create generated it.
                try fileManager.removeItem(at: url)
                entries[url] = nil
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                entries[url] = nil // The OS may already have reclaimed a temporary file.
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func validateDirectory() throws {
        // Do not follow a substituted directory symlink into documents or other storage.
        guard directory.resolvingSymlinksInPath() == directory else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}
