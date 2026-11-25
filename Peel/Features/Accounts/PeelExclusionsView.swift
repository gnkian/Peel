import SwiftUI

struct PeelExclusionsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var model: PeelModel

    @State private var importRequest: DocumentImportKind?

    var body: some View {
        List {
            if model.excluded.isEmpty {
                ContentUnavailableView(
                    "No Exclusions",
                    systemImage: "hand.raised",
                    description: Text("Accounts you exclude from Mass Unfollow will appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(model.excluded.sorted(), id: \.self) { user in
                        AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize, spacing: 12) {
                            InstagramAvatar(username: user, allowsNetwork: true)
                            Text(verbatim: "@\(user)").fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Include") { model.toggleExclude(user) }
                                .buttonStyle(.bordered)
                                .disabled(!model.canEditLists)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Include @\(user)")
                        }
                    }
                } footer: {
                    Text("Excluded accounts are skipped during Mass Unfollow.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(bg.ignoresSafeArea())
        .navigationTitle("Exclusions")
        .navigationBarTitleDisplayMode(.inline)
        .documentImporter(request: $importRequest, model: model)
        .operationFeedback(model: model, chooseRestore: { importRequest = .backup })
        .tint(orange)
    }
}
