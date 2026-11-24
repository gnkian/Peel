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
        .operationFeedback(model: model, startupOnly: true)
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
