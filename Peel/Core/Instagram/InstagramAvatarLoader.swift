import Foundation
import UIKit
import ImageIO
import os

struct AvatarLoader: Sendable {
    let client: any HTTPClient
    var measurements = AvatarMeasurements()
    func image(_ username: String) async throws -> UIImage {
        guard let url = InstagramEndpoints.profile(username) else { throw PeelError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await measurements.measure(.profileHTML) {
            try await client.data(for: request, maxBytes: 1_000_000)
        }
        guard let html = String(data: data, encoding: .utf8) else { throw PeelError.unsupportedFormat }
        let imageURL = try AvatarMetadata.imageURL(in: html)
        let bytes = try await measurements.measure(.image) {
            try await client.data(for: URLRequest(url: imageURL), maxBytes: 3_000_000)
        }
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 48
              ] as CFDictionary) else { throw PeelError.unavailable }
        return UIImage(cgImage: cgImage)
    }
}

/// Limits simultaneous avatar operations, including page and image retrieval.
actor AvatarRequestGate {
    private let now: @Sendable () async -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    init(now: @escaping @Sendable () async -> Date = { Date() },
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.now = now
        self.sleep = sleep
    }
    private var active = 0
    private var pausedUntil = Date.distantPast
    func pause(until date: Date) { pausedUntil = max(pausedUntil, date) }

    func acquire() async throws {
        while true {
            let date = await now()
            if active < 4 && date >= pausedUntil { break }
            try await sleep(max(0.05, pausedUntil.timeIntervalSince(date)))
        }
        try Task.checkCancellation()
        active += 1
    }
    func release() { active -= 1 }
}

/// Durations contain no usernames, URLs, cookies or response bodies.
struct AvatarMeasurements: Sendable {
    enum Stage: String, Sendable { case queue, profileHTML, image }
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Peel", category: "AvatarTiming")
    var record: @Sendable (Stage, Duration) -> Void = { stage, duration in
        let milliseconds = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        logger.debug("\(stage.rawValue, privacy: .public): \(milliseconds, privacy: .public) ms")
    }

    func measure<Value>(_ stage: Stage, operation: () async throws -> Value) async rethrows -> Value {
        let start = ContinuousClock.now
        defer { record(stage, start.duration(to: .now)) }
        return try await operation()
    }
}
