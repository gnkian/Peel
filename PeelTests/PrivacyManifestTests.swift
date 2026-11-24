import Foundation
import Testing
@testable import Peel

struct PrivacyManifestTests {
    @Test func appBundleIncludesVerifiedRequiredReasonDeclaration() throws {
        let url = try #require(Bundle(for: PeelModel.self).url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let apis = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(apis.count == 1)
        let declaration = try #require(apis.first)
        #expect(declaration["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(declaration["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }
}
