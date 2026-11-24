import Foundation
import UIKit
import Testing
@testable import Peel

@MainActor
struct InstagramAvatarRequestContractTests {
    private let imageURL = URL(string: "https://cdninstagram.com/fictional.png?a=1&b=2")
    private let page = Data(#"<meta property="og:image" content="https://cdninstagram.com/fictional.png?a=1&amp;b=2">"#.utf8)

    private func png() throws -> Data {
        try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg=="))
    }

    @Test func twoRequestsRetainExactConstructionAndBounds() async throws {
        let client = MockHTTPClient([.data(page), .data(try png())])
        let image = try await AvatarLoader(client: client).image("Peel.Fixture_1")
        #expect(image.cgImage?.width == 1)
        #expect(image.cgImage?.height == 1)
        let records = await client.recordedRequests
        #expect(records.count == 2)
        let profile = try #require(records.first)
        #expect(profile.request.url?.absoluteString == "https://www.instagram.com/Peel.Fixture_1/")
        #expect(profile.request.httpMethod == "GET")
        #expect(profile.request.timeoutInterval == 8)
        #expect(profile.request.value(forHTTPHeaderField: "Accept") == "text/html")
        #expect(profile.request.value(forHTTPHeaderField: "User-Agent") == nil)
        #expect(profile.request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(profile.maxBytes == 1_000_000)
        let photo = records[1]
        let expected = URLRequest(url: try #require(imageURL))
        #expect(photo.request.url == expected.url)
        #expect(photo.request.httpMethod == expected.httpMethod)
        #expect(photo.request.timeoutInterval == expected.timeoutInterval)
        #expect(photo.request.cachePolicy == expected.cachePolicy)
        #expect(photo.request.allHTTPHeaderFields == expected.allHTTPHeaderFields)
        #expect(photo.maxBytes == 3_000_000)
    }

    @Test func decodingKeepsMaximumThumbnailDimension() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80))
        let data = renderer.pngData { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let client = MockHTTPClient([.data(page), .data(data)])
        let image = try await AvatarLoader(client: client).image("peel_fixture")
        let cgImage = try #require(image.cgImage)
        #expect(max(cgImage.width, cgImage.height) == 48)
    }

    @Test func invalidUsernameMakesNoRequest() async {
        let client = MockHTTPClient([])
        await #expect(throws: PeelError.invalidURL) {
            try await AvatarLoader(client: client).image("invalid/name")
        }
        #expect(await client.requests == 0)
    }

    @Test func invalidHTMLStopsBeforeImageRequest() async {
        for data in [Data([0xff]), Data("<html>changed</html>".utf8)] {
            let client = MockHTTPClient([.data(data)])
            await #expect(throws: PeelError.unsupportedFormat) {
                try await AvatarLoader(client: client).image("peel_fixture")
            }
            #expect(await client.requests == 1)
        }
    }

    @Test func cancellationBeforeTransportRemainsCancellation() async {
        let client = MockHTTPClient([.data(page)])
        let loader = AvatarLoader(client: client)
        let task = Task { try await loader.image("peel_fixture") }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled request succeeded") }
        catch { #expect(error is CancellationError) }
        #expect(await client.requests == 0)
    }
}
