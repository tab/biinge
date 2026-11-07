import SwiftUI

/// A row of capsule pills over a faint track, one per case, the selected one filled (the Mac library filters' look), whose fill slides to a new choice over Standard as `forward` tells the content which way to shift (Reduce Motion crossfades the fill)
struct PillFilter<Option>: View where Option: CaseIterable & Hashable & RawRepresentable<String>, Option.AllCases: RandomAccessCollection {
    @Binding var selection: Option
    /// Set on each choice to whether it lies after the one before, for a content's 20 pt shift (nil for content that cuts)
    var forward: Binding<Bool>?
    /// Pill label (the raw value unless a caller names its cases)
    var title: (Option) -> String = { $0.rawValue }

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Option.allCases, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    let cases = Option.allCases
                    if let new = cases.firstIndex(of: option), let old = cases.firstIndex(of: selection) { forward?.wrappedValue = new > old }
                    // the fill slides in this transaction, which the screens read for their content, and Reduce Motion keeps it for the crossfade
                    withAnimation(MotionCurve.standard.animation(MotionDuration.standard)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isSelected ? Color.biingeText : Color.biingeTextSecondary)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.biingeFill(0.14))
                                    // one shared fill slides between the pills, while a fill of each pill's own crossfades
                                    .matchedGeometryEffect(id: reduceMotion ? AnyHashable(option) : AnyHashable("selection"), in: pill)
                            }
                        }
                        // the track's inset counts toward each pill, so every touch target is at least 44 pt tall
                        .padding(.vertical, 3)
                        .padding(.horizontal, 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 2)
        .background(Color.biingeFill(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.biingeFill(0.06), lineWidth: 1))
    }
}
