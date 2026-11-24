import Foundation

struct QueueState: Codable, Sendable {
    var users: [String] = []
    var following: Int? = nil
    var followers: Int? = nil
    var done: [String] = []
    var cursor: Int = 0
    var lastOpened: String? = nil
    var mode: String = "none"
}
