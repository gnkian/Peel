import Foundation
import Testing
import UIKit
@testable import Peel

@MainActor
struct AvatarDiskCacheTests {
    private var picture: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
    private let page = Data(#"<meta property="og:image" content="https://cdninstagram.com/fixture.png">"#.utf8)
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func thumbnailsSurviveNewStoreAndLoadWithoutNetwork() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AvatarDiskCache(directory: directory.appendingPathComponent("photos"))
        let first = InstagramAvatarStore(client: MockHTTPClient([.data(page), .data(picture)]), diskCache: cache)
        await first.load("apple")
        #expect(first.cacheBytes == Int64(first.image(for: "apple")?.pngData()?.count ?? 0))
        let offline = MockHTTPClient([.failure(.offline)])
        let second = InstagramAvatarStore(client: offline, diskCache: AvatarDiskCache(directory: directory.appendingPathComponent("photos")))
        await second.load("apple")
        #expect(second.image(for: "apple") != nil)
        #expect(await offline.requests == 0)
        #expect(second.cacheBytes == first.cacheBytes)
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("photos"), includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(!files[0].lastPathComponent.contains("apple"))
        #expect(try directory.appendingPathComponent("photos").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func memorySnapshotIsPersistedAndSizeMatchesActualFiles() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AvatarDiskCache(directory: directory)
        let store = InstagramAvatarStore(client: MockHTTPClient([.data(page), .data(picture)]), diskCache: cache)
        await store.load("apple")
        // Simulate iOS purging disposable disk files while the thumbnail remains in memory.
        try await cache.clear()
        #expect(try await cache.byteCount() == 0)
        try await store.refreshCacheSize()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(Int64(0)) { try $0 + Int64($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        #expect(store.cacheBytes == bytes)
        #expect(bytes > 0)
    }

    @Test func clearCacheDoesNotAlterRelationshipsOrAcceptLateWrites() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sibling = directory.appendingPathComponent("progress.json")
        let progress = Data("personal review progress".utf8)
        try progress.write(to: sibling)
        let cache = AvatarDiskCache(directory: directory.appendingPathComponent("photos"))
        let oldGeneration = await cache.currentGeneration()
        let store = InstagramAvatarStore(client: MockHTTPClient([.data(page), .data(picture)]), diskCache: cache)
        await store.load("apple")
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let model = try await fixture.restoredModel()
        model.followingNames = ["apple", "google"]
        model.followerNames = ["apple"]
        model.compare()
        model.toggleExclude("google")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let snapshot = try encoder.encode(model.snapshot)
        try await store.clearCache()
        #expect(store.images.isEmpty)
        #expect(store.cacheBytes == 0)
        #expect(store.cacheRevision == 1)
        try await cache.save(picture, for: "late", generation: oldGeneration)
        #expect(await cache.data(for: "late") == nil)
        #expect(try await cache.byteCount() == 0)
        #expect(try Data(contentsOf: sibling) == progress)
        #expect(try encoder.encode(model.snapshot) == snapshot)
    }

    @Test func clearDuringDownloadPreventsRepopulation() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AvatarDiskCache(directory: directory)
        let client = MockHTTPClient([.data(page), .data(picture)], holdingReplies: true)
        let store = InstagramAvatarStore(client: client, diskCache: cache)
        let load = Task { await store.load("apple") }
        await client.waitForRequests(1)
        try await store.clearCache()
        await client.resumeReplies()
        await load.value
        #expect(store.images.isEmpty)
        #expect(try await cache.byteCount() == 0)
        #expect(await cache.data(for: "apple") == nil)
    }

    @Test func savedPhotosRemainAvailableDuringGlobalCooldownAndClearPreservesIt() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AvatarDiskCache(directory: directory)
        let generation = await cache.currentGeneration()
        try await cache.save(picture, for: "apple", generation: generation)
        let now = Date()
        let until = now.addingTimeInterval(120)
        let client = MockHTTPClient([.failure(.rateLimited(until))])
        let store = InstagramAvatarStore(client: client, now: { now }, diskCache: cache)
        await store.load("limited")
        await store.load("apple")
        #expect(store.image(for: "apple") != nil)
        #expect(await client.requests == 1)
        try await store.clearCache()
        #expect(store.retryAvailableAt("apple") == until)
        await store.load("apple")
        #expect(await client.requests == 1)
    }

    @Test func cacheIsBoundedAndCorruptionFallsBackSafely() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AvatarDiskCache(directory: directory, capacity: Int64(picture.count))
        let generation = await cache.currentGeneration()
        try await cache.save(picture, for: "apple", generation: generation)
        try await cache.save(picture, for: "google", generation: generation)
        #expect(try await cache.byteCount() <= Int64(picture.count))
        #expect(await cache.data(for: "google") != nil)
        try await cache.clear()
        let current = await cache.currentGeneration()
        try await cache.save(Data("invalid image".utf8), for: "apple", generation: current)
        #expect(await cache.data(for: "apple") == nil)
        let client = MockHTTPClient([.data(page), .data(picture)])
        let store = InstagramAvatarStore(client: client, diskCache: cache)
        await store.load("apple")
        #expect(store.image(for: "apple") != nil)
        #expect(await client.requests == 2)
        #expect(await cache.data(for: "apple") != nil)
    }

    @Test func clearFailureIsReportedWithoutClaimingZeroBytes() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AvatarDiskCache(directory: directory, fileManager: CacheRemovalFailureFileManager())
        let store = InstagramAvatarStore(client: MockHTTPClient([.data(page), .data(picture)]), diskCache: cache)
        await store.load("apple")
        #expect(store.cacheBytes > 0)
        do {
            try await store.clearCache()
            Issue.record("A failed removal must be reported")
        } catch {
            #expect((error as? CocoaError)?.code == .fileWriteNoPermission)
        }
        #expect(store.cacheBytes > 0)
        #expect(!store.isClearingCache)
    }

    @Test func cacheWriteFailureDoesNotHideLoadedPhoto() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let cache = AvatarDiskCache(directory: blocker.appendingPathComponent("photos"))
        let client = MockHTTPClient([.data(page), .data(picture)])
        let store = InstagramAvatarStore(client: client, diskCache: cache)
        await store.load("apple")
        #expect(store.image(for: "apple") != nil)
        #expect(store.cacheBytes == 0)
    }
}

private final class CacheRemovalFailureFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
}
