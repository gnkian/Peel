import SwiftUI

struct InstagramExportGuide: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(orange)
                    Text("Select Followers and following in Accounts Center, then request your ZIP in HTML or JSON.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                InstagramExportBrowser()
                AnyLayout(accessibilityLayout: dynamicTypeSize.isAccessibilitySize) {
                    Text("Once your export is ready, download the ZIP and import it in Peel.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Done") { dismiss() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .frame(minWidth: 44, minHeight: 44)
                        .tint(orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("Instagram Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)) } .accessibilityLabel("Close") } }
        }
        .tint(orange)
    }
}
