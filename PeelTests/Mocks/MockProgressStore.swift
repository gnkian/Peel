import Foundation
@testable import Peel

@MainActor
final class MockProgressStore: ProgressStore {
    var bytes: (Data?, Data?, Data?) = (nil, nil, nil)
    var failWrites = false
    var writes = 0
    func read() throws -> (Data?, Data?, Data?) { bytes }
    func save(_ snapshot: SavedSnapshot) throws {
        if failWrites { throw PeelError.persistence }
        let encoded = try JSONEncoder().encode(snapshot)
        bytes = (nil, nil, encoded)
        writes += 1
    }
}

