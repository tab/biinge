import SwiftUI

/// Fill drawn past the bottom of the card content, enough to cover the home indicator inset on any device
private let detailCardBottomBleed: CGFloat = 120

extension View {
    /// Rounded-top card backing for the person sheet; bleeds card color through the bottom safe area
    func detailCardBackground() -> some View {
        // The card scrolls, and the enclosing ScrollView has already taken the safe area as a content
        // inset, so ignoresSafeArea has nothing left to expand into. Drawing the fill past its own
        // frame instead reaches the screen edge, and the ScrollView clips whatever overshoots
        background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .fill(Color.biingeCard)
                .padding(.bottom, -detailCardBottomBleed)
        )
    }
}

extension View {
    /// Shows a failed Play's alert over this details sheet, which the shell's alert would sit under (none until the shell provides the connection)
    @ViewBuilder
    func detailPlayFailureAlert(_ connection: JellyfinConnection?) -> some View {
        if let connection {
            playFailureAlert(connection: connection)
        } else {
            self
        }
    }
}

/// Connect Jellyfin over a details sheet, as Profile's Jellyfin sheet shows it, closing once the connection lands
struct DetailConnectSheet: View {
    let connection: JellyfinConnection
    let apiClient: APIClient
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ModalScaffold(title: "Connect Jellyfin") {
            MobileConnectView(connection: connection, apiClient: apiClient)
        }
        .preferredColorScheme(colorScheme)
        .presentationDragIndicator(.hidden)
        // the details underneath turn to Play once connected
        .onChange(of: connection.isConnected) { _, isConnected in
            if isConnected { dismiss() }
        }
    }
}

/// The white pill that leads a details action row: the next step on one line (no icon for an Add to Want; dimmed and inert while the server is unreachable)
struct DetailPrimaryPill: View {
    let title: String
    let systemImage: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    // the prototype's 23 pt Material glyph, at the SF Symbol size that draws as large
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                    // shrinks before it truncates, so a long step beside a pinned list pill still reads whole
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(isDisabled ? Color.biingeText.opacity(0.38) : Color.biingeBackground)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(isDisabled ? Color.biingeFill(0.07) : Color.biingeText, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(isDisabled)
    }
}

/// The action row's list pill: the title's list with its pin, or Add to List, and the chevron of the Lists sheet it opens
struct DetailListButton: View {
    let pill: DetailListPill
    /// Whether it fills the row, as it does without a white pill beside it
    let fills: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: pill.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .iconPop(pill.systemImage != "plus")
                Text(pill.label)
                    .contentTransition(.opacity)
                    .animation(MotionCurve.standard.animation(MotionDuration.standard), value: pill.label)
                if pill.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 13))
                        .rotationEffect(.degrees(25))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.6)
                    .padding(.leading, -2)
            }
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(Color.biingeText)
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: 50)
            .background(Color.biingeFill(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        // beside a white pill it keeps its whole label, and the white pill's label gives way (at accessibility sizes both shrink, so the row stays on screen)
        .fixedSize(horizontal: !fills && !dynamicTypeSize.isAccessibilitySize, vertical: false)
        .accessibilityLabel(pill.isPinned ? "\(pill.label), pinned" : pill.label)
        .accessibilityHint("Shows the lists")
    }
}

/// The iPhone details action row: the white pill of the title's next step, then `secondary` (the list pill, or an episode's Mark pill); the white pill folds away once its step is done, over Quick on Exit (Reduce Motion fades it)
struct DetailActionRow<Secondary: View>: View {
    let primary: DetailPrimary?
    let connection: JellyfinConnection?
    /// Moves the title to the list the white pill names
    var move: (WatchState) -> Void = { _ in }
    @ViewBuilder let secondary: Secondary
    /// Read here, so the details sheet's own failure alert catches the play
    @Environment(\.attemptPlay) private var attemptPlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            if let primary {
                DetailPrimaryPill(title: primary.label, systemImage: primary.systemImage, isDisabled: primary.action == .unreachable) {
                    switch primary.action {
                    case .play(let jellyfinID):
                        // a fresh item, so the play resumes from the position Jellyfin holds now
                        attemptPlay {
                            guard let connection, let service = connection.service else { return }
                            await connection.play(try await service.item(id: jellyfinID))
                        }
                    case .unreachable:
                        break
                    case .move(let target):
                        move(target)
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
            secondary
        }
        .animation(MotionCurve.exit.animation(MotionDuration.quick), value: primary == nil)
    }
}

/// The details More button, a glass circle level with the close button at the top bar's trailing edge
struct DetailMoreButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.biingeText)
                .frame(width: 44, height: 44)
                .background(reduceTransparency ? Color.biingeCard : .clear, in: Circle())
                .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .padding(.trailing, 16)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A details note under the action row, such as "Not on <server>", with an optional inline action after the text
struct DetailNote: View {
    let text: String
    let systemImage: String
    var tint: Color = .biingeTextSecondary
    /// The inline action's label, such as "Connect…"
    var cta: String?
    var action: () -> Void = {}

    var body: some View {
        var line = AttributedString(text)
        if let cta {
            // a link run, so the action wraps with the sentence and takes the tap through openURL below
            var link = AttributedString(cta)
            link.link = URL(string: "biinge-note:action")
            link.font = .footnote.weight(.semibold)
            line += AttributedString(" ") + link
        }
        return Label {
            Text(line)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(.footnote)
        .foregroundStyle(Color.biingeTextSecondary)
        .tint(Color.biingeText)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.openURL, OpenURLAction { _ in
            action()
            return .handled
        })
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let cta { Button(cta, action: action) }
        }
    }
}

/// A played share as a short bar beside its caption (the time left)
struct DetailProgress: View {
    /// The played share, 0 to 1
    let fraction: Double
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(Color.biingeFill(0.22))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(Color.biingeText).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(maxWidth: 180)
                .frame(height: 4)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Color.biingeTextSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A star rating in the rating yellow beside its value
struct RatingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(Color.biingeRating)
            configuration.title.fontWeight(.semibold).foregroundStyle(Color.biingeText)
        }
    }
}

struct ProfileCircle: View {
    let path: String
    var size: CGFloat = 64
    var grayscale: Bool = false

    var body: some View {
        Circle()
            .fill(Color.biingeSecondaryCard)
            .frame(width: size, height: size)
            .overlay {
                CachedImage(url: Config.tmdbImageURL(path: path, size: "w185"), maxPixel: 300, grayscale: grayscale) {
                    Image(systemName: "person.fill").foregroundStyle(Color.biingeGrayDark)
                }
            }
            .clipShape(Circle())
    }
}

struct CreditsRow: View {
    let credits: [CreditPerson]
    @Environment(\.presentPerson) private var presentPerson

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(credits) { person in
                    Button {
                        presentPerson(person.id)
                    } label: {
                        VStack(spacing: 8) {
                            ProfileCircle(path: person.profilePath, size: 72, grayscale: true)
                            VStack(spacing: 1) {
                                Text(person.name)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.biingeText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                Text(person.description)
                                    .font(.caption)
                                    .foregroundStyle(Color.biingeTextSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 80)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.biingeSubhead)
                .foregroundStyle(.primary)
                .padding(.horizontal)
            content
        }
    }
}

/// A details page's loading skeleton in the page's layout: the centred poster (or an episode's wide still), then the kind, title and facts lines and the action row where they land
struct DetailSkeleton: View {
    /// Whether the art is an episode's 16:9 still across the top, with its smaller title and shorter action row
    var isEpisode = false
    /// The parent's hold, which keeps the skeleton 500 ms once it shows
    @Binding var isHeld: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isEpisode ? 14 : 32) {
            if isEpisode {
                SkeletonBlock(cornerRadius: 0)
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else {
                SkeletonBlock(cornerRadius: 14)
                    .frame(width: 216, height: 324)
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 14) {
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 64, height: 14)
                SkeletonBlock(cornerRadius: 8)
                    .frame(width: 240, height: isEpisode ? 28 : 34)
                SkeletonBlock(cornerRadius: 4)
                    .frame(width: 200, height: 14)
                HStack(spacing: 10) {
                    SkeletonBlock(cornerRadius: 25)
                        .frame(height: 50)
                    // an episode's two pills split the row, and a title's list pill sits at its usual width
                    SkeletonBlock(cornerRadius: 25)
                        .frame(maxWidth: isEpisode ? .infinity : 140)
                        .frame(height: 50)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, isEpisode ? 0 : 72)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loadingSkeleton(isHeld: $isHeld)
    }
}
