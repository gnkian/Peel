import SwiftUI

struct HowPeelWorksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("How Peel works", systemImage: "info.circle").font(.title2.bold())
                Text("1 · Sign in to Instagram").font(.headline)
                Text("Peel opens Instagram in an in-app browser. You sign in on Instagram's website, not to a Peel account. Peel does not collect or store your password; Instagram may retain website session data.")
                Text("2 · Request and import your data").font(.headline)
                Text("Use Instagram's Accounts Center to request a Followers and following export. Instagram prepares it asynchronously. Download the ZIP and import it directly into Peel; no extraction is needed.")
                Text("3 · Compare and review").font(.headline)
                Text("Peel compares imported usernames on your device. It shows accounts that don't follow you back, your followers, and mutual accounts.")
                Text("4 · Review manually").font(.headline)
                Text("Mass Unfollow opens Instagram profiles one by one. Peel does not automatically unfollow anyone. You decide what to do on Instagram. A profile is marked reviewed after it loads; this does not confirm an unfollow.")
                Text("Your imported lists, exclusions, and review progress are stored locally by Peel. Backups contain usernames, so keep them private.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(bg.ignoresSafeArea())
        .navigationTitle("How Peel Works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
