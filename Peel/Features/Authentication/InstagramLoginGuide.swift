import SwiftUI

struct InstagramLoginGuide: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: PeelModel
    @StateObject private var loginState = BrowserLoadState()
    @State private var confirmLogin = false
    @State private var keyboardVisible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                InstagramLoginBrowser(state: loginState)
                if !keyboardVisible {
                VStack(spacing: 8) {
                    Button { confirmLogin = true } label: {
                        Label("Login complete", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OrangeButton())
                    .disabled(loginState.phase != .loaded || model.isDemo)
                    .popover(isPresented: $confirmLogin, arrowEdge: .bottom) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Login complete?")
                                    .font(.headline)
                                Text("Confirm after signing in. Peel cannot verify Instagram login status.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize, spacing: 12) {
                                    Button("Cancel") { confirmLogin = false }
                                        .buttonStyle(.bordered)
                                    Button("Continue") {
                                        confirmLogin = false
                                        model.instagramLoginConfirmed = true
                                        dismiss()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(orange)
                                }
                            }
                            .padding(18)
                        }
                        .frame(idealWidth: 300, maxWidth: 360, idealHeight: 240, maxHeight: 500)
                        .presentationCompactAdaptation(.popover)
                    }
                    Text("You sign in on Instagram’s website. WebKit may retain cookies and website session data. Peel does not collect your password and cannot verify login status.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(.regularMaterial)
                }
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("Sign in to Instagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)) } .accessibilityLabel("Close") } }
        }
        .tint(orange)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
            confirmLogin = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }
}
