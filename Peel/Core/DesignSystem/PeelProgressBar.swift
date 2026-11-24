import SwiftUI

// Shared progress rendering: the fill always has rounded ends, even at 1%.
struct PeelProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double
    var height: CGFloat = 12
    var body: some View {
        GeometryReader { geometry in
            let progress = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                if progress > 0 {
                    Capsule().fill(orange.gradient)
                        .frame(width: min(geometry.size.width, max(height, geometry.size.width * progress)))
                }
            }
            .clipShape(Capsule())
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: progress)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(min(1, max(0, fraction)), format: .percent.precision(.fractionLength(0))))
    }
}
