import AppKit
import ImageIO

@main struct AvatarFrameRegistrationTests {
    static func main() {
        let url = URL(fileURLWithPath: "Assets/codex-companion-atlas.png")
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let width = sheet.width / 2, height = sheet.height / 2
        let original = (0..<4).map {
            AvatarFrameRegistration.visibleBounds(of: sheet.cropping(to: CGRect(x: ($0 % 2) * width, y: ($0 / 2) * height, width: width, height: height))!)!
        }
        assert(abs(original[0].midX - original[1].midX) >= 10, "Real atlas reproduces the blink-position defect")
        let frames = AvatarFrameRegistration.frames(from: sheet)
        assert(frames.count == 4)
        let rendered = frames.map { frame -> CGRect in
            assert(frame.size == NSSize(width: width, height: height))
            // Rasterize the same AppKit image representation used by the view.
            let bitmap = NSBitmapImageRep(data: frame.tiffRepresentation!)!
            return AvatarFrameRegistration.visibleBounds(of: bitmap.cgImage!)!
        }
        for bounds in rendered {
            assert(abs(bounds.midX - rendered[0].midX) <= 1, "All rendered character centers must agree within one source pixel")
            assert(abs(bounds.maxY - rendered[0].maxY) <= 1, "Feet must not jump while blinking, thinking or speaking")
            assert(abs(bounds.height - rendered[0].height) <= 1, "Character height must remain stable")
        }
        print("PASS: real sprite atlas reproduces 12px drift; rendered frames retain one canvas, center, baseline and height")
        print("rendered bounds:", rendered)
    }
}
