import Foundation

struct ProgressFile: Codable, Sendable {
    var format: String = "follow-manager-backup-v1"
    var exportedAt: String
    var state: QueueState
    var excluded: [String]? = nil
    var nonMutualReviewed: [String]? = nil
    var mutualReviewed: [String]? = nil
    var importedFollowing: [String]? = nil
    var importedFollowers: [String]? = nil
}
