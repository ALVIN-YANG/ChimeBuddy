import AppKit
import ImageIO

/// Keep one canvas and one character baseline across the default sprite poses.
/// Only the rendering transform changes; the authored atlas remains untouched.
enum AvatarFrameRegistration {
    static func visibleBounds(of image: CGImage) -> CGRect? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard bitmap.bitsPerSample == 8, bitmap.hasAlpha, !bitmap.isPlanar,
              let pixels = bitmap.bitmapData else { return nil }
        let step = bitmap.bitsPerPixel / 8
        let alpha = bitmap.bitmapFormat.contains(.alphaFirst) ? 0 : bitmap.samplesPerPixel - 1
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where pixels[y * bitmap.bytesPerRow + x * step + alpha] > 64 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func frames(from sheet: CGImage) -> [NSImage] {
        let width = sheet.width / 2, height = sheet.height / 2
        let cells = (0..<4).compactMap {
            sheet.cropping(to: CGRect(x: ($0 % 2) * width, y: ($0 / 2) * height, width: width, height: height))
        }
        guard let first = cells.first, let reference = visibleBounds(of: first) else { return [] }
        let canvas = NSSize(width: width, height: height)
        return cells.map { cell in
            let source = NSImage(cgImage: cell, size: canvas)
            guard let bounds = visibleBounds(of: cell) else { return source }
            let scale = reference.height / bounds.height
            let x = (reference.midX - bounds.midX * scale).rounded()
            // Bitmap rows start at the top; AppKit drawing starts at the bottom.
            let y = (CGFloat(height) - reference.maxY - (CGFloat(height) - bounds.maxY) * scale).rounded()
            let destination = NSRect(x: x, y: y, width: canvas.width * scale, height: canvas.height * scale)
            return NSImage(size: canvas, flipped: false) { _ in
                source.draw(in: destination, from: NSRect(origin: .zero, size: canvas), operation: .sourceOver, fraction: 1)
                return true
            }
        }
    }
}
