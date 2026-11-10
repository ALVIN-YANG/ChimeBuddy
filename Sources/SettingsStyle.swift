import AppKit

final class SettingsCanvas: NSView {
    var sidebar = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor(calibratedWhite: dark ? (sidebar ? 0.105 : 0.13) : (sidebar ? 0.95 : 0.99), alpha: 1).setFill()
        bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class SettingsNavigationButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if state == .on || isHighlighted {
            NSColor.labelColor.withAlphaComponent(state == .on ? 0.09 : 0.04).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        super.draw(dirtyRect)
    }
}

enum SettingsStyle {
    static let width: CGFloat = 596
    @discardableResult static func label(_ text: String, in view: NSView, x: CGFloat = 28, y: CGFloat, width: CGFloat = 540, size: CGFloat = 13, secondary: Bool = false, height: CGFloat = 22, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.frame = NSRect(x: x, y: y, width: width, height: height)
        view.addSubview(field); return field
    }
    static func heading(_ title: String, subtitle: String, in view: NSView) {
        label(title, in: view, y: 26, size: 22, height: 30, weight: .semibold)
        label(subtitle, in: view, y: 65, size: 12, secondary: true, height: 36)
    }
    @discardableResult static func button(_ title: String, symbol: String? = nil, in view: NSView, x: CGFloat, y: CGFloat, width: CGFloat, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 12)
        if let symbol = symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); button.imagePosition = .imageLeading; button.image?.isTemplate = true }
        button.frame = NSRect(x: x, y: y, width: width, height: 32)
        button.setAccessibilityLabel(title); view.addSubview(button); return button
    }
    static func divider(in view: NSView, y: CGFloat) {
        let line = NSBox(frame: NSRect(x: 28, y: y, width: 540, height: 1)); line.boxType = .separator; view.addSubview(line)
    }
    static func input(_ field: NSTextField, label: String, in view: NSView, y: CGFloat, placeholder: String = "") {
        self.label(label, in: view, y: y + 4, width: 110)
        field.font = .systemFont(ofSize: 12)
        field.frame = NSRect(x: 146, y: y, width: 422, height: 26)
        field.placeholderString = placeholder; field.setAccessibilityLabel(label); view.addSubview(field)
    }
    static func textArea(_ text: NSTextView, label: String, in view: NSView, y: CGFloat, height: CGFloat = 64) {
        self.label(label, in: view, y: y, width: 110, secondary: true, height: 38)
        let scroll = NSScrollView(frame: NSRect(x: 146, y: y, width: 422, height: height))
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        text.isRichText = false; text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular); text.textContainerInset = NSSize(width: 5, height: 5)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        text.frame = NSRect(x: 0, y: 0, width: 420, height: height)
        text.setAccessibilityLabel(label); scroll.documentView = text; view.addSubview(scroll)
    }
}
