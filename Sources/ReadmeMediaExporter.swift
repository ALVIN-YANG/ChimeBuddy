import AppKit
import ImageIO

/// Documentation-only rendering of production views. No desktop capture,
/// personal transcript, model call or Computer Use session is involved.
enum ReadmeMediaExporter {
    static let demoText = "说好只养只桌宠，怎么还要负责吐槽代码。"
    static func export(to directory: URL, surface: NSView,
                       paint: (NSAppearance.Name, String, Bool, NSImage) -> Void) throws {
        let manager = FileManager.default
        let framesDirectory = directory.appendingPathComponent("frames")
        try manager.createDirectory(at: framesDirectory, withIntermediateDirectories: true)
        guard let url = Bundle.main.url(forResource: "codex-companion-atlas", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw failure("找不到默认伙伴图集")
        }
        let sprites = AvatarFrameRegistration.frames(from: sheet)
        guard sprites.count == 4 else { throw failure("默认伙伴图集无效") }

        func capture(theme: NSAppearance.Name, text: String, visible: Bool, sprite: Int) throws -> Data {
            paint(theme, text, visible, sprites[sprite])
            surface.layoutSubtreeIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 880, pixelsHigh: 564,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw failure("无法创建截图") }
            bitmap.size = surface.bounds.size
            surface.effectiveAppearance.performAsCurrentDrawingAppearance {
                surface.cacheDisplay(in: surface.bounds, to: bitmap)
            }
            // Consistent crop of the actual 440x282-point panel; retain both
            // the full character and every possible compact bubble width.
            guard let cropped = bitmap.cgImage?.cropping(to: CGRect(x: 128, y: 144, width: 752, height: 420)),
                  let context = CGContext(data: nil, width: 752, height: 420, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw failure("无法裁切截图")
            }
            let background: CGFloat = theme == .darkAqua ? 0.105 : 0.965
            context.setFillColor(CGColor(gray: background, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 752, height: 420))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 752, height: 420))
            guard let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw failure("无法编码截图")
            }
            return data
        }

        for (name, theme) in [("companion-light.png", NSAppearance.Name.aqua), ("companion-dark.png", .darkAqua)] {
            try capture(theme: theme, text: demoText, visible: true, sprite: 0).write(to: directory.appendingPathComponent(name))
        }
        // 12 seconds at 10 fps: native idle blink, thinking, talking, collapse,
        // then the same first state so the GIF's loop does not jump.
        for index in 0..<120 {
            let time = Double(index) / 10
            let mood: CompanionMood = time < 5.2 || time >= 9.8 ? .idle : (time < 6.6 ? .thinking : .speaking)
            let elapsed = time < 5.2 ? time : (time < 6.6 ? time - 5.2 : (time < 9.8 ? time - 6.6 : 0))
            let frame = CompanionAnimation.frame(mood: mood, elapsed: elapsed, reducedMotion: false)
            let text = time >= 5.2 && time < 6.6 ? "先让我看看你这次又写了什么。" : demoText
            let visible = !(time >= 9.8 && time < 11)
            try capture(theme: .aqua, text: text, visible: visible, sprite: frame)
                .write(to: framesDirectory.appendingPathComponent(String(format: "%03d.png", index)))
        }
        print("Exported native screenshots and 120 animation frames to \(directory.path)")
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ChimeBuddy.Media", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
