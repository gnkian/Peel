import SwiftUI

struct InstagramLoginGuide: View {
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
                    .alert("Login complete?", isPresented: $confirmLogin) {
                        Button("Cancel", role: .cancel) { }
                        Button("Continue") {
                            model.instagramLoginConfirmed = true
                            dismiss()
                        }
                    } message: {
                        Text("Confirm after signing in. Peel cannot verify Instagram login status.")
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
