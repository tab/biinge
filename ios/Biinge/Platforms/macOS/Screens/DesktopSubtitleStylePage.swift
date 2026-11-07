import SwiftUI

/// The Mac player's Subtitle Style page in the tracks panel: Back to the tracks and Reset, then size, weight, background, position and timing, each applied at once to every title
struct DesktopSubtitleStylePage: View {
    /// Whether subtitles are off, so a note says the sample line stands in
    let isOff: Bool
    let back: () -> Void

    @AppStorage(SubtitleSize.key) private var size = SubtitleSize.medium
    @AppStorage(SubtitleWeight.key) private var weight = SubtitleWeight.regular
    @AppStorage(SubtitleBackground.key) private var background = SubtitleBackground.shadow
    @AppStorage(SubtitleHeight.key) private var height = SubtitleHeight.standard
    @AppStorage(SubtitleTiming.key) private var offset = 0.0

    private var isDefault: Bool {
        size == .medium && weight == .regular && background == .shadow && height == SubtitleHeight.standard && offset == 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("Subtitle Style")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.leading, 4)
                    .padding(.trailing, 10)
                    .frame(height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(BarHoverStyle(shape: RoundedRectangle(cornerRadius: 9)))
                .accessibilityLabel("Back to tracks")
                Spacer()
                Button {
                    size = .medium
                    weight = .regular
                    background = .shadow
                    height = SubtitleHeight.standard
                    offset = 0
                } label: {
                    Text("Reset")
                        .font(.system(size: 13.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(BarHoverStyle(shape: RoundedRectangle(cornerRadius: 8)))
                .disabled(isDefault)
            }
            .padding(EdgeInsets(top: 2, leading: 0, bottom: 8, trailing: 4))
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
            VStack(spacing: 0) {
                row("Size") {
                    Picker("Size", selection: $size) {
                        ForEach(SubtitleSize.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                row("Weight") {
                    Picker("Weight", selection: $weight) {
                        ForEach(SubtitleWeight.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                row("Background") {
                    Picker("Background", selection: $background) {
                        ForEach(SubtitleBackground.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                row("Position") {
                    Slider(value: $height, in: SubtitleHeight.range) {
                        Text("Position")
                    } minimumValueLabel: {
                        Text("Lower")
                    } maximumValueLabel: {
                        Text("Higher")
                    }
                    .labelsHidden()
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.5))
                    .tint(Color(rgb: 0xF4F4F2))
                    .frame(width: 280)
                }
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Timing")
                            .font(.system(size: 14.5))
                        Text("For subtitles that run early or late")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.45))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        timingButton("minus", label: "Show subtitles earlier") {
                            offset = max(SubtitleTiming.range.lowerBound, offset - SubtitleTiming.step)
                        }
                        .disabled(offset <= SubtitleTiming.range.lowerBound)
                        Text(SubtitleTiming.label(offset))
                            .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                            .frame(minWidth: 104)
                        timingButton("plus", label: "Show subtitles later") {
                            offset = min(SubtitleTiming.range.upperBound, offset + SubtitleTiming.step)
                        }
                        .disabled(offset >= SubtitleTiming.range.upperBound)
                    }
                }
                .frame(minHeight: 56)
            }
            .padding(.horizontal, 10)
            if isOff {
                Text("Subtitles are off. The sample line shows your style.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(rgb: 0xF4F4F2).opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 0, leading: 10, bottom: 4, trailing: 10))
            }
        }
    }

    /// One labelled row of the page with its control trailing and a hairline below
    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 20) {
            Text(title)
                .font(.system(size: 14.5))
            Spacer()
            control()
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }

    private func timingButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 30)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(BarHoverStyle(shape: RoundedRectangle(cornerRadius: 8)))
        .help(label)
        .accessibilityLabel(label)
    }
}
