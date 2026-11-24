import SwiftUI

struct InstagramExportBrowser: View {
    @StateObject private var state = BrowserLoadState()
    var body: some View {
        InstagramWebView(url: InstagramEndpoints.export, username: nil, state: state)
            .browserFeedback(state)
    }
}
