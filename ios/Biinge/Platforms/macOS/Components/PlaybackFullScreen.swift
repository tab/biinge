import AppKit
import SwiftUI

/// Enters the window's fullscreen while the player shows and leaves it when the player goes, only when the player entered it
struct PlaybackFullScreen: NSViewRepresentable {
    func makeNSView(context: Context) -> PlaybackFullScreenView {
        PlaybackFullScreenView()
    }

    func updateNSView(_ view: PlaybackFullScreenView, context: Context) {}
}

/// An empty view that toggles its own window's fullscreen as it joins and leaves the window (every way playback ends removes it)
final class PlaybackFullScreenView: NSView {
    /// Whether playback entered fullscreen and the user hasn't left it since
    private var didEnter = false
    /// Whether the enter animation still runs
    private var isEntering = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // a window already in fullscreen stays as it is, on stop too
        guard let window, !didEnter, !window.styleMask.contains(.fullScreen) else { return }
        // selector observers go with the view, and the handlers only touch its own flags
        NotificationCenter.default.addObserver(self, selector: #selector(entered), name: NSWindow.didEnterFullScreenNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(exited), name: NSWindow.didExitFullScreenNotification, object: window)
        didEnter = true
        isEntering = true
        window.toggleFullScreen(nil)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, let window, didEnter else { return }
        didEnter = false
        if isEntering {
            // a toggle during the enter animation is lost, so a stop then leaves fullscreen once the animation ends
            let entered = NotificationCenter.default.notifications(named: NSWindow.didEnterFullScreenNotification, object: window)
            Task {
                for await _ in entered { break }
                window.toggleFullScreen(nil)
            }
        } else if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    @objc private func entered() {
        isEntering = false
    }

    /// The user left fullscreen during playback, so the stop leaves the window alone
    @objc private func exited() {
        didEnter = false
    }
}
