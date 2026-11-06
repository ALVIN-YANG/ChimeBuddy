import AppKit
import ImageIO

/// State-driven, cached sprite playback. Custom GIFs keep AppKit's decoder.
final class CompanionAvatarView: NSImageView {
    var onClick: (() -> Void)?
    private var frames: [NSImage] = []
    private var custom = false
    private var mood: CompanionMood = .idle
    private var started = Date()
    private var timer: Timer?
    private var displayedFrame = -1
    private var dragAnchor: NSPoint?
    private var originalOrigin: NSPoint?
    private var dragged = false

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        originalOrigin = window.frame.origin
        dragAnchor = NSPoint(x: window.frame.minX + event.locationInWindow.x, y: window.frame.minY + event.locationInWindow.y)
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window = window, let anchor = dragAnchor, let origin = originalOrigin else { return }
        let dx = window.frame.minX + event.locationInWindow.x - anchor.x
        let dy = window.frame.minY + event.locationInWindow.y - anchor.y
        if abs(dx) + abs(dy) > 3 { dragged = true }
        guard dragged else { return }
        var point = NSPoint(x: origin.x + dx, y: origin.y + dy)
        if let screen = window.screen {
            point.x = min(max(point.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - window.frame.width)
            point.y = min(max(point.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - window.frame.height)
        }
        window.setFrameOrigin(point)
    }
    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick?() }
        dragAnchor = nil; originalOrigin = nil
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    func setMood(_ value: CompanionMood) {
        mood = value
        started = Date()
        displayedFrame = -1
        tick()
    }
    func loadDefault(at url: URL) {
        custom = false
        frames.removeAll()
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            frames = AvatarFrameRegistration.frames(from: sheet)
        }
        displayedFrame = -1
        if timer == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        tick()
    }
    func loadCustom(_ value: NSImage) {
        custom = true
        image = value
        animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    private func tick() {
        guard !custom, frames.count == 4 else { return }
        guard window?.isVisible == true || image == nil else { return }
        let index = CompanionAnimation.frame(mood: mood, elapsed: Date().timeIntervalSince(started),
                                            reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if index != displayedFrame { image = frames[index]; displayedFrame = index }
    }
    deinit { timer?.invalidate() }
}
