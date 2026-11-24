import SwiftUI

struct InstagramBrowser: View {
    let username: String
    @ObservedObject var state: BrowserLoadState
    var body: some View {
        InstagramWebView(url: InstagramEndpoints.profile(username), username: username, state: state)
            .browserFeedback(state)
    }
}
