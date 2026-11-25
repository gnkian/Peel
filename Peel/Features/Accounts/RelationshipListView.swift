import SwiftUI

struct RelationshipListView: View {
    @EnvironmentObject private var model: PeelModel
    let mode: ReviewMode
    var initialSearch: String = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var search = ""
    @State private var filter = AccountListFilter.remaining
    @State private var sort = AccountListSort.original

    private var users: [String] { mode == .mutual ? model.mutualUsers : model.reverseUsers }
    private var heading: LocalizedStringResource {
        mode == .mutual ? "Accounts you follow each other" : "People who follow you, but you don't follow back"
    }
    private var title: LocalizedStringResource { mode == .mutual ? "Mutual" : "Followers" }
    private var reviewedCount: Int { users.filter { model.reviewed(mode).contains($0) }.count }
    private var filteredUsers: [(offset: Int, element: String)] {
        let reviewed = model.reviewed(mode)
        let matches = users.filter { user in
            (search.isEmpty || user.localizedCaseInsensitiveContains(search)) &&
            filter.includes(user, reviewed: reviewed, excluded: model.excluded, mode: mode)
        }
        let ordered = sort.ordered(matches, naturally: true)
        return Array(ordered.enumerated())
    }
    private var hasLists: Bool {
        model.instagramLoginConfirmed && model.queue.mode == "comparison"
    }

    @State private var importRequest: DocumentImportKind?

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hasLists {
                        reviewCard
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(title).font(.title3.bold())
                            Button {} label: {
                                Label("Start Review", systemImage: "person.crop.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(15)
                                    .foregroundStyle(.white)
                                    .background(Color.gray.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .disabled(true)
                            Label("Your accounts will appear here after comparing lists.", systemImage: "person.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 12)
                        }
                        .padding(18)
                        .background(panel, in: RoundedRectangle(cornerRadius: 22))

                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .background(bg.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if !initialSearch.isEmpty { search = initialSearch } }
            .sheet(isPresented: Binding(
                get: { model.instagramUser != nil && model.browserMode == mode },
                set: { if !$0 { model.instagramUser = nil } }
            )) {
                BrowserSheet(model: model)
            }
        .documentImporter(request: $importRequest, model: model)
        .operationFeedback(model: model, enabled: model.instagramUser == nil, chooseRestore: { importRequest = .backup })
        .tint(orange)
    }

    private var reviewCard: some View {
        let rows = filteredUsers
        let lastUsername = rows.last?.element
        let numberColumnCount = model.accountNumberColumnCount
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize) {
                    Text(title).font(.title3.bold())
                    Spacer()
                    Text("\(model.remainingCount(mode)) left")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(heading).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text("\(reviewedCount) of \(users.count) reviewed")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            PeelProgressBar(fraction: users.isEmpty ? 0 :
                Double(reviewedCount) / Double(users.count))
            .accessibilityLabel("Review progress")
            Button { model.startBrowser(mode: mode) } label: {
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text("Start Review")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 17)
                .frame(minHeight: 48)
                .foregroundStyle(!model.canEditLists || !model.instagramLoginConfirmed || users.isEmpty || model.remainingCount(mode) == 0 ? Color.white.opacity(0.42) : Color.black)
                .background(!model.canEditLists || !model.instagramLoginConfirmed || users.isEmpty || model.remainingCount(mode) == 0 ? Color.gray.opacity(0.28) : orange,
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!model.canEditLists || !model.instagramLoginConfirmed || users.isEmpty || model.remainingCount(mode) == 0)
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search usernames", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize) {
                Picker("Remaining", selection: $filter) {
                    ForEach(AccountListFilter.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("accountFilter")
                Picker("Order", selection: $sort) {
                    ForEach(AccountListSort.allCases) { Text($0.title).tag($0) }
                }
            }
            .font(.caption)
            Text("\(rows.count) accounts shown", comment: "Number of accounts matching the current search and filter.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if rows.isEmpty {
                Text(users.isEmpty ? LocalizedStringResource("No accounts in this list.") : LocalizedStringResource("No matching usernames."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.element) { index, user in
                        accountRow(index: index, user: user, numberColumnCount: numberColumnCount)
                        if user != lastUsername {
                            Rectangle().fill(.white.opacity(0.065)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private func accountRow(index: Int, user: String, numberColumnCount: Int) -> some View {
        AccountReviewRow(
            username: user, index: index + 1, numberColumnCount: numberColumnCount, actionTitle: "Open",
            enabled: model.instagramLoginConfirmed, allowsAvatarNetwork: true, excluded: model.excluded.contains(user),
            open: { model.startBrowser(mode: mode, at: user) },
            toggleExclusion: { model.toggleExclude(user) }
        )
        .disabled(!model.canEditLists)
    }
}

/// Keeps identity readable while placing actions below it at accessibility sizes.
struct AccountReviewRow: View {
    let username: String
    var index: Int? = nil
    var numberColumnCount = 1
    var status: LocalizedStringResource? = nil
    let actionTitle: LocalizedStringResource
    let enabled: Bool
    let allowsAvatarNetwork: Bool
    let excluded: Bool
    let open: () -> Void
    let toggleExclusion: () -> Void
    var trim: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize, spacing: 10) {
            HStack(spacing: 10) {
                if let index {
                    // Reserve the same number-column width across all relationship tabs.
                    Text(max(numberColumnCount, index), format: .number)
                        .hidden()
                        .overlay(alignment: .trailing) { Text(index, format: .number) }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                InstagramAvatar(username: username, allowsNetwork: allowsAvatarNetwork)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "@\(username)")
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let status { Text(status).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            HStack(spacing: 8) {
                Button(action: open) { Text(actionTitle) }
                    .disabled(!enabled)
                    .buttonStyle(CompactOrangeButton())
                    .accessibilityLabel(Text("\(Text(actionTitle)) @\(username)"))
                Menu {
                    Button(action: toggleExclusion) {
                        Label(excluded ? LocalizedStringResource("Remove Exclusion") : LocalizedStringResource("Exclude Account"), systemImage: "hand.raised")
                    }
                    if let trim {
                        Button(action: trim) { Label("Start from here", systemImage: "arrow.right.to.line") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Actions for @\(username)")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 3)
    }
}
