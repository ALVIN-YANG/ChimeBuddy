import AppKit

struct SpeechBubbleLayout {
    let viewportSize: NSSize
    let documentSize: NSSize
    let scrolls: Bool

    /// Measure the same NSTextFieldCell that draws the text. NSString's text
    /// width omits the cell's inset and can underestimate an entire wrapped line.
    static func measure(_ label: NSTextField, maximumHeight: CGFloat) -> SpeechBubbleLayout {
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        let attributes: [NSAttributedString.Key: Any] = [.font: label.font ?? NSFont.systemFont(ofSize: 13)]
        let width = min(220, max(90, ceil((label.stringValue as NSString).size(withAttributes: attributes).width)))
        func height(for width: CGFloat) -> CGFloat {
            let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)) ?? .zero
            return max(18, ceil(size.height) + 2)
        }
        let available = max(18, floor(maximumHeight))
        let scrolls = height(for: width) > available
        let documentWidth = width - (scrolls ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
        let documentHeight = height(for: documentWidth)
        return SpeechBubbleLayout(viewportSize: NSSize(width: width, height: min(available, documentHeight)),
                                  documentSize: NSSize(width: documentWidth, height: documentHeight), scrolls: scrolls)
    }
}
