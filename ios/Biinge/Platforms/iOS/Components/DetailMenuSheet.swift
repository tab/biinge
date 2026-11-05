import SwiftUI

/// The details bottom sheet for Lists and More: a grabber, the sheet's title over the title's name and a close button, then its rows, sized to fit them
struct DetailMenuSheet<Content: View>: View {
    let title: String
    /// The title's name under the sheet's title
    let subtitle: String
    @ViewBuilder let content: Content
    /// The rows' height, which the sheet's one detent takes
    @State private var height: CGFloat = 320
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // the rows scroll once they outgrow the screen, as they can at accessibility text sizes
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        // the prototype's 20 pt sheet title, between the title scale's steps
                        Text(title)
                            .font(.custom("Archivo-SemiBold", size: 20, relativeTo: .title3))
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.biingeText.opacity(0.5))
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Color.biingeFill(0.1), in: Circle())
                            // the 30 pt circle inside a 44 pt target
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .padding(.trailing, -7)
                }
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.bottom, 4)
                content
            }
            .padding(.horizontal, 8)
            // clear of the system grabber
            .padding(.top, 22)
            .padding(.bottom, 8)
            .foregroundStyle(Color.biingeText)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // the system holds a taller detent to the screen's height
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.biingeCard)
        // a sheet presented from a details sheet keeps its appearance
        .preferredColorScheme(colorScheme)
    }
}

/// One sheet row's icon and label over its optional description (the trailing check or switch sits beside it)
struct DetailMenuLabel: View {
    let systemImage: String
    let title: String
    var summary: String?
    var tint: Color = .biingeText
    /// The icon's turn in degrees (the pin leans 25°)
    var rotation: Double = 0

    var body: some View {
        HStack(spacing: 14) {
            // the prototype's 24 pt Material glyph, at the SF Symbol size that draws as large
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .rotationEffect(.degrees(rotation))
                .frame(width: 24)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tint)
                if let summary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Color.biingeText.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A sheet row that acts on a tap, with a check on the current choice
struct DetailMenuButton: View {
    let systemImage: String
    let title: String
    var summary: String?
    var tint: Color = .biingeText
    var isChecked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DetailMenuLabel(systemImage: systemImage, title: title, summary: summary, tint: tint)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        // the row's selected trait says it
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// The hairline between a sheet's groups of rows
struct DetailMenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.biingeFill(0.08))
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }
}

/// The Lists sheet a details list pill opens: the kind's lists with a check on the title's, Pin to Up Next in a list that pins, and Remove (each row hands its choice back and leaves closing to the caller)
struct DetailListsSheet: View {
    let kind: DetailKind
    /// The title's name under the sheet's title
    let title: String
    /// The Jellyfin server the list descriptions name
    let server: String
    let state: WatchState?
    let isPinned: Bool
    let select: (WatchState) -> Void
    let pin: (Bool) -> Void
    let remove: () -> Void

    var body: some View {
        let lists = DetailList.lists(kind, server: server)
        let current = lists.first { $0.state == state }
        DetailMenuSheet(title: current == nil ? "Add to List" : "Lists", subtitle: title) {
            ForEach(lists, id: \.state) { list in
                let isCurrent = list.state == state
                // the current list's icon is filled, the others' outlined
                DetailMenuButton(
                    systemImage: isCurrent ? list.systemImage : list.systemImage.replacingOccurrences(of: ".fill", with: ""),
                    title: list.name,
                    summary: list.summary,
                    isChecked: isCurrent
                ) { select(list.state) }
            }
            if let current {
                if current.state.isPinnable {
                    DetailMenuSeparator()
                    Toggle(isOn: Binding(get: { isPinned }, set: { pin($0) })) {
                        DetailMenuLabel(
                            systemImage: isPinned ? "pin.fill" : "pin",
                            title: "Pin to Up Next",
                            summary: "Keeps it at the top of Up Next and the list.",
                            rotation: 25
                        )
                    }
                    .toggleStyle(SwitchStyle())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 56)
                }
                DetailMenuSeparator()
                DetailMenuButton(systemImage: "minus.circle", title: "Remove from \(current.name)", tint: .biingeError, action: remove)
            }
        }
    }
}

/// The More sheet's Start Over row, which plays the Jellyfin item from 0:00 (it reads attemptPlay itself, so the details sheet's own failure alert catches the play)
struct DetailStartOverRow: View {
    let title: String
    let connection: JellyfinConnection
    let jellyfinID: String
    /// Closes the sheet as the play starts
    let close: () -> Void
    @Environment(\.attemptPlay) private var attemptPlay

    var body: some View {
        DetailMenuButton(systemImage: "arrow.counterclockwise", title: title, summary: "From 0:00") {
            close()
            attemptPlay {
                guard let service = connection.service else { return }
                await connection.play(try await service.item(id: jellyfinID), fromStart: true)
            }
        }
    }
}
