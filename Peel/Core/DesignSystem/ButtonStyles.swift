import SwiftUI

struct OrangeButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).padding(13).frame(maxWidth: .infinity)
            .foregroundStyle(isEnabled ? Color.black : Color.white.opacity(0.42))
            .background(isEnabled ? orange : Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 15))
            .opacity(configuration.isPressed && isEnabled ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: configuration.isPressed)
    }
}
struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline).padding(14).background(bg, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
struct CompactOrangeButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.weight(.bold)).foregroundStyle(.black).padding(.horizontal, 11).padding(.vertical, 10)
            .background(orange, in: Capsule()).opacity(configuration.isPressed ? 0.7 : 1)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
struct CompactGrayButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.weight(.semibold)).padding(10)
            .foregroundStyle(isEnabled ? Color.white : Color.gray)
            .background(.white.opacity(isEnabled ? 0.12 : 0.05), in: Capsule())
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
extension AnyLayout {
    /// Change arrangement without replacing the controls or their state.
    init(accessibilityLayout: Bool, spacing: CGFloat = 8) {
        self = accessibilityLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
    }
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View { content.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
}
extension View { func panelStyle() -> some View { modifier(PanelModifier()) } }
