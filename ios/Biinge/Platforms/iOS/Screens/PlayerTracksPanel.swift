import JellyfinAPI
import SwiftUI

/// The iPhone player's Audio & Subtitles panel: audio beside the text subtitles in landscape and above them in portrait, with Subtitle Style below, or the Subtitle Style page
struct PlayerTracksPanel: View {
    let session: PlaybackSession
    let stream: PlaybackStream
    let isLandscape: Bool
    /// The home indicator's height, which the portrait sheet's content clears
    let bottomInset: CGFloat
    @Binding var panel: PlayerPanel?

    @AppStorage(SubtitleSize.key) private var size = SubtitleSize.medium
    @AppStorage(SubtitleBackground.key) private var background = SubtitleBackground.shadow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = isLandscape
            ? UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 22, bottomLeading: 22, bottomTrailing: 22, topTrailing: 22), style: .continuous)
            : UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 28, topTrailing: 28), style: .continuous)
        VStack(spacing: 0) {
            if !isLandscape {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
            // the pages slide 24 pt apart as they cross over Standard, the tracks to the leading side (Reduce Motion crossfades them)
            ZStack(alignment: .top) {
                if panel == .style {
                    PlayerSubtitleStylePage(isOff: (session.subtitleIndex ?? -1) < 0) { panel = .tracks }
                        .transition((reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(x: 24)))
                            .animation(MotionCurve.standard.animation(MotionDuration.standard)))
                } else {
                    tracks
                        .transition((reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .offset(x: -24)))
                            .animation(MotionCurve.standard.animation(MotionDuration.standard)))
                }
            }
        }
        .padding(.bottom, isLandscape ? 0 : bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(rgb: 0x1E1E24).opacity(0.96), in: shape)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.14)))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.55), radius: 30, y: 24)
        // a swipe down on the sheet closes it, as the grabber suggests
        .gesture(DragGesture(minimumDistance: 20).onEnded { drag in
            if !isLandscape, drag.translation.height > 80 { panel = nil }
        })
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { panel = nil }
    }

    /// The header with Close, the audio and subtitle columns, and the Subtitle Style row
    private var tracks: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Audio & Subtitles")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { panel = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MobilePlayerView.text.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close")
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(height: 50)
            ScrollView {
                let layout = isLandscape ? AnyLayout(HStackLayout(alignment: .top, spacing: 6)) : AnyLayout(VStackLayout(spacing: 8))
                layout {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Audio")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MobilePlayerView.text.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(stream.audioStreams, id: \.index) { track in
                            if let index = track.index {
                                PlayerTrackRow(track: track, isSelected: index == stream.audioIndex) {
                                    Task { await session.selectAudio(index) }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Subtitles")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MobilePlayerView.text.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .accessibilityAddTraits(.isHeader)
                        // an index of -1 or none is Off
                        PlayerTrackRow(title: "Off", detail: nil, isSelected: (session.subtitleIndex ?? -1) < 0) {
                            session.selectSubtitle(nil)
                        }
                        ForEach(stream.subtitleStreams, id: \.index) { track in
                            if let index = track.index {
                                PlayerTrackRow(track: track, isSelected: index == session.subtitleIndex, isFailed: session.failedSubtitles.contains(index)) {
                                    session.selectSubtitle(index)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
            Button { panel = .style } label: {
                HStack(spacing: 10) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 18))
                    Text("Subtitle Style")
                        .font(.system(size: 14.5))
                    Spacer()
                    Text("\(size.label) · \(background.label)")
                        .font(.system(size: 14))
                        .foregroundStyle(MobilePlayerView.text.opacity(0.55))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MobilePlayerView.text.opacity(0.45))
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 10, trailing: 10))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        }
    }
}

/// One track in the panel: a checkmark slot, the language, and the rest of Jellyfin's title below it (a track whose file failed says so and can't be picked)
private struct PlayerTrackRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let isFailed: Bool
    let select: () -> Void

    init(track: MediaStream, isSelected: Bool, isFailed: Bool = false, select: @escaping () -> Void) {
        let label = TrackLabel(track)
        self.init(title: label.title, detail: label.detail, isSelected: isSelected, isFailed: isFailed, select: select)
    }

    init(title: String, detail: String?, isSelected: Bool, isFailed: Bool = false, select: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.isFailed = isFailed
        self.select = select
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)
                    .opacity(isSelected ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(MobilePlayerView.text.opacity(isFailed ? 0.45 : 1))
                    if isFailed {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle")
                            Text("Couldn’t load from the server")
                        }
                        .font(.system(size: 12.5))
                            .foregroundStyle(Color(rgb: 0xFF8A8D))
                    } else if let detail {
                        Text(detail)
                            .font(.system(size: 12.5))
                            .foregroundStyle(MobilePlayerView.text.opacity(0.55))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 48)
            .background(.white.opacity(isSelected ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(isFailed)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Subtitle Style page: Back to the tracks and Reset, then size, weight, background, position and timing, each applied at once to every title
private struct PlayerSubtitleStylePage: View {
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
            ZStack {
                Text("Subtitle Style")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Button(action: back) {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 15))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
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
                            .font(.system(size: 15))
                            .foregroundStyle(MobilePlayerView.text.opacity(isDefault ? 0.35 : 1))
                            .padding(.horizontal, 6)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(isDefault)
                }
                .buttonStyle(.pressable)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(height: 50)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    PlayerStyleRow(title: "Size", selection: $size, options: SubtitleSize.allCases) { $0.label }
                    PlayerStyleRow(title: "Weight", selection: $weight, options: SubtitleWeight.allCases) { $0.label }
                    PlayerStyleRow(title: "Background", selection: $background, options: SubtitleBackground.allCases) { $0.label }
                    HStack(spacing: 16) {
                        Text("Position")
                            .font(.system(size: 14.5))
                        Spacer(minLength: 0)
                        Slider(value: $height, in: SubtitleHeight.range) {
                            Text("Position")
                        } minimumValueLabel: {
                            Text("Lower")
                        } maximumValueLabel: {
                            Text("Higher")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(MobilePlayerView.text.opacity(0.5))
                        .tint(MobilePlayerView.text)
                        .frame(maxWidth: 220)
                    }
                    .frame(minHeight: 52)
                    HStack(spacing: 16) {
                        Text("Timing")
                            .font(.system(size: 14.5))
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            Button {
                                offset = max(SubtitleTiming.range.lowerBound, offset - SubtitleTiming.step)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(.white.opacity(0.1), in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .disabled(offset <= SubtitleTiming.range.lowerBound)
                            .accessibilityLabel("Show subtitles earlier")
                            Text(SubtitleTiming.label(offset))
                                .font(.system(size: 14, weight: .medium).monospacedDigit())
                                .frame(minWidth: 104)
                            Button {
                                offset = min(SubtitleTiming.range.upperBound, offset + SubtitleTiming.step)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .background(.white.opacity(0.1), in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .disabled(offset >= SubtitleTiming.range.upperBound)
                            .accessibilityLabel("Show subtitles later")
                        }
                        .buttonStyle(.pressable)
                    }
                    .frame(minHeight: 52)
                    Text(isOff ? "Subtitles are off. The sample line shows your style." : "The style applies to every title.")
                        .font(.system(size: 12.5))
                        .lineSpacing(2)
                        .foregroundStyle(MobilePlayerView.text.opacity(0.5))
                }
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 14, trailing: 16))
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// One labelled row of the style page with its options as pills in a capsule track
private struct PlayerStyleRow<Option: Hashable>: View {
    let title: String
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14.5))
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection
                    Button { selection = option } label: {
                        Text(label(option))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : MobilePlayerView.text.opacity(0.7))
                            .padding(.horizontal, 12)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(.white.opacity(isSelected ? 0.2 : 0), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(.white.opacity(0.08), in: Capsule())
            // the pills keep their labels on one line and the row's title gives way instead
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
        }
        .frame(minHeight: 52)
    }
}

/// The speed menu above the speed pill: each rate with a checkmark on the current one
struct PlayerSpeedMenu: View {
    let rate: Float
    let pick: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Playback Speed")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(MobilePlayerView.text.opacity(0.5))
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 4, trailing: 10))
                .accessibilityAddTraits(.isHeader)
            ForEach(PlayerChrome.speeds, id: \.self) { speed in
                let isSelected = speed == rate
                Button { pick(speed) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 18)
                            .opacity(isSelected ? 1 : 0)
                        Text(speed.formatted(.number.precision(.fractionLength(0...2))) + "×")
                            .font(.system(size: 15.5))
                        Spacer(minLength: 0)
                        if speed == 1 {
                            Text("Normal")
                                .font(.system(size: 13))
                                .foregroundStyle(MobilePlayerView.text.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(.white.opacity(isSelected ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: 196)
        .background(Color(rgb: 0x28282E).opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.5), radius: 25, y: 20)
    }
}
