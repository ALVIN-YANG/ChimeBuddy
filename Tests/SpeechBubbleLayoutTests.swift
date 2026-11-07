import AppKit

@main struct SpeechBubbleLayoutTests {
    static func main() {
        let real = "你刚催完修 bug，又追问这台机器有没有问题，急得像 bug 会被你瞪没了。"
        let field = NSTextField(wrappingLabelWithString: real)
        field.font = .systemFont(ofSize: 13)
        let attrs: [NSAttributedString.Key: Any] = [.font: field.font!]
        let previous = ceil((real as NSString).boundingRect(with: NSSize(width: 220, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs).height) + 2
        let needed = field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: 220, height: CGFloat.greatestFiniteMagnitude)).height
        assert(previous < needed, "The real cached message must reproduce the former clipping")
        for text in [real, "收到了。", "中英 mixed GIF 🐉，字符不应被裁。", "第一行\n第二行\n第三行", String(repeating: "长内容完整显示。", count: 60)] {
            field.stringValue = text
            let layout = SpeechBubbleLayout.measure(field, maximumHeight: 141)
            let drawn = field.cell!.cellSize(forBounds: NSRect(origin: .zero, size: NSSize(width: layout.documentSize.width, height: CGFloat.greatestFiniteMagnitude)))
            assert(layout.documentSize.height >= ceil(drawn.height))
            assert(layout.viewportSize.height <= 141 && layout.viewportSize.width <= 220)
            if layout.scrolls {
                let scroll = NSScrollView(frame: NSRect(origin: .zero, size: layout.viewportSize))
                scroll.borderType = .noBorder; scroll.scrollerStyle = .legacy; scroll.hasVerticalScroller = true
                assert(abs(scroll.contentSize.width - layout.documentSize.width) < 1, "Text measurement must account for the real scroller width")
                assert(layout.documentSize.height > layout.viewportSize.height)
            }
            assert(field.stringValue == text, "Layout cannot truncate the message")
        }
        print("PASS: real 38-character clipping reproduced, native cell fitting, mixed text/newlines and bounded scrollable overflow")
    }
}
