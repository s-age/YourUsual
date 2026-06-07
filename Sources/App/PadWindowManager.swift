import AppKit
import SwiftUI

/// Hosts each Launcher Pad in its **own** non-activating `NSPanel`, keyed by pad
/// layout id, so several pads can be open at once. Tapping a cell fires its action
/// *without* activating this app or stealing key focus from the foreground app — the
/// one capability a physical Stream Deck has that a plain SwiftUI `Window` cannot
/// (clicking a `Window` activates the owning app).
///
/// This is the sanctioned AppKit drop-down (CLAUDE.md: "drop to AppKit only if
/// SwiftUI lacks the capability"): SwiftUI's `WindowGroup`/`Window` scenes cannot
/// express `.nonactivatingPanel`. It lives in `App/` (the AppKit boundary); the
/// content (`PadContainerView`) stays pure SwiftUI in `Presentation/`.
///
/// Generalizes the former single-panel `PadPanelController` to a `[UUID: NSPanel]`
/// registry. Each panel uses a per-pad frame autosave name so windows remember their
/// own size/position independently instead of fighting over one shared frame.
///
/// Prototype scope: a `.runAndStream` cell streams into the shared menu VM and is
/// viewable from the menu's Result window — the panel does not auto-open it, since
/// doing so would re-activate the app and defeat the focus-preserving design.
@MainActor
final class PadWindowManager {
    private let makeContent: @MainActor (UUID) -> PadContainerView
    private var panels: [UUID: NSPanel] = [:]

    init(makeContent: @escaping @MainActor (UUID) -> PadContainerView) {
        self.makeContent = makeContent
    }

    /// Show the pad's panel if hidden, hide it if visible. The first toggle for a
    /// given id lazily builds the panel. Showing uses `orderFrontRegardless()` so the
    /// panel surfaces without activating this app.
    func toggle(padID: UUID) {
        if let panel = panels[padID] {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
            }
            return
        }
        let panel = makePanel(for: padID)
        panels[padID] = panel
        panel.orderFrontRegardless()
    }

    /// Close and forget the pad's panel, if one is open. Called after the pad's layout
    /// is deleted so no orphaned panel lingers for a pad that no longer exists. No-op
    /// when the pad was never opened (no panel built). `close()` is safe here because
    /// panels are `isReleasedWhenClosed = false`; dropping the last reference from the
    /// registry is what releases it.
    func close(padID: UUID) {
        guard let panel = panels.removeValue(forKey: padID) else { return }
        panel.close()
    }

    private func makePanel(for padID: UUID) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true   // don't grab key focus merely by appearing
        panel.hidesOnDeactivate = false       // stay up while another app is frontmost
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // Move the panel by its (transparent) titlebar strip only, NOT by the content
        // background: a slider cell is a custom SwiftUI control, not an AppKit one, so the
        // window does not auto-exempt it — background-dragging would move the whole panel
        // while the user is dragging a slider. Cells stay tappable/draggable; the titlebar
        // (where the traffic lights sit) remains the drag handle.
        panel.isMovableByWindowBackground = false

        // Let the panel drive the content size, not the reverse. NSHostingView's
        // default `.standardBounds` sizing pins the window to the SwiftUI content's
        // intrinsic size, which fights edge-drag resizing. Clearing it (and tracking
        // the panel via autoresizing) lets the user resize freely; the grid divides
        // the new bounds so cells grow/shrink to match. Resizing needs neither key
        // focus nor app activation, so the non-activating, focus-preserving design
        // (see type doc) is untouched.
        let host = NSHostingView(rootView: makeContent(padID))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        panel.contentMinSize = NSSize(width: 320, height: 240)
        // Persist each pad's chosen size/position across launches, keyed by id so
        // windows don't fight over one shared frame. Takes effect only when no frame
        // is saved yet, so center() seeds the first-run position.
        panel.center()
        panel.setFrameAutosaveName("LauncherPad-\(padID.uuidString)")
        return panel
    }
}
