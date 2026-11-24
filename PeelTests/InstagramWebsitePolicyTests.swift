import Foundation
import Testing
@testable import Peel

struct InstagramWebsitePolicyTests {
    @Test func endpointStringsAndUsernameConstructionStayExact() {
        #expect(InstagramEndpoints.login?.absoluteString == "https://www.instagram.com/accounts/login/")
        #expect(InstagramEndpoints.export?.absoluteString == "https://accountscenter.instagram.com/info_and_permissions/dyi/")
        #expect(InstagramEndpoints.profile("Peel.Fixture_1")?.absoluteString == "https://www.instagram.com/Peel.Fixture_1/")
        for value in ["", "@fixture", "has space", "../fixture", String(repeating: "a", count: 31)] {
            #expect(InstagramEndpoints.profile(value) == nil)
        }
    }

    @Test func transportHostAndSchemeAcceptanceStayExact() throws {
        let accepted = ["https://instagram.com/a", "https://www.instagram.com/a",
                        "https://sub.cdninstagram.com/a", "HTTPS://FBCDN.NET/a",
                        "https://instagram.com:8443/a"]
        let rejected = ["http://instagram.com/a", "https://instagram.com.evil.example/a",
                        "https://evilinstagram.com/a", "https://facebook.com/a", "file:///a"]
        for value in accepted { #expect(InstagramEndpoints.allowedImageURL(try #require(URL(string: value)))) }
        for value in rejected { #expect(!InstagramEndpoints.allowedImageURL(try #require(URL(string: value)))) }
    }

    @Test func profileMatchingRetainsExactPathAndHostRules() throws {
        for value in ["https://instagram.com/FIXTURE/", "https://www.instagram.com/fixture?x=1",
                      "https://www.instagram.com/fixture/#fragment"] {
            let url = try #require(URL(string: value))
            #expect(InstagramEndpoints.isProfile(url, username: "fixture"))
        }
        for value in ["http://instagram.com/fixture", "https://sub.instagram.com/fixture",
                      "https://instagram.com/_u/fixture", "https://instagram.com/fixture/extra",
                      "https://instagram.com/other"] {
            let url = try #require(URL(string: value))
            #expect(!InstagramEndpoints.isProfile(url, username: "fixture"))
        }
        #expect(!InstagramEndpoints.isProfile(nil, username: "fixture"))
    }

    @Test func loginClassificationRetainsPrefixAndSchemeBehavior() throws {
        // Existing classification checks host/path, not scheme or a path-component boundary.
        for value in ["https://www.instagram.com/accounts/login/", "http://instagram.com/challenge/a",
                      "https://sub.instagram.com/checkpoint", "https://instagram.com/challenge_extra"] {
            let url = try #require(URL(string: value))
            #expect(InstagramEndpoints.needsLogin(url))
        }
        for value in ["https://instagram.com/Challenge", "https://facebook.com/challenge",
                      "https://instagram.com.evil.example/accounts/login", "https://instagram.com/fixture"] {
            let url = try #require(URL(string: value))
            #expect(!InstagramEndpoints.needsLogin(url))
        }
        #expect(!InstagramEndpoints.needsLogin(nil))
    }

    @MainActor @Test func logoutRecordMatchingRetainsSeparateDomainSet() {
        for value in ["instagram.com", "WWW.INSTAGRAM.COM", "facebook.com", "sub.fbcdn.net", "cdninstagram.com"] {
            #expect(InstagramSessionService.matchesWebsiteDataRecord(value))
        }
        for value in ["meta.com", "Instagram", "facebook.com.evil.example", "evilinstagram.com", ""] {
            #expect(!InstagramSessionService.matchesWebsiteDataRecord(value))
        }
    }

    @Test func avatarSessionConfigurationRemainsCookieDisabledAndBounded() {
        let configuration = URLSessionConfiguration.ephemeral
        _ = URLSessionHTTPClient(configuration: configuration)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.timeoutIntervalForRequest == 8)
        #expect(configuration.timeoutIntervalForResource == 20)
        #expect(configuration.httpMaximumConnectionsPerHost == 4)
    }
}
