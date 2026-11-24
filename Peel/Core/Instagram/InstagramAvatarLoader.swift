import Foundation
import UIKit
import ImageIO

struct AvatarLoader: Sendable {
    let client: any HTTPClient
    func image(_ username: String) async throws -> UIImage {
        guard let url = InstagramEndpoints.profile(username) else { throw PeelError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await client.data(for: request, maxBytes: 1_000_000)
        guard let html = String(data: data, encoding: .utf8) else { throw PeelError.unsupportedFormat }
        let imageURL = try AvatarMetadata.imageURL(in: html)
        let bytes = try await client.data(for: URLRequest(url: imageURL), maxBytes: 3_000_000)
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
    private var active = 0
    private var pausedUntil = Date.distantPast
    func pause(until date: Date) { pausedUntil = max(pausedUntil, date) }

    func acquire() async throws {
        while active >= 4 || Date() < pausedUntil {
            try await Task.sleep(for: .seconds(max(0.05, pausedUntil.timeIntervalSinceNow)))
        }
        try Task.checkCancellation()
        active += 1
    }
    func release() { active -= 1 }
}
