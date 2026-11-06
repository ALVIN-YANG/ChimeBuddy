import AppKit

/// Opaque neutral surfaces, rather than a tinted card or glass overlay.
/// Draw with the current appearance so system light/dark changes remain live.
final class BuddySurface: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        NSColor(calibratedWhite: dark ? 0.13 : 0.985, alpha: 1).setFill()
        shape.fill()
        NSColor(calibratedWhite: dark ? 0.27 : 0.85, alpha: 1).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 16, y: 44))
        divider.line(to: NSPoint(x: bounds.width - 16, y: 44))
        NSColor.separatorColor.setStroke()
        divider.lineWidth = 0.5
        divider.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
