import SwiftUI

struct PeelMenuView: View {
    @EnvironmentObject private var model: PeelModel
    @State private var importRequest: DocumentImportKind?
    @State private var guideImportRequest: DocumentImportKind?
    @State private var shareFile: URL?
    @State private var showClear = false
    @State private var showExportGuide = false
    @State private var showLogoutConfirmation = false
    @State private var loggingOut = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Your Data") {
                    if model.isDemo {
                        Button { model.importSampleArchive() } label: {
                            Label("Import Sample Archive", systemImage: "doc.zipper")
                        }
                        .disabled(model.operationState.isRunning)
                        .accessibilityIdentifier("importSampleArchive")
                    }
                    Button { showExportGuide = true } label: { Label("Save Progress", systemImage: "square.and.arrow.up") }
                    Button { if model.requireLiveMode() { importRequest = .backup } } label: { Label("Restore Progress", systemImage: "square.and.arrow.down") }
                    Button(role: .destructive) { showClear = true } label: { Label("Reset Lists", systemImage: "trash") }
                    Button(role: .destructive) { if model.requireLiveMode() { showLogoutConfirmation = true } } label: {
                        Label(loggingOut ? LocalizedStringResource("Signing out…") : LocalizedStringResource("Log Out of Instagram"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(loggingOut)
                }
                Section("Information") {
                    NavigationLink { HowPeelWorksView() } label: {
                        Label("How Peel Works", systemImage: "info.circle")
                    }
                    NavigationLink { PeelPrivacyView() } label: {
                        Label("Privacy & Storage", systemImage: "lock.shield")
                    }
                    NavigationLink { PeelLicenseView() } label: {
                        Label("License", systemImage: "doc.text")
                    }
                }
                Section("About") {
                    Label("By Ian Gnk", systemImage: "heart.fill")
                    Link(destination: URL(string: "https://github.com/gnkian/")!) {
                        Label { Text("GitHub") } icon: { Image("GitHubIcon").resizable().scaledToFit().frame(width: 20, height: 20) }
                    }
                    Link(destination: URL(string: "https://www.linkedin.com/in/ioannisgnk")!) {
                        Label { Text("LinkedIn") } icon: { Image("LinkedInIcon").resizable().scaledToFit().frame(width: 20, height: 20) }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(bg.ignoresSafeArea())
            
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showExportGuide) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("Your Peel backup", systemImage: "square.and.arrow.up.circle.fill")
                                .font(.title2.bold())
                                .foregroundStyle(orange)
                            Text("This exports a JSON file containing:")
                                .font(.headline)
                            Label("Imported Following and Followers lists", systemImage: "person.2")
                            Label("Your review progress and queue", systemImage: "checkmark.circle")
                            Label("Excluded accounts", systemImage: "hand.raised")
                            Text("It does not export Instagram passwords, photos, or login information. Keep the file private because it contains usernames.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if let url = model.exportFile() {
                                    showExportGuide = false
                                    shareFile = url
                                }
                            } label: {
                                Label("Export JSON Backup", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(OrangeButton())
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(bg.ignoresSafeArea())
                    .navigationTitle("Save Progress")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showExportGuide = false }
                        }
                    }
                }
                .documentImporter(request: $guideImportRequest, model: model)
                .operationFeedback(model: model, chooseRestore: { guideImportRequest = .backup }, retryExport: {
                    if let url = model.exportFile() { showExportGuide = false; shareFile = url }
                })
                .presentationDetents([.medium, .large])
            }
            .documentImporter(request: $importRequest, model: model)
            .background {
                if let file = shareFile {
                    ActivitySheet(items: [file], beginActivity: { model.beginExportSharing(file) }, onDismiss: {
                        if shareFile == file { shareFile = nil }
                    })
                    .id(file)
                }
            }
            .confirmationDialog("Log out of Instagram?", isPresented: $showLogoutConfirmation) {
                Button("Log Out", role: .destructive) {
                    guard !model.isDemo else { return }
                    loggingOut = true
                    Task {
                        await model.signOut()
                        loggingOut = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears Instagram and related Meta website sessions in Peel. Imported lists and review progress remain saved.")
            }
            .alert("Reset imported lists?", isPresented: $showClear) {
                Button("Reset Lists", role: .destructive) { model.resetLists() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Deletes imported lists, exclusions, and review progress. Your Instagram login stays connected.") }
        }
        .operationFeedback(model: model, enabled: !showExportGuide, chooseRestore: model.isDemo ? nil : { importRequest = .backup })
        .tint(.primary)
    }
}
