import SwiftUI
import UniformTypeIdentifiers

// Review is the single entry point. Existing review screens remain separate.
struct ContentView: View {
    @EnvironmentObject private var model: PeelModel
    @EnvironmentObject private var demoMode: PeelDemoMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34
    @ScaledMetric(relativeTo: .title) private var countSize = 30
    @State private var showingLogin = false
    @State private var showingZIPPicker = false
    @State private var showingExportGuide = false

    private var ready: Bool { model.instagramLoginConfirmed && model.queue.mode == "comparison" }
    private var remaining: Int { model.remaining }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image("PeelLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .onLongPressGesture(minimumDuration: 10) { demoMode.toggle() }
                            .accessibilityLabel("Peel demo mode")
                            .accessibilityHint("Press and hold for 10 seconds, or use the Toggle Demo Mode accessibility action")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { demoMode.toggle() }
                            .accessibilityAction(named: Text("Toggle Demo Mode")) { demoMode.toggle() }
                            .accessibilityIdentifier("demoLogo")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peel")
                                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                            Text("Your Instagram review space")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 12)

                    if demoMode.isEnabled {
                        HStack {
                            Label("DEMO MODE · Fictional data", systemImage: "eye")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Exit Demo") { demoMode.toggle() }
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(orange)
                        .padding(12)
                        .background(orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if !model.instagramLoginConfirmed {
                        Button { showingLogin = true } label: {
                            Label("Login to Instagram", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OrangeButton())
                    }

                    LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        Button { showingExportGuide = true } label: {
                            instagramActionTile("Get your Lists", subtitle: "Open Instagram’s Export page", icon: "arrow.down.doc")
                        }
                        .disabled(!model.instagramLoginConfirmed || model.isDemo)
                        Button { showingZIPPicker = true } label: {
                            instagramActionTile("Import Lists", subtitle: "Exported ZIP File", icon: "doc.zipper")
                        }
                        .accessibilityIdentifier("importLists")
                        .disabled(!model.instagramLoginConfirmed || model.isDemo)
                    }
                    .buttonStyle(.plain)

                    reviewProgressCard

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Your review").font(.title3.bold())
                            Spacer()
                            if ready {
                                Text("\(remaining) remaining")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            reviewTile("Unfollowers", count: model.remaining, symbol: "person.crop.circle.badge.minus") {
                                UnfollowDetailView()
                            }
                            reviewTile("Followers", count: model.remainingCount(.followers), symbol: "person.2") {
                                RelationshipListView(mode: .followers)
                            }
                            reviewTile("Mutual", count: model.remainingCount(.mutual), symbol: "person.2.fill") {
                                RelationshipListView(mode: .mutual)
                            }
                            reviewTile("Exclusions", count: model.excluded.count, symbol: "hand.raised") {
                                PeelExclusionsView()
                            }
                        }

                    }
                    .padding(18)
                    .background(panel, in: RoundedRectangle(cornerRadius: 22))

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .accessibilityIdentifier("dashboardScroll")
            .background(bg.ignoresSafeArea())
            .foregroundStyle(.white)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLogin) {
                InstagramLoginGuide().environmentObject(model)
            }
            .sheet(isPresented: $showingExportGuide) {
                InstagramExportGuide()
            }
            .fileImporter(isPresented: $showingZIPPicker, allowedContentTypes: [UTType(filenameExtension: "zip") ?? .archive]) { result in
                switch result {
                case .success(let url): model.importZIP(url)
                case .failure(let error): model.report(error, operation: .chooseZIP)
                }
            }
        }
        .operationFeedback(model: model, chooseFile: { showingZIPPicker = true })
        .tint(orange)
    }

    private func instagramActionTile(_ title: LocalizedStringResource, subtitle: LocalizedStringResource, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(orange)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 106)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .opacity(model.instagramLoginConfirmed ? 1 : 0.45)
    }

    private var reviewProgressCard: some View {
        let fraction = model.queue.users.isEmpty ? 0.0 :
            min(1.0, Double(model.queue.done.count) / Double(model.queue.users.count))
        return VStack(alignment: .leading, spacing: 12) {
            AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize) {
                Text("Progress").font(.headline)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))% completed")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(orange)
            }
            PeelProgressBar(fraction: fraction, height: 16)
            .accessibilityLabel("Review progress")
            .accessibilityIdentifier("reviewProgress")
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private func reviewTile<Destination: View>(
        _ title: LocalizedStringResource,
        count: Int,
        symbol: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(orange)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(count, format: .number)
                    .font(.system(size: countSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 118)
            .padding(15)
            .background(bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 17))
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
    }
}
