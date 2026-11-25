import CryptoKit
import Foundation
import ImageIO

/// Disposable thumbnails only. Imported lists, credentials and review progress never enter this directory.
actor AvatarDiskCache {
    private let directory: URL
    private let capacity: Int64
    private let fileManager: FileManager
    private var generation = UUID()
    private struct Entry { let bytes: Int64; let date: Date }
    private var entries: [URL: Entry]?

    init(directory: URL = URL.cachesDirectory.appendingPathComponent("PeelProfilePhotos", isDirectory: true),
         capacity: Int64 = 32 * 1_024 * 1_024, fileManager: FileManager = .default) {
        self.directory = directory.resolvingSymlinksInPath()
        self.capacity = max(0, capacity)
        self.fileManager = fileManager
    }

    func currentGeneration() -> UUID { generation }

    func data(for username: String) -> Data? {
        guard UsernameParser.valid(username), !username.hasPrefix("peeldemo_") else { return nil }
        let file = fileURL(username)
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 128 * 1_024 else { return nil }
        guard let data = try? Data(contentsOf: file),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 48, height <= 48,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            try? fileManager.removeItem(at: file)
            entries?[file] = nil
            return nil
        }
        return data
    }

    func save(_ data: Data, for username: String, generation expected: UUID) throws {
        guard expected == generation, UsernameParser.valid(username), !username.hasPrefix("peeldemo_"),
              !data.isEmpty, data.count <= 128 * 1_024, Int64(data.count) <= capacity else { return }
        try loadEntries()
        let file = fileURL(username)
        // An existing thumbnail is reused until the user clears the cache or iOS removes it.
        if entries?[file] != nil, fileManager.fileExists(atPath: file.path) { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var folder = directory
        try folder.setResourceValues(resourceValues)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        entries?[file] = Entry(bytes: Int64(data.count), date: Date())
        var bytes = totalBytes
        if bytes > capacity {
            for (url, entry) in (entries ?? [:]).sorted(by: { $0.value.date < $1.value.date }) where bytes > capacity {
                try fileManager.removeItem(at: url)
                entries?[url] = nil
                bytes -= entry.bytes
            }
        }
    }

    func byteCount(reconcile: Bool = false) throws -> Int64 {
        // Reconcile on menu entry; ordinary writes update the inventory without rescanning it.
        if reconcile { entries = nil }
        try loadEntries()
        return totalBytes
    }

    func clear() throws {
        generation = UUID() // Late writes from requests started before Clear Cache are rejected.
        if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
        entries = [:]
    }

    private var totalBytes: Int64 { entries?.values.reduce(0) { $0 + $1.bytes } ?? 0 }

    private func fileURL(_ username: String) -> URL {
        let hash = SHA256.hash(data: Data(username.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".png")
    }

    private func loadEntries() throws {
        guard entries == nil else { return }
        guard fileManager.fileExists(atPath: directory.path) else { entries = [:]; return }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
        var found: [URL: Entry] = [:]
        for file in files where file.pathExtension == "png" {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            found[file] = Entry(bytes: Int64(values.fileSize ?? 0), date: values.contentModificationDate ?? .distantPast)
        }
        entries = found
    }
}
