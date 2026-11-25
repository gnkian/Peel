import SwiftUI

struct UnfollowDetailView: View {
    @EnvironmentObject private var model: PeelModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var importRequest: DocumentImportKind?
    @State private var trimTarget: String?
    @State private var search = ""
    @State private var filter = AccountListFilter.remaining
    @State private var sort = AccountListSort.original
    var visible: [String] {
        let d = model.doneSet
        let filtered = model.queue.users.filter { user in
            (search.isEmpty || user.localizedCaseInsensitiveContains(search)) &&
            filter.includes(user, reviewed: d, excluded: model.excluded)
        }
        return sort.ordered(filtered)
    }
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.instagramLoginConfirmed && model.queue.mode == "comparison" {
                        unfollowReviewPanel
                    } else {
                        unavailableAccounts
                    }
                }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 20)
            }
            .background(bg.ignoresSafeArea())
            .foregroundStyle(.white)
            .navigationTitle("Unfollowers")
            .navigationBarTitleDisplayMode(.inline)
            .documentImporter(request: $importRequest, model: model)
            .sheet(isPresented: Binding(get: { model.instagramUser != nil && model.browserMode == .unfollow }, set: { if !$0 { model.instagramUser = nil } })) {
                BrowserSheet(model: model)
            }
            .alert("Start from here?", isPresented: Binding(get: { trimTarget != nil }, set: { if !$0 { trimTarget = nil } })) {
                Button("Trim Queue", role: .destructive) { if let user = trimTarget { model.start(at: user) }; trimTarget = nil }
                Button("Cancel", role: .cancel) { trimTarget = nil }
            } message: { Text("This removes every account before @\(trimTarget ?? "") from your queue, including their review marks. You cannot undo it without a saved progress file.") }
        .operationFeedback(model: model, enabled: model.instagramUser == nil, chooseFile: { importRequest = .archive },
                           chooseRestore: { importRequest = .backup })
        .tint(orange)
    }
    private var unavailableAccounts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unfollow").font(.title3.bold())
            Button {} label: {
                Label("Mass Unfollow", systemImage: "person.crop.circle.badge.minus")
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

    private var unfollowReviewPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unfollow")
                        .font(.title3.bold())
                    Text("Accounts that don't follow you back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.queue.users.isEmpty {
                    Text("\(model.remaining) left")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize) {
                Text("\(model.queue.done.count) of \(model.queue.users.count) reviewed")
                Spacer()
                Text("\(model.remaining) remaining")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            PeelProgressBar(fraction: model.queue.users.isEmpty ? 0 :
                Double(model.queue.done.count) / Double(model.queue.users.count))
            .accessibilityLabel("Mass Unfollow progress")
            Button { model.startBrowser(mode: .unfollow) } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.minus")
                    Text("Mass Unfollow")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 17)
                .frame(minHeight: 48)
                .foregroundStyle((!model.canEditLists || !model.instagramLoginConfirmed || model.queue.mode != "comparison" || model.remaining == 0) ? Color.white.opacity(0.42) : Color.black)
                .background(
                    (!model.canEditLists || !model.instagramLoginConfirmed || model.queue.mode != "comparison" || model.remaining == 0)
                    ? Color.gray.opacity(0.28) : orange,
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .buttonStyle(.plain)
            .disabled(!model.canEditLists || !model.instagramLoginConfirmed || model.queue.mode != "comparison" || model.remaining == 0)
            if let user = model.queue.lastOpened {
                Text("Last reviewed  @\(user)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !model.queue.users.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 1)
                listPanel
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .foregroundStyle(.secondary)
                    Text("Your accounts will appear here after comparing lists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 18)
            }
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private var listPanel: some View {
        let rows = visible
        let numberColumnCount = model.accountNumberColumnCount
        return VStack(alignment: .leading, spacing: 12) {
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
                Picker("Filter", selection: $filter) { ForEach(AccountListFilter.allCases) { Text($0.title).tag($0) } }
                    .accessibilityIdentifier("accountFilter")
                Picker("Sort", selection: $sort) { ForEach(AccountListSort.allCases) { Text($0.title).tag($0) } }
            }.font(.caption)
            Text("\(rows.count) accounts shown", comment: "Number of accounts matching the current search and filter.").font(.caption).foregroundStyle(.secondary)
            LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, user in
                        AccountReviewRow(
                            username: user, index: index + 1, numberColumnCount: numberColumnCount,
                            status: model.excluded.contains(user) ? "Excluded" : model.doneSet.contains(user) ? "Reviewed" : "Awaiting review",
                            actionTitle: "Unfollow", enabled: model.instagramLoginConfirmed, allowsAvatarNetwork: true,
                            excluded: model.excluded.contains(user),
                            open: { model.openInBrowser(user) },
                            toggleExclusion: { model.toggleExclude(user) },
                            trim: { trimTarget = user }
                        )
                        .disabled(!model.canEditLists)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(.white.opacity(0.065)).frame(height: 1)
                        }
                    }
                }
        }
    }
}
