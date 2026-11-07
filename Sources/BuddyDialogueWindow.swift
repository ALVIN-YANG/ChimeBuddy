import AppKit

/// Opened explicitly. It never types into Codex and is bound to one chat ID.
final class BuddyDialogueWindow: NSWindowController {
    let sessionID: String
    private let transcript = NSTextView()
    private let input = NSTextField()
    private let send = NSButton()
    private let hint = NSTextField(labelWithString: "")
    private var pendingKey: String?
    var onSend: ((String) -> Void)?
    init(sessionID: String, title: String) {
        self.sessionID = sessionID
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "和伙伴聊 · " + title
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = window.contentView!
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 99, width: 388, height: 204))
        scroll.hasVerticalScroller = true
        transcript.frame = scroll.bounds
        transcript.isEditable = false
        transcript.isSelectable = true
        transcript.drawsBackground = false
        transcript.textContainerInset = NSSize(width: 4, height: 8)
        transcript.autoresizingMask = [.width]
        transcript.textContainer?.widthTracksTextView = true
        transcript.setAccessibilityLabel("当前会话与伙伴的最近对话")
        scroll.documentView = transcript
        content.addSubview(scroll)
        input.frame = NSRect(x: 20, y: 51, width: 294, height: 30)
        input.placeholderString = "回她一句…"
        input.setAccessibilityLabel("对伙伴说")
        input.target = self; input.action = #selector(submit)
        content.addSubview(input)
        send.title = "发送"; send.bezelStyle = .rounded
        send.frame = NSRect(x: 324, y: 49, width: 80, height: 32)
        send.target = self; send.action = #selector(submit)
        content.addSubview(send)
        hint.frame = NSRect(x: 20, y: 19, width: 380, height: 18)
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        hint.stringValue = "只和伙伴聊，不发送到 Codex。最多保留最近 10 轮。"
        content.addSubview(hint)
        window.center()
        window.initialFirstResponder = input
    }
    required init?(coder: NSCoder) { nil }
    func update(messages: [ContextMessage], cached: String?) {
        let text = NSMutableAttributedString()
        let visible = messages.isEmpty ? (cached.map { [("伙伴", $0)] } ?? []) : messages.map { ($0.speaker == "user" ? "你" : "伙伴", $0.text) }
        for (name, line) in visible {
            text.append(NSAttributedString(string: name + "\n", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]))
            text.append(NSAttributedString(string: line + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))
        }
        transcript.textStorage?.setAttributedString(text)
        transcript.scrollToEndOfDocument(nil)
    }
    func bind(requestKey: String) { pendingKey = requestKey }
    func finish(error: String? = nil, requestKey: String? = nil) {
        if let requestKey = requestKey, pendingKey != requestKey { return }
        pendingKey = nil
        input.isEnabled = true; send.isEnabled = true
        hint.stringValue = error ?? "只和伙伴聊，不发送到 Codex。最多保留最近 10 轮。"
        window?.makeFirstResponder(input)
    }
    @objc private func submit() {
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard send.isEnabled, !value.isEmpty else { return }
        guard value.count <= 2000 else { hint.stringValue = "这句太长了，最多 2000 字。"; return }
        input.stringValue = ""; input.isEnabled = false; send.isEnabled = false
        hint.stringValue = "等她回一句…"
        onSend?(value)
    }
}
