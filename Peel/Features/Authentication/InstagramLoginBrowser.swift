import SwiftUI

struct InstagramLoginBrowser: View {
    @ObservedObject var state: BrowserLoadState
    var body: some View {
        InstagramWebView(url: InstagramEndpoints.login, username: nil, state: state)
            .browserFeedback(state)
    }
}
