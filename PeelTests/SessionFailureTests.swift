import Foundation
import Testing
@testable import Peel

@MainActor
private final class MockSession: InstagramSessionServicing {
    var signOuts = 0
    func signOut() async { signOuts += 1 }
}

@MainActor
struct SessionFailureTests {
    @Test func demoCannotClearRealSessionOrImportRealData() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let session = MockSession()
        let importer = ControlledImporter()
        let model = PeelModel(demo: true, defaults: fixture.defaults, importer: importer, session: session)
        let before = model.followingNames
        await model.signOut()
        await model.importZIP(URL(fileURLWithPath: "/fixture.zip")).value
        await model.restore(URL(fileURLWithPath: "/fixture.json")).value
        #expect(session.signOuts == 0)
        #expect(await importer.count == 0)
        #expect(model.followingNames == before)
        #expect(model.instagramLoginConfirmed)
    }

    @Test func liveLogoutPreservesListsAndReviewState() async throws {
        let fixture = try ModelFixture()
        defer { fixture.cleanUp() }
        let session = MockSession()
        let model = PeelModel(defaults: fixture.defaults, session: session)
        await model.reloadSavedData().value
        model.queue = QueueState(users: ["peel_a"], done: ["peel_a"])
        model.instagramLoginConfirmed = true
        await model.signOut()
        #expect(session.signOuts == 1)
        #expect(!model.instagramLoginConfirmed)
        #expect(model.queue.done == ["peel_a"])
    }
}
