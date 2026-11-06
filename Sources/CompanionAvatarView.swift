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

    override func mouseDown(with event: NSEvent) { onClick?() }
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
            let width = sheet.width / 2, height = sheet.height / 2
            for index in 0..<4 {
                if let crop = sheet.cropping(to: CGRect(x: (index % 2) * width, y: (index / 2) * height, width: width, height: height)) {
                    frames.append(NSImage(cgImage: crop, size: NSSize(width: width, height: height)))
                }
            }
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
