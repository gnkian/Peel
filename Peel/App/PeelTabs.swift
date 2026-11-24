import SwiftUI

private enum PeelTab: Int, CaseIterable, Identifiable {
    case review, unfollowers, followers, mutual, menu
    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .review: return "Review"
        case .unfollowers: return "Unfollowers"
        case .followers: return "Followers"
        case .mutual: return "Mutual"
        case .menu: return "Menu"
        }
    }

    var symbol: String {
        switch self {
        case .review: return "square.grid.2x2"
        case .unfollowers: return "person.crop.circle.badge.minus"
        case .followers: return "person.2"
        case .mutual: return "person.2.fill"
        case .menu: return "ellipsis"
        }
    }
}

struct PeelTabs: View {
    @StateObject private var model = PeelTabs.makeModel()

    /// UI failure tests use a disposable domain; Release builds always use live storage.
    private static func makeModel() -> PeelModel {
        #if PEEL_Debug
        let environment = ProcessInfo.processInfo.environment
        if let domain = environment["PEEL_UI_TEST_STORAGE_DOMAIN"],
           domain.hasPrefix("PeelUITests."),
           let defaults = UserDefaults(suiteName: domain) {
            if environment["PEEL_UI_TEST_CORRUPT_STORE"] == "1" {
                defaults.set(Data("{broken".utf8), forKey: DefaultsProgressStore.queueKey)
            }
            return PeelModel(defaults: defaults)
        }
        #endif
        return PeelModel()
    }

    @StateObject private var demoModel = PeelModel(demo: true)
    @StateObject private var demoMode = PeelDemoMode()
    @State private var sampleTransferFailed = false
    @State private var importRequest: DocumentImportKind?
    @State private var selection: PeelTab = .review
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if model.isRestoring {
                VStack(spacing: 14) {
                    ProgressView().tint(orange)
                    Text("Restoring your lists…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(bg.ignoresSafeArea())
            } else if horizontalSizeClass == .regular {
                tabletNavigation
            } else {
                phoneNavigation
            }
        }
        .environmentObject(demoMode.isEnabled ? demoModel : model)
        .environmentObject(demoMode)
        .id(demoMode.isEnabled ? "demo" : "live")
        .documentImporter(request: $importRequest, model: model)
        .operationFeedback(model: model, startupOnly: true, chooseRestore: { importRequest = .backup })
        .alert("Demo Mode", isPresented: Binding(
            get: { demoModel.demoRestrictionRequested },
            set: { presented in
                // UIKit may dismiss during a SwiftUI update; publish on the next actor turn.
                Task { @MainActor in demoModel.demoRestrictionRequested = presented }
            }
        )) {
            Button("Exit Demo Mode") {
                DispatchQueue.main.async { demoMode.exitRequested = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To use this functionality, please exit Demo Mode first.")
        }
        .alert("Exit Demo Mode?", isPresented: Binding(
            get: { demoMode.exitRequested },
            set: { presented in
                Task { @MainActor in demoMode.exitRequested = presented }
            }
        )) {
            if demoModel.hasImportedSample && model.canReceiveSampleLists && demoModel.canEditLists && demoModel.failure == nil {
                Button("Keep Sample Lists") {
                    DispatchQueue.main.async {
                        do {
                            try model.retainSampleLists(from: demoModel)
                            demoMode.exit()
                        } catch {
                            sampleTransferFailed = true
                        }
                    }
                }
            }
            Button("Exit Without Sample Lists") {
                DispatchQueue.main.async {
                    demoModel.cancelOperation()
                    demoMode.exit()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if demoModel.hasImportedSample && !model.canReceiveSampleLists {
                Text("Your personal lists and review progress will remain unchanged. To keep sample lists, first exit Demo Mode, save a backup and reset your lists, then import the sample again in Demo Mode.")
            } else if demoModel.hasImportedSample {
                Text("Keep the imported sample lists and their review progress in your normal workspace? Live profile browsing requires internet access and your own login confirmation. Sample relationships are fictional.")
            } else {
                Text("Your personal lists and review progress will remain unchanged. Import the sample archive in Demo Mode to keep its lists when exiting.")
            }
        }
        .alert("Could Not Keep Sample Lists", isPresented: $sampleTransferFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your saved data and Demo Mode lists remain unchanged. Please try again after checking your available storage.")
        }
        .tint(orange)
    }

    @ViewBuilder
    private func screen(for tab: PeelTab) -> some View {
        switch tab {
        case .review: ContentView()
        case .unfollowers: NavigationStack { UnfollowDetailView() }
        case .followers: NavigationStack { RelationshipListView(mode: .followers) }
        case .mutual: NavigationStack { RelationshipListView(mode: .mutual) }
        case .menu: PeelMenuView()
        }
    }

    // Preserve the established iPhone tab bar and screen layouts.
    private var phoneNavigation: some View {
        TabView(selection: $selection) {
            ForEach(PeelTab.allCases) { tab in
                screen(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .background(bg.ignoresSafeArea())
    }

    // A native iPad sidebar. Narrow iPad windows automatically use phone navigation.
    private var tabletNavigation: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(PeelTab.allCases) { tab in
                        Button {
                            selection = tab
                        } label: {
                            Label(tab.title, systemImage: tab.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .foregroundStyle(selection == tab ? orange : .white)
                                .background(selection == tab ? orange.opacity(0.15) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    }
                }
                .padding(12)
            }
            .navigationTitle("Peel")
            .scrollContentBackground(.hidden)
            .background(bg)
            .navigationSplitViewColumnWidth(
                min: dynamicTypeSize.isAccessibilitySize ? 320 : 200,
                ideal: dynamicTypeSize.isAccessibilitySize ? 440 : 235,
                max: dynamicTypeSize.isAccessibilitySize ? 500 : 280
            )
        } detail: {
            screen(for: selection)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(bg.ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
    }
}
