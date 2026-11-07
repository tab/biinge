import SwiftUI

/// The Apple TV player's Subtitle Style page in the tracks panel: Back and Reset, the size, weight and background options, then position and timing values a swipe steps, each applied at once to every title
struct TVSubtitleStylePage: View {
    let back: () -> Void

    @AppStorage(SubtitleSize.key) private var size = SubtitleSize.medium
    @AppStorage(SubtitleWeight.key) private var weight = SubtitleWeight.regular
    @AppStorage(SubtitleBackground.key) private var background = SubtitleBackground.shadow
    @AppStorage(SubtitleHeight.key) private var height = SubtitleHeight.standard
    @AppStorage(SubtitleTiming.key) private var offset = 0.0
    /// The page opens on the current size
    @FocusState private var focus: SubtitleSize?

    /// The heights a swipe steps through, from the standard height up (the Mac slider reaches lower)
    private static let positions = [SubtitleHeight.standard, 0.13, 0.18, 0.24, SubtitleHeight.range.upperBound]
    private static let positionLabels = ["Lowest", "Low", "Middle", "High", "Highest"]

    private var isDefault: Bool {
        size == .medium && weight == .regular && background == .shadow && height == SubtitleHeight.standard && offset == 0
    }

    /// The step nearest the stored height
    private var position: Int {
        Self.positions.indices.min { abs(Self.positions[$0] - height) < abs(Self.positions[$1] - height) } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                option("Audio & Subtitles", systemImage: "chevron.left", action: back)
                Spacer()
                option("Reset") {
                    size = .medium
                    weight = .regular
                    background = .shadow
                    height = SubtitleHeight.standard
                    offset = 0
                }
                .disabled(isDefault)
            }
            .overlay {
                Text("Subtitle Style")
                    .font(.system(size: 36, weight: .semibold))
                    .tracking(-0.7)
            }
            .padding(EdgeInsets(top: 36, leading: 44, bottom: 12, trailing: 44))
            VStack(spacing: 6) {
                row("Size") {
                    ForEach(SubtitleSize.allCases, id: \.self) { value in
                        option(value.label, isSelected: value == size) { size = value }
                            .focused($focus, equals: value)
                    }
                }
                row("Weight") {
                    ForEach(SubtitleWeight.allCases, id: \.self) { value in
                        option(value.label, isSelected: value == weight) { weight = value }
                    }
                }
                row("Background") {
                    ForEach(SubtitleBackground.allCases, id: \.self) { value in
                        option(value.label, isSelected: value == background) { background = value }
                    }
                }
                row("Position") {
                    // Select steps up and wraps, a swipe left or right steps down or up
                    option("‹  \(Self.positionLabels[position])  ›") {
                        height = Self.positions[(position + 1) % Self.positions.count]
                    }
                    .onMoveCommand { direction in
                        if direction == .left { height = Self.positions[max(0, position - 1)] }
                        if direction == .right { height = Self.positions[min(Self.positions.count - 1, position + 1)] }
                    }
                    .accessibilityLabel("Position")
                    .accessibilityValue(Self.positionLabels[position])
                }
                row("Timing") {
                    // Select steps later and wraps, a swipe left or right moves the lines earlier or later
                    option("‹  \(SubtitleTiming.label(offset))  ›") {
                        offset = offset >= SubtitleTiming.range.upperBound ? SubtitleTiming.range.lowerBound : offset + SubtitleTiming.step
                    }
                    .onMoveCommand { direction in
                        if direction == .left { offset = max(SubtitleTiming.range.lowerBound, offset - SubtitleTiming.step) }
                        if direction == .right { offset = min(SubtitleTiming.range.upperBound, offset + SubtitleTiming.step) }
                    }
                    .accessibilityLabel("Timing")
                    .accessibilityValue(SubtitleTiming.label(offset))
                }
            }
            .padding(EdgeInsets(top: 8, leading: 44, bottom: 0, trailing: 44))
            Spacer(minLength: 0)
            Text("The style applies to every title. Swipe left or right to change a value.")
                .font(.system(size: 21))
                .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 12, leading: 66, bottom: 26, trailing: 66))
        }
        .defaultFocus($focus, size)
    }

    /// One labelled row of the page with its options trailing
    private func row(_ title: String, @ViewBuilder options: () -> some View) -> some View {
        HStack(spacing: 30) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
            Spacer()
            HStack(spacing: 8) {
                options()
            }
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 84)
        .focusSection()
    }

    /// A capsule option, resting on a fill while it is the current pick
    private func option(_ title: String, systemImage: String? = nil, isSelected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 24, weight: .semibold))
            .padding(.horizontal, 26)
            .frame(minWidth: 72, minHeight: 60)
        }
        .buttonStyle(PanelButtonStyle(cornerRadius: 30, isSelected: isSelected))
    }
}
