import SwiftUI

struct PeelPrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PrivacySection(
                    title: "Saved on this device",
                    text: "Peel saves imported usernames, exclusions, and review progress in its local app storage. iOS may include local app data in device backups."
                )
                PrivacySection(
                    title: "Instagram website sessions",
                    text: "Sign-in takes place in a WebKit browser. Website cookies and session data may persist after the browser closes. Login Complete is your confirmation; Peel cannot verify Instagram authentication."
                )
                PrivacySection(
                    title: "Avatar requests",
                    text: "Loading profile photos sends network requests to Instagram and its image providers. Embedded website content may also contact service providers."
                )
                PrivacySection(
                    title: "Release checks",
                    text: "At startup and when you select Check for Updates, Peel checks GitHub for a newer public release. This request does not include your Instagram account, imported lists or review progress. Peel never downloads or installs updates automatically."
                )
                PrivacySection(
                    title: "Profile photo cache",
                    text: "Downloaded profile thumbnails are saved in the app’s private cache to reduce repeat downloads and remain available without a connection. They are excluded from backups and are not included in exported Peel backups. iOS may remove cached photos. Use Menu → Reset Data → Clear Cache to remove them and rebuild the photo library as you browse."
                )
                PrivacySection(
                    title: "Backups and sharing",
                    text: "JSON backups contain imported usernames, exclusions, and review progress. Sharing sends the file to the destination you choose. Keep backups private. Reset Lists does not delete copies you have already shared."
                )
                PrivacySection(
                    title: "Reset and logout",
                    text: "Reset Lists clears imported lists, exclusions, and review progress while keeping the website session. Log Out requests removal of matching Instagram and Meta website data in Peel; imported lists and progress remain saved."
                )
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("Privacy & Storage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacySection: View {
    let title: LocalizedStringResource
    let text: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}
