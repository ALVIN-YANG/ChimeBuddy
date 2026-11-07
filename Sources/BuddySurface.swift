import AppKit

/// Read-only NSTextField's default mouse handler does not show its assigned
/// menu. Route the secondary click explicitly so the bubble shares pet actions.
final class CompanionSpeechLabel: NSTextField {
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu else { super.rightMouseDown(with: event); return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// A compact speech bubble beside an independent transparent character.
final class BuddySurface: NSView {
    static let bubble = NSRect(x: 74, y: 109, width: 262, height: 58)
    var bubbleRect = BuddySurface.bubble
    var pointerPassthroughEnabled = true
    static let pet = NSRect(x: 316, y: 12, width: 116, height: 158)
    var showsSpeech = true { didSet { needsDisplay = true } }
    private var pointerTimer: Timer?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pointerTimer?.invalidate()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let window = self.window, window.isVisible else { return }
            if !self.pointerPassthroughEnabled { window.ignoresMouseEvents = false; return }
            let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            window.ignoresMouseEvents = !(Self.pet.contains(point) || (self.showsSpeech && self.bubbleRect.contains(point)))
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }
    override func draw(_ dirtyRect: NSRect) {
        guard showsSpeech else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let shape = NSBezierPath(roundedRect: bubbleRect, xRadius: 12, yRadius: 12)
        let tailY = bubbleRect.minY + min(22, bubbleRect.height / 2)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bubbleRect.maxX - 1, y: tailY + 6))
        tail.line(to: NSPoint(x: bubbleRect.maxX + 14, y: tailY - 6))
        tail.line(to: NSPoint(x: bubbleRect.maxX - 1, y: tailY - 6))
        tail.close()
        let background = NSColor(calibratedWhite: dark ? 0.13 : 0.985, alpha: 1)
        background.setFill(); shape.fill(); tail.fill()
        NSColor(calibratedWhite: dark ? 0.29 : 0.84, alpha: 1).setStroke()
        shape.lineWidth = 0.75; shape.stroke()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    deinit { pointerTimer?.invalidate() }
}
