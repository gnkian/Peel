import SwiftUI

@main struct PeelApp: App {
    @Environment(\.openURL) private var openURL
    @State private var updateChecker = ReleaseUpdateChecker()

    var body: some Scene {
        WindowGroup {
            PeelTabs()
                .environment(updateChecker)
                .preferredColorScheme(.dark)
                .task {
                    #if PEEL_Debug
                    // Existing UI tests use disposable storage and must not contact GitHub.
                    if ProcessInfo.processInfo.environment["PEEL_UI_TEST_STORAGE_DOMAIN"]?.hasPrefix("PeelUITests.") == true { return }
                    #endif
                    await updateChecker.checkAtStartup()
                }
                .alert("Update Available", isPresented: $updateChecker.showsUpdate,
                       presenting: updateChecker.availableUpdate) { update in
                    Button("View Release") { openURL(update.url) }
                    Button("Not Now", role: .cancel) { }
                } message: { update in
                    Text("Peel \(update.version) is available. Open GitHub to view the release. Updates are installed manually.",
                         comment: "The variable is the newer Peel release version number.")
                }
        }
    }
}
