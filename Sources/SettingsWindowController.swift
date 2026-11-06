import AppKit

final class SettingsWindowController: NSWindowController {
    private let preview = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let resetButton = NSButton()
    var onImport: (() -> Void)?
    var onReset: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ChimeBuddy 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = window.contentView!
        let heading = NSTextField(labelWithString: "伙伴形象")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 233, width: 332, height: 23)
        content.addSubview(heading)
        preview.frame = NSRect(x: 22, y: 44, width: 136, height: 180)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("伙伴形象预览")
        content.addSubview(preview)
        nameLabel.frame = NSRect(x: 178, y: 190, width: 178, height: 20)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        content.addSubview(nameLabel)
        let description = NSTextField(wrappingLabelWithString: "选择你喜欢的 GIF，让她动起来。")
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        description.frame = NSRect(x: 178, y: 139, width: 178, height: 39)
        content.addSubview(description)
        let importButton = NSButton(title: "导入 GIF 形象…", target: self, action: #selector(importAvatar))
        importButton.bezelStyle = .rounded
        importButton.frame = NSRect(x: 174, y: 91, width: 186, height: 32)
        content.addSubview(importButton)
        resetButton.title = "恢复默认形象"
        resetButton.target = self
        resetButton.action = #selector(resetAvatar)
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 174, y: 52, width: 186, height: 32)
        content.addSubview(resetButton)
        let hint = NSTextField(labelWithString: "GIF · 最大 20 MB")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 24, y: 17, width: 332, height: 17)
        content.addSubview(hint)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func update(customURL: URL) {
        if let image = NSImage(contentsOf: customURL), image.isValid {
            preview.image = image
            nameLabel.stringValue = "自定义 GIF"
            resetButton.isEnabled = true
        } else {
            preview.image = Bundle.main.url(forResource: "codex-companion", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            nameLabel.stringValue = "默认 Codex 伙伴"
            resetButton.isEnabled = false
        }
        preview.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @objc private func importAvatar() { onImport?() }
    @objc private func resetAvatar() { onReset?() }
}
