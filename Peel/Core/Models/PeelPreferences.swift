import Foundation

struct PeelPreferences: Codable, Sendable {
    var excluded: [String]
    var nonMutualReviewed: [String]
    var mutualReviewed: [String]?
    var followers: [String]
    var following: [String]
}
