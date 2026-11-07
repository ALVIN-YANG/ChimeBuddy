import AppKit

final class MemoryWindowController: NSWindowController, NSTextViewDelegate {
    private let memory: SharedMemory
    private let profile = NSTextView()
    private let projects = NSTextView()
    private let count = NSTextField(labelWithString: "")
    private let saveButton = NSButton()
    init(memory: SharedMemory) {
        self.memory = memory
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "共享记忆"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = window.contentView!
        let description = NSTextField(wrappingLabelWithString: "所有会话共用这些概况。自动提取只看用户明确表达的事实，不保存对话原文。可以直接修改或清空。")
        description.font = .systemFont(ofSize: 12); description.textColor = .secondaryLabelColor
        description.frame = NSRect(x: 20, y: 416, width: 420, height: 44)
        content.addSubview(description)
        for (title, view, y, height) in [("用户画像 · 最多 400 字", profile, 254.0, 128.0), ("项目概况 · 合计最多 800 字", projects, 82.0, 134.0)] {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.frame = NSRect(x: 20, y: y + height + 6, width: 420, height: 21)
            content.addSubview(label)
            let scroll = NSScrollView(frame: NSRect(x: 20, y: y, width: 420, height: height))
            scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
            view.frame = scroll.bounds; view.isRichText = false; view.font = .systemFont(ofSize: 12)
            view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
            view.textContainerInset = NSSize(width: 7, height: 7)
            view.delegate = self; view.setAccessibilityLabel(title)
            scroll.documentView = view; content.addSubview(scroll)
        }
        count.frame = NSRect(x: 20, y: 52, width: 420, height: 19)
        count.font = .systemFont(ofSize: 11); count.textColor = .secondaryLabelColor
        content.addSubview(count)
        let clear = NSButton(title: "清空全部", target: self, action: #selector(clearAll))
        clear.bezelStyle = .rounded; clear.frame = NSRect(x: 16, y: 13, width: 96, height: 30)
        content.addSubview(clear)
        saveButton.title = "保存"; saveButton.bezelStyle = .rounded
        saveButton.target = self; saveButton.action = #selector(save)
        saveButton.frame = NSRect(x: 350, y: 13, width: 94, height: 30)
        content.addSubview(saveButton)
        window.center()
    }
    required init?(coder: NSCoder) { nil }
    func reload() {
        profile.string = memory.snapshot.profileText
        projects.string = memory.snapshot.projectsText
        textDidChange(Notification(name: NSText.didChangeNotification))
    }
    func textDidChange(_ notification: Notification) {
        count.stringValue = "画像 \(profile.string.count)/400 · 项目 \(projects.string.count)/800"
        saveButton.isEnabled = profile.string.count <= SharedMemory.profileLimit && projects.string.count <= SharedMemory.projectsLimit
    }
    @objc private func clearAll() { profile.string = ""; projects.string = ""; save() }
    @objc private func save() {
        do { try memory.replace(profile: profile.string, projects: projects.string); reload() }
        catch { NSAlert(error: error).beginSheetModal(for: window!) }
    }
}
