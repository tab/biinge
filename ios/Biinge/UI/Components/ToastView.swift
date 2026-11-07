import SwiftUI

#if os(tvOS)
/// The toast capsule's height and side inset, sized for the room
private let toastHeight: CGFloat = 72
private let toastInset: CGFloat = 30
#else
private let toastHeight: CGFloat = 38
private let toastInset: CGFloat = 16
#endif

/// Shows the toast at the bottom of the view (the top on Apple TV, clear of the focused buttons), entering over Standard, leaving on Exit over Quick and closing after 2 seconds, or the Undo window with Undo (Reduce Motion only fades it)
private struct ToastPresenter: ViewModifier {
    @Binding var toast: Toast?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(tvOS)
        let edge = Alignment.top, rise: CGFloat = -16
        #else
        let edge = Alignment.bottom, rise: CGFloat = 16
        #endif
        let move: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: rise))
        // reading the store here tracks it, so a removal that commits early (a later write on the title) closes its toast at once
        let undoable = toast?.undo != nil && toast?.canUndo?() == true
        content
            .overlay(alignment: edge) {
                // the stack keeps a replaced toast and its replacement in one place while they cross
                ZStack {
                    if let toast {
                        ToastLabel(toast: toast, undoable: undoable) {
                            toast.undo?()
                            withAnimation(MotionCurve.exit.animation(MotionDuration.quick)) { self.toast = nil }
                        }
                            .id(toast.id)
                            .transition(.asymmetric(
                                insertion: move.animation(MotionCurve.standard.animation(MotionDuration.standard)),
                                removal: move.animation(MotionCurve.exit.animation(MotionDuration.quick))
                            ))
                    }
                }
                .padding(toastInset)
                .animation(MotionCurve.standard.animation(MotionDuration.standard), value: toast?.id)
                // a toast without Undo only confirms, so taps, clicks and focus pass through to the page
                .allowsHitTesting(undoable)
            }
            // the store ended the removal's window, so Undo would do nothing
            .onChange(of: undoable) { _, isUndoable in
                guard !isUndoable, toast?.undo != nil else { return }
                withAnimation(MotionCurve.exit.animation(MotionDuration.quick)) { toast = nil }
            }
            .task(id: toast?.id) {
                guard let shown = toast else { return }
                AccessibilityNotification.Announcement(shown.sub.map { "\(shown.message). \($0)" } ?? shown.message).post()
                guard (try? await Task.sleep(for: shown.undo == nil ? .seconds(2) : Toast.undoWindow)) != nil else {
                    // leaving the screen ends this toast, so coming back doesn't show and announce it again
                    if toast?.id == shown.id { toast = nil }
                    return
                }
                withAnimation(MotionCurve.exit.animation(MotionDuration.quick)) { toast = nil }
            }
    }
}

/// The toast's capsule: the green symbol, then the message over its quieter second line, then the Undo pill for a removal
private struct ToastLabel: View {
    let toast: Toast
    /// Whether the Undo pill shows
    let undoable: Bool
    /// Runs the toast's Undo and closes it
    let undo: () -> Void

    var body: some View {
        HStack(spacing: toastInset / 2) {
            if let systemImage = toast.systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.biingeWatched)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.message)
                    .lineLimit(1)
                if let sub = toast.sub {
                    Text(sub)
                        .fontWeight(.regular)
                        .opacity(0.55)
                        .lineLimit(1)
                }
            }
            // the presenter announces the message and its second line
            .accessibilityHidden(true)
            if undoable {
                Button(action: undo) {
                    Text("Undo")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .frame(minHeight: toastHeight - 12)
                        .background(Color.biingeFill(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(toast.message)
            }
        }
        #if os(macOS)
        .font(.body.weight(.medium))
        #else
        .font(.subheadline.weight(.medium))
        #endif
        .foregroundStyle(Color.biingeText)
        .padding(.leading, toast.systemImage == nil ? toastInset : toastInset * 0.75)
        // the Undo pill sits 6 pt inside the capsule's end, as the board draws it
        .padding(.trailing, undoable ? 6 : toastInset)
        // two lines outgrow the one-line capsule, so they keep a margin above and below
        .padding(.vertical, toast.sub == nil ? 0 : toastInset / 3)
        .frame(minHeight: toastHeight)
        .background(Color.biingeCard.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.biingeFill(0.12), lineWidth: 1))
        .shadow(color: Color.biingeShadow.opacity(0.5), radius: 15, y: 10)
    }
}

extension View {
    /// Shows `toast` over this view until it closes itself, replacing any toast already showing
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastPresenter(toast: toast))
    }
}
