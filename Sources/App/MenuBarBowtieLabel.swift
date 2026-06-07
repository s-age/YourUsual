import AppKit
import SwiftUI

/// Menu-bar status-item label: a bow tie over an open collar V, distilled from
/// the app's tuxedo mark so it stays legible at menu-bar size (where the full
/// figure would be unreadable). Rendered as a *template* `NSImage` so AppKit
/// tints it for light/dark menu bars and inverts it when the status item is
/// highlighted — the same behaviour the previous SF Symbol gave us.
struct MenuBarBowtieLabel: View {
    /// The shared menu VM. Read here only to observe `presentResultTick` — the label
    /// renders nothing from it; this is purely the always-mounted trigger point.
    let viewModel: MenuItemsViewModel
    /// Brings the app forward before the Result window opens (an `.accessory` app does
    /// not auto-activate, so the window would otherwise land behind the frontmost app).
    let activate: @MainActor () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: Self.makeImage(side: 18))
            .accessibilityLabel("Your Usual")
            // The status item is mounted for the whole app lifetime, unlike the menu
            // popover content. Observing here means a background run that produces output
            // (or fails) after the menu was dismissed still surfaces its result window —
            // the popover-content observer would have unmounted and missed the tick.
            .onChange(of: viewModel.presentResultTick) {
                activate()
                openWindow(id: "result")
            }
    }

    /// Builds the template icon. The drawing handler is resolution-independent:
    /// AppKit re-invokes it per scale factor, so the mark stays crisp on Retina.
    private static func makeImage(side: CGFloat) -> NSImage {
        let image = NSImage(
            size: NSSize(width: side, height: side),
            flipped: true
        ) { rect in
            drawBowtieAndCollar(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Draws the bow tie and collar V into `rect` (top-left origin, y-down). Filled
/// black; the enclosing `NSImage.isTemplate` flag is what recolours it to the
/// menu-bar tint, so only the alpha mask produced here matters.
private func drawBowtieAndCollar(in rect: CGRect) {
    let width = rect.width
    let height = rect.height
    func point(_ relX: CGFloat, _ relY: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + relX * width, y: rect.minY + relY * height)
    }

    NSColor.black.setFill()
    NSColor.black.setStroke()

    // Bow tie — two triangular wings flanking a central knot, kept compact and
    // nudged toward the top so the collar stem has room below.
    let wings = NSBezierPath()
    wings.move(to: point(0.21, 0.12))
    wings.line(to: point(0.21, 0.34))
    wings.line(to: point(0.47, 0.23))
    wings.close()
    wings.move(to: point(0.79, 0.12))
    wings.line(to: point(0.79, 0.34))
    wings.line(to: point(0.53, 0.23))
    wings.close()
    wings.fill()

    let knot = NSBezierPath(
        roundedRect: CGRect(
            x: point(0.45, 0.165).x,
            y: point(0.45, 0.165).y,
            width: 0.10 * width,
            height: 0.13 * height
        ),
        xRadius: 0.02 * width,
        yRadius: 0.02 * height
    )
    knot.fill()

    // Collar — two lapel edges converge, then drop as a single stem, tracing a
    // "Y" beneath the bow tie.
    let collar = NSBezierPath()
    collar.lineWidth = 0.075 * width
    collar.lineCapStyle = .round
    collar.lineJoinStyle = .round
    collar.move(to: point(0.35, 0.34))
    collar.line(to: point(0.50, 0.56))
    collar.line(to: point(0.50, 0.78))
    collar.move(to: point(0.65, 0.34))
    collar.line(to: point(0.50, 0.56))
    collar.stroke()
}
