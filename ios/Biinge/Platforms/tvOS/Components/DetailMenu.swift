import SwiftUI

/// A details menu sheet: the list menu (T27) or More (T28)
enum DetailMenu: Identifiable {
    case list
    case more

    var id: Self { self }
}

/// One row of a details menu sheet
struct MenuRow {
    let label: String
    let systemImage: String
    /// The quieter line under the label
    var summary: String?
    /// The symbol's turn in degrees (the pin leans 25°)
    var rotation: Double = 0
    /// Ends the row with a check (the title's list)
    var isChecked = false
    /// The trailing state ("On" or "Off" for the pin)
    var value: String?
    var isDestructive = false
    /// Acts with the sheet open (the pin), where any other row closes the sheet and acts once it's gone
    var keepsOpen = false
    let action: @MainActor () -> Void
}

extension MenuRow {
    /// The list menu's rows: the kind's lists with the title's list filled and checked, then Pin to Up Next for a pinnable list and Remove from the list (picking the title's own list only closes)
    static func lists(
        _ kind: DetailKind, server: String, state: WatchState?, isPinned: Bool,
        move: @escaping @MainActor (WatchState) -> Void, pin: @escaping @MainActor (Bool) -> Void, remove: @escaping @MainActor () -> Void
    ) -> [MenuRow] {
        let lists = DetailList.lists(kind, server: server)
        var rows = lists.map { list in
            let isCurrent = list.state == state
            // the other lists show their symbols outlined
            let symbol = isCurrent ? list.systemImage : list.systemImage.replacingOccurrences(of: ".fill", with: "")
            return MenuRow(label: list.name, systemImage: symbol, summary: list.summary, isChecked: isCurrent) {
                if !isCurrent { move(list.state) }
            }
        }
        guard let current = lists.first(where: { $0.state == state }) else { return rows }
        if current.state.isPinnable {
            rows.append(MenuRow(
                label: "Pin to Up Next", systemImage: isPinned ? "pin.fill" : "pin", summary: "Keeps it at the top of Up Next and the list.",
                rotation: 25, value: isPinned ? "On" : "Off", keepsOpen: true
            ) { pin(!isPinned) })
        }
        rows.append(MenuRow(label: "Remove from \(current.name)", systemImage: "minus.circle.fill", isDestructive: true, action: remove))
        return rows
    }
}

extension View {
    /// Presents the details menu full screen over the blurred screen, building its rows as it draws (so the pin's row follows a toggle) and showing the screen's toasts over it
    func tvDetailMenu(
        _ menu: Binding<DetailMenu?>, poster: URL?, title: String, toast: Binding<Toast?>, rows: @escaping (DetailMenu) -> [MenuRow]
    ) -> some View {
        modifier(DetailMenuPresenter(menu: menu, poster: poster, title: title, toast: toast, rows: rows))
    }
}

/// Presents the menu sheet and runs a closing row's action once the sheet has gone, so the change lands on the details in view
private struct DetailMenuPresenter: ViewModifier {
    @Binding var menu: DetailMenu?
    let poster: URL?
    let title: String
    @Binding var toast: Toast?
    let rows: (DetailMenu) -> [MenuRow]

    /// The closing row's action, held until the sheet is gone
    @State private var chosen: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $menu, onDismiss: {
                chosen?()
                chosen = nil
            }, content: { shown in
                TVDetailMenuSheet(menu: shown, poster: poster, title: title, rows: rows(shown)) { row in
                    guard !row.keepsOpen else {
                        row.action()
                        return
                    }
                    chosen = row.action
                    menu = nil
                }
                .toast($toast)
            })
    }
}

/// The menu sheet over the blurred, dimmed screen: the poster cropped wide, then the eyebrow, title, Back's note on the list menu and the rows, with focus starting on the first row
private struct TVDetailMenuSheet: View {
    let menu: DetailMenu
    let poster: URL?
    let title: String
    let rows: [MenuRow]
    let choose: (MenuRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Int?

    var body: some View {
        HStack(spacing: 80) {
            // the poster fills the wide frame from 30% of the way down, as the board crops it
            PosterImage(title: title, cornerRadius: 0, poster: poster, frame: CGSize(width: 640, height: 960), titleFont: .system(size: 26), titlePadding: 20)
                .offset(y: -180)
                .frame(width: 640, height: 360, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.biingeText.opacity(0.12), lineWidth: 1))
                .shadow(color: Color.biingeShadow.opacity(0.6), radius: 45, y: 40)
            VStack(alignment: .leading, spacing: 16) {
                Text(menu == .more ? "More" : rows.contains(where: \.isChecked) ? "Lists" : "Add to List")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Color.biingeText.opacity(0.65))
                Text(title)
                    .font(.system(size: 56, weight: .bold))
                    .tracking(-1.68)
                    .padding(.bottom, menu == .list ? 0 : 18)
                if menu == .list {
                    Text("Back closes without changes.")
                        .font(.system(size: 27))
                        .foregroundStyle(Color.biingeText.opacity(0.7))
                        .padding(.bottom, 18)
                }
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    Button { choose(row) } label: {
                        Label {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.label)
                                    if let summary = row.summary {
                                        Text(summary)
                                            .font(.system(size: 21))
                                            .opacity(0.62)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if row.isChecked {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 28, weight: .semibold))
                                        .accessibilityLabel("Current list")
                                }
                                if let value = row.value {
                                    Text(value)
                                        .font(.system(size: 26, weight: .semibold))
                                        .opacity(0.7)
                                }
                            }
                        } icon: {
                            Image(systemName: row.systemImage)
                                .rotationEffect(.degrees(row.rotation))
                        }
                    }
                    .buttonStyle(SheetButtonStyle(isDestructive: row.isDestructive))
                    .focused($focus, equals: index)
                }
            }
            .frame(width: 620, alignment: .leading)
        }
        .foregroundStyle(Color.biingeText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focus, 0)
        .presentationBackground {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.biingeScrim.opacity(0.55))
                .ignoresSafeArea()
        }
        .onExitCommand { dismiss() }
    }
}

/// The list pill's label: the title's list and symbol, else Add to List holding the width of the kind's first list, so the pill keeps its size as an add lands while the symbol and label crossfade (Reduce Motion drops the symbol's scale)
struct ListPillLabel: View {
    let kind: DetailKind
    let pill: DetailListPill
    /// Whether the title sits in no list
    let isUnlisted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label {
            ZStack(alignment: .leading) {
                if isUnlisted, let first = DetailList.lists(kind, server: "").first {
                    Text(first.name).hidden()
                }
                Text(pill.label)
                    .id(pill.label)
                    .transition(.opacity)
            }
        } icon: {
            Image(systemName: pill.systemImage)
                .id(pill.systemImage)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.5)))
        }
        .animation(MotionCurve.focus.animation(MotionDuration.standard), value: pill.label)
    }
}
