import Foundation
import Testing
@testable import Peel

struct InstagramProfileMetadataParserTests {
    @Test func forwardPatternPrecedesEarlierReverseTag() throws {
        let html = """
        <meta content="https://cdninstagram.com/earlier.png" property="og:image">
        <meta property="og:image" content="https://cdninstagram.com/preferred.png">
        <meta property="og:image" content="https://cdninstagram.com/later.png">
        """
        #expect(try AvatarMetadata.imageURL(in: html).absoluteString == "https://cdninstagram.com/preferred.png")
    }

    @Test func invalidFirstPreferredMatchDoesNotFallBack() {
        let html = """
        <meta content="https://cdninstagram.com/reverse.png" property="og:image">
        <meta property="og:image" content="https://untrusted.example/first.png">
        <meta property="og:image" content="https://cdninstagram.com/second.png">
        """
        #expect(throws: PeelError.invalidURL) { try AvatarMetadata.imageURL(in: html) }
    }

    @Test func attributeCaseQuotesAndEntityDecodingStayExact() throws {
        let html = #"<META NAME='OG:IMAGE' CONTENT='https://sub.fbcdn.net/a.png?a=1&amp;b=2&amp;amp;c=3'>"#
        #expect(try AvatarMetadata.imageURL(in: html).absoluteString == "https://sub.fbcdn.net/a.png?a=1&b=2&amp;c=3")
        #expect(throws: PeelError.unsupportedFormat) {
            try AvatarMetadata.imageURL(in: #"<meta property = "og:image" content = "https://cdninstagram.com/a.png">"#)
        }
    }

    @Test func metadataURLAcceptanceRemainsIndependent() throws {
        for value in ["https://instagram.com/a", "https://sub.cdninstagram.com/a",
                      "https://FBCDN.NET/a", "https://cdninstagram.com:8443/a"] {
            #expect(try AvatarMetadata.imageURL(in: "<meta property='og:image' content='\(value)'>").absoluteString == value)
        }
        for value in ["http://cdninstagram.com/a", "https://facebook.com/a",
                      "https://cdninstagram.com.evil.example/a", "/relative.png"] {
            #expect(throws: PeelError.invalidURL) {
                try AvatarMetadata.imageURL(in: "<meta property='og:image' content='\(value)'>")
            }
        }
        // Characterize the actual scheme spelling Foundation supplies, rather than
        // assuming it normalizes URL input on every supported runtime.
        let uppercase = try #require(URL(string: "HTTPS://cdninstagram.com/a"))
        let html = "<meta property='og:image' content='\(uppercase.absoluteString)'>"
        if uppercase.scheme == "https" {
            #expect(try AvatarMetadata.imageURL(in: html) == uppercase)
        } else {
            #expect(throws: PeelError.invalidURL) { try AvatarMetadata.imageURL(in: html) }
        }
        #expect(InstagramEndpoints.allowedImageURL(uppercase))
    }

    @Test func missingOrEmptyMetadataKeepsFailureClassification() {
        #expect(throws: PeelError.unsupportedFormat) { try AvatarMetadata.imageURL(in: "<html></html>") }
        #expect(throws: PeelError.unsupportedFormat) {
            try AvatarMetadata.imageURL(in: #"<meta property="og:image" content="">"#)
        }
    }
}
