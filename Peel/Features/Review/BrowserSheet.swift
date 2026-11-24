import SwiftUI

struct BrowserSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: PeelModel
    @StateObject private var browserState = BrowserLoadState()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 9) {
                    AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(orange)
                        Text("\(model.browserReviewedCount) of \(model.browserUsers.count) reviewed")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Spacer()
                        Text("\(model.browserRemaining) left")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    PeelProgressBar(
                        fraction: model.browserUsers.isEmpty ? 0 :
                            Double(model.browserReviewedCount) / Double(model.browserUsers.count)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(model.browserReviewedCount) of \(model.browserUsers.count) accounts reviewed", comment: "First count is reviewed accounts; second count is total accounts."))
                if let username = model.instagramUser {
                    InstagramBrowser(username: username, state: browserState)
                        .id("instagram-browser")
                }
                AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reviewed \(model.browserReviewedCount) / \(model.browserUsers.count)")
                            .font(.caption.weight(.semibold))
                        Text("\(model.browserRemaining) remaining").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { model.previousInBrowser() } } label: {
                        Image(systemName: "arrow.left")
                    }
                    .buttonStyle(CompactGrayButton())
                    .accessibilityLabel("Previous Account")
                    .disabled(!model.canEditLists || model.browserIndex == 0)
                    Button {
                        if model.browserRemaining == 0 { dismiss(); model.instagramUser = nil }
                        else { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { _ = model.nextInBrowser() } }
                    } label: {
                        Label(model.browserRemaining == 0 ? LocalizedStringResource("Completed!") : LocalizedStringResource("Next Account"), systemImage: model.browserRemaining == 0 ? "checkmark" : "arrow.right")
                    }
                    .buttonStyle(CompactOrangeButton())
                    .disabled(!model.canEditLists || browserState.phase != .loaded)
                }
                .padding(12)
                .background(panel)
            }
            .background(bg)
            .navigationTitle(model.instagramUser.map { "@" + $0 } ?? "Instagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "xmark")
                    }.foregroundStyle(orange)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let username = model.instagramUser,
                       let url = InstagramEndpoints.profile(username) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Share Profile")
                    }
                }
            }
        }
        .operationFeedback(model: model)
        .onAppear {
            browserState.reviewToken = model.browserRequestID
            browserState.onProfileLoaded = { user, token in
                model.profileDidLoad(user, requestID: token)
            }
        }
        .onChange(of: model.browserRequestID) { _, token in browserState.reviewToken = token }
    }
}
