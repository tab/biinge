import SwiftUI

/// The details action row's white pill from DetailPrimary, brightening on hover, or dimmed with its tooltip while the server is unreachable
struct PrimaryPill: View {
    let primary: DetailPrimary
    /// The Jellyfin server's name, which the disabled pill's tooltip names
    let server: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        // a pill without a symbol only offers an add, which the Mac shows as an outline bookmark
        let label = HStack(spacing: 6) {
            Image(systemName: primary.systemImage ?? "bookmark")
                .font(.system(size: 20, weight: .medium))
            Text(primary.title)
        }
        .font(.system(size: 17, weight: .semibold))
        .lineLimit(1)
        .padding(.leading, 18)
        .padding(.trailing, 24)
        .frame(height: 48)
        if primary.action == .unreachable {
            // a disabled button, so VoiceOver reads it dimmed; the tooltip sits outside it, where a disabled control still shows one
            Button {} label: {
                label
                    .foregroundStyle(Color.biingeText.opacity(0.38))
                    .background(Color.biingeText.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(true)
            .accessibilityHint("Unavailable until \(server) is back")
            .contentShape(Capsule())
            .help("Unavailable until \(server) is back")
        } else {
            Button(action: action) {
                label
                    .foregroundStyle(Color.biingeBackground)
                    .background(isHovered ? Color.biingeTextFocused : Color.biingeText, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .onHover { isHovered = $0 }
            .animation(MotionCurve.standard.animation(MotionDuration.quick), value: isHovered)
            .help(primary.title)
        }
    }
}

/// The details action row's list split-button: the title's list and pin, else Add to List, which opens the list menu
struct ListButton: View {
    let pill: DetailListPill
    /// Whether the list menu shows under the button
    @Binding var isOpen: Bool

    @State private var isHovered = false

    var body: some View {
        let isListed = pill.systemImage != "plus"
        Button {
            withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 7) {
                // the plus becomes the list's filled symbol on Focus over Standard, which Reduce Motion crossfades
                Image(systemName: pill.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .iconPop(isListed)
                Text(pill.label)
                    .contentTransition(.opacity)
                if pill.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14))
                        .padding(.leading, 2)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.6)
                    .padding(.leading, -2)
            }
            .font(.system(size: 17, weight: .semibold))
            .lineLimit(1)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(height: 48)
            .background(Color.biingeText.opacity(isOpen ? 0.26 : isHovered ? 0.22 : 0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .onHover { isHovered = $0 }
        .animation(MotionCurve.focus.animation(MotionDuration.standard), value: pill)
        .help(isListed ? "Change list, pin or remove" : "Choose a list")
        .anchorPreference(key: ListMenuAnchor.self, value: .bounds) { $0 }
    }
}

/// The list button's bounds, which place the list menu under it
struct ListMenuAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Shows the list menu 8 pt under the list button while `isPresented` holds, closing it on a click elsewhere or Escape
    func macListMenu(isPresented: Binding<Bool>, @ViewBuilder menu: @escaping () -> some View) -> some View {
        overlayPreferenceValue(ListMenuAnchor.self) { anchor in
            GeometryReader { proxy in
                if isPresented.wrappedValue, let anchor {
                    let frame = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { isPresented.wrappedValue = false } }
                        menu()
                            // the menu stays inside the window's trailing edge
                            .offset(x: min(frame.minX, proxy.size.width - 360), y: frame.maxY + 8)
                        Button("Close") { withAnimation(MotionCurve.standard.animation(MotionDuration.quick)) { isPresented.wrappedValue = false } }
                            .keyboardShortcut(.cancelAction)
                            .hidden()
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

/// The glass list menu: the kind's lists with the current one checked, Pin to Up Next for a pinnable list, then Remove from the list
struct ListMenu: View {
    let kind: DetailKind
    /// The list the title is on, nil when it's on none
    let state: WatchState?
    let isPinned: Bool
    /// The Jellyfin server's name, which the descriptions of lists that write to it name
    let server: String
    let pick: (WatchState) -> Void
    let togglePin: () -> Void
    let remove: () -> Void

    var body: some View {
        let lists = DetailList.lists(kind, server: server)
        let current = lists.first { $0.state == state }
        VStack(alignment: .leading, spacing: 0) {
            Text(current == nil ? "Add to List" : "Lists")
                .font(.system(size: 12.5, weight: .semibold))
                .opacity(0.5)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
            ForEach(lists, id: \.state) { list in
                let isCurrent = list.state == state
                // the list's symbol is filled only while the title is on it
                let symbol = isCurrent || !list.systemImage.hasSuffix(".fill") ? list.systemImage : String(list.systemImage.dropLast(5))
                ListMenuRow(systemImage: symbol, label: list.name, summary: list.summary, shortcut: list.state == .watched ? "⇧⌘U" : nil) {
                    pick(list.state)
                } trailing: {
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
            if let current {
                if current.state.isPinnable {
                    Divider().padding(.horizontal, 10).padding(.vertical, 5)
                    ListMenuRow(
                        systemImage: isPinned ? "pin.fill" : "pin",
                        label: "Pin to Up Next", summary: "Keeps it at the top of Up Next and the list.", shortcut: "⌘P", action: togglePin
                    ) {
                        // the switch is drawn, as the whole row is the control
                        Capsule()
                            .fill(isPinned ? Color.biingeText : Color.biingeFill(0.28))
                            .frame(width: 36, height: 22)
                            .overlay(alignment: isPinned ? .trailing : .leading) {
                                Circle()
                                    .fill(isPinned ? Color.biingeBackground : .white)
                                    .frame(width: 18, height: 18)
                                    .padding(2)
                            }
                    }
                    .accessibilityValue(isPinned ? "On" : "Off")
                }
                Divider().padding(.horizontal, 10).padding(.vertical, 5)
                ListMenuRow(systemImage: "minus.circle.fill", label: "Remove from \(current.name)", summary: nil, color: Color.biingeError, action: remove) {
                    EmptyView()
                }
            }
        }
        .padding(6)
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .background(Color.adaptive(light: 0xFFFFFF, dark: 0x28282E, lightOpacity: 0.9, darkOpacity: 0.9), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.biingeFill(0.12), lineWidth: 1))
        // the glass's lit top edge
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.biingeFill(0.16))
                .frame(height: 1)
                .padding(.horizontal, 14)
        }
        .shadow(color: .black.opacity(0.5), radius: 25, y: 18)
        .foregroundStyle(Color.biingeText)
    }

    /// The menu's ⇧⌘U Watched and ⌘P Pin as hidden buttons, which act while the menu is closed (Watched off once there and absent for games, Pin only on a pinnable list)
    var shortcuts: some View {
        ZStack {
            if kind != .game {
                Button("Watched") { pick(.watched) }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(state == .watched)
            }
            if state?.isPinnable == true {
                Button("Pin to Up Next", action: togglePin)
                    .keyboardShortcut("p")
            }
        }
        .hidden()
    }
}

/// One list menu row: the symbol, the label over its description, the key equivalent and the trailing check or switch, lit on hover
private struct ListMenuRow<Trailing: View>: View {
    let systemImage: String
    let label: String
    let summary: String?
    /// The key equivalent's glyphs, right-aligned like a macOS menu's
    var shortcut: String?
    var color: Color = .biingeText
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                    if let summary {
                        Text(summary)
                            .font(.system(size: 12.5))
                            .lineSpacing(1.5)
                            .foregroundStyle(Color.biingeText.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.biingeText.opacity(0.5))
                }
                trailing()
            }
            .foregroundStyle(color)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(isHovered ? Color.biingeFill(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A details note under the action row: the symbol, the sentence and its optional link
struct DesktopDetailNote: View {
    let systemImage: String
    var color: Color = .biingeTextSecondary
    let text: String
    /// The link's label, nil without one
    var link: String?
    var action: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(color)
            Text(text)
                .opacity(0.72)
            if let link {
                Button(link, action: action)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .underline(isHovered)
                    .onHover { isHovered = $0 }
                    .padding(.leading, 4)
            }
        }
        .font(.system(size: 15))
    }
}
