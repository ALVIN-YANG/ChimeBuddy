import AppKit
import Foundation
import UniformTypeIdentifiers

let workspace = "/Users/USER/Documents/my-learn/ChimeBuddy"
let storage = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ChimeBuddy")
let inbox = storage.appendingPathComponent("events")
try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])

// This executable also acts as the short-lived hook. It never calls a model or
// writes instructions back into the Codex conversation.
if CommandLine.arguments.contains("--hook") {
    do {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let metadata: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()),
                                      "inputBytes": input.count,
                                      "simulated": CommandLine.arguments.contains("--simulate")]
        // Metadata only: proves the hook command was invoked even if validation
        // below rejects the payload. Never stores raw rejected conversation data.
        if let data = try? JSONSerialization.data(withJSONObject: metadata) {
            try? data.write(to: storage.appendingPathComponent("last-hook-invocation.json"), options: .atomic)
        }
        guard input.count <= 4_000_000,
              let object = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              object["cwd"] as? String == workspace,
              let kind = object["hook_event_name"] as? String,
              ["UserPromptSubmit", "Stop"].contains(kind) else {
            print("{}")
            exit(0)
        }
        let message = (object["prompt"] as? String) ?? (object["last_assistant_message"] as? String) ?? "（事件没有消息正文）"
        let event = HookEvent(id: UUID().uuidString, receivedAt: Date(), kind: kind,
                              session: object["session_id"] as? String ?? "unknown",
                              turn: object["turn_id"] as? String ?? "unknown",
                              text: String(message.prefix(500)),
                              simulated: CommandLine.arguments.contains("--simulate"))
        let destination = inbox.appendingPathComponent(event.id + ".json")
        try JSONEncoder().encode(event).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        print("{}")
    } catch {
        // Observer failure must not interrupt the user's task.
        fputs("ChimeBuddy: \(error.localizedDescription)\n", stderr)
        print("{}")
    }
    exit(0)
}

final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: BuddyPanel!
    var statusItem: NSStatusItem!
    var titleLabel: NSTextField!
    var messageLabel: NSTextField!
    var source: DispatchSourceFileSystemObject?
    var seen = Set<String>()
    var fd: Int32 = -1
    var hiddenByUser = false
    var avatar: NSImageView!
    var connectionLabel: NSTextField!
    var pauseItem: NSMenuItem!
    var paused = UserDefaults.standard.bool(forKey: "displayPaused")
    let sessions = SessionStore(selectedID: UserDefaults.standard.string(forKey: "selectedSession"))
    var lastEvent: HookEvent? { sessions.latest }
    var sessionPicker: NSPopUpButton!
    var mode = ReviewMode(rawValue: UserDefaults.standard.string(forKey: "reviewMode") ?? "expert") ?? .expert
    var modeItems: [NSMenuItem] = []
    var autoReview = UserDefaults.standard.bool(forKey: "autoReview")
    var autoItem: NSMenuItem!
    var reviewing = false
    var reviewGeneration = UUID()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = BuddyPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 252),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ChimeBuddy"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true

        let view = BuddySurface(frame: panel.contentView!.bounds)
        let brand = NSTextField(labelWithString: "Codex 伙伴")
        brand.font = .systemFont(ofSize: 11, weight: .medium)
        brand.textColor = .secondaryLabelColor
        brand.frame = NSRect(x: 18, y: 226, width: 200, height: 17)
        view.addSubview(brand)
        avatar = NSImageView(frame: NSRect(x: 12, y: 63, width: 128, height: 155))
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.animates = true
        avatar.setAccessibilityLabel("Codex 拟人伙伴")
        titleLabel = NSTextField(labelWithString: "等待 Codex 消息")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 152, y: 192, width: 246, height: 22)
        let closeButton = NSButton(title: "", target: self, action: #selector(hidePanel))
        closeButton.frame = NSRect(x: 386, y: 222, width: 22, height: 22)
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭气泡")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "隐藏气泡，可从菜单栏重新打开"
        closeButton.setAccessibilityLabel("关闭气泡")
        view.addSubview(closeButton)
        connectionLabel = NSTextField(labelWithString: "尚未收到真实事件")
        connectionLabel.font = .systemFont(ofSize: 11)
        connectionLabel.textColor = .secondaryLabelColor
        connectionLabel.frame = NSRect(x: 152, y: 172, width: 246, height: 17)
        messageLabel = NSTextField(wrappingLabelWithString: "在这里查看建议与吐槽。\n选择会话后，从设置开始点评。")
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .labelColor
        messageLabel.frame = NSRect(x: 152, y: 57, width: 246, height: 102)
        view.addSubview(avatar)
        view.addSubview(connectionLabel)
        view.addSubview(titleLabel)
        view.addSubview(messageLabel)
        sessionPicker = NSPopUpButton(frame: NSRect(x: 16, y: 10, width: 342, height: 26))
        sessionPicker.isBordered = false
        sessionPicker.font = .systemFont(ofSize: 11)
        sessionPicker.target = self
        sessionPicker.action = #selector(selectSession)
        view.addSubview(sessionPicker)
        let settings = NSButton(title: "", target: self, action: #selector(showSettings))
        settings.frame = NSRect(x: 374, y: 10, width: 28, height: 26)
        settings.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "设置")
        settings.isBordered = false
        settings.contentTintColor = .secondaryLabelColor
        settings.toolTip = "模式与设置"
        settings.setAccessibilityLabel("设置")
        view.addSubview(settings)
        panel.contentView = view
        loadAvatar()
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 450, y: screen.visibleFrame.minY + 70))
        }
        presentPanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "ChimeBuddy")
        statusItem.button?.toolTip = "ChimeBuddy · Codex 伙伴"
        let menu = NSMenu()
        menu.addItem(withTitle: "显示气泡", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏气泡", action: #selector(hidePanel), keyEquivalent: "")
        pauseItem = menu.addItem(withTitle: "暂停消息显示", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.state = paused ? .on : .off
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "导入 GIF 形象…", action: #selector(importAvatar), keyEquivalent: "")
        menu.addItem(withTitle: "恢复默认 Codex 伙伴", action: #selector(resetAvatar), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        for option in ReviewMode.allCases {
            let item = menu.addItem(withTitle: option.title + "模式", action: #selector(selectMode(_:)), keyEquivalent: "")
            item.representedObject = option.rawValue
            item.state = option == mode ? .on : .off
            modeItems.append(item)
        }
        menu.addItem(withTitle: "点评最新回合（使用 Codex 用量）", action: #selector(reviewLatest), keyEquivalent: "")
        autoItem = menu.addItem(withTitle: "回合结束后自动点评", action: #selector(toggleAutoReview), keyEquivalent: "")
        autoItem.state = autoReview ? .on : .off
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 ChimeBuddy", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu

        // Ignore previous launches' events, then use filesystem notifications
        // rather than repeatedly polling conversation files.
        for url in (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [] {
            seen.insert(url.lastPathComponent)
            if let data = try? Data(contentsOf: url), let event = try? JSONDecoder().decode(HookEvent.self, from: data) {
                sessions.receive(event)
            }
        }
        refreshSessions()

        refreshStatus()
        if let event = lastEvent {
            titleLabel.stringValue = "已载入固定会话"
            messageLabel.stringValue = String(event.text.prefix(130))
        }
        fd = open(inbox.path, O_EVTONLY)
        guard fd >= 0 else { messageLabel.stringValue = "无法监听事件目录"; return }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source?.setEventHandler { [weak self] in self?.receive() }
        source?.resume()
        writeReceipt(["state": "ready", "pid": ProcessInfo.processInfo.processIdentifier])
        // Explicit local visual fixture; no model request or conversation write.
        if CommandLine.arguments.contains("--preview-light") || CommandLine.arguments.contains("--preview-dark") {
            panel.appearance = NSAppearance(named: CommandLine.arguments.contains("--preview-light") ? .aqua : .darkAqua)
            titleLabel.stringValue = "双开点评 · 样式预览"
            connectionLabel.stringValue = "示例内容 · 不调用模型"
            messageLabel.stringValue = "专家：先确认需求和验收条件，再做最小改动。不要把测试通过当作完整交付。\n吐槽：只想加个按钮，差点收到一座软件产业园。"
        }
    }

    func receive() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        let events = urls.filter { $0.pathExtension == "json" && !seen.contains($0.lastPathComponent) }
            .compactMap { url -> HookEvent? in
                guard let data = try? Data(contentsOf: url), let event = try? JSONDecoder().decode(HookEvent.self, from: data) else { return nil }
                seen.insert(url.lastPathComponent)
                return event
            }.sorted { $0.receivedAt < $1.receivedAt }
        for event in events {
            let affectsSelection = sessions.receive(event)
            refreshSessions()
            guard affectsSelection else {
                writeReceipt(["state": "receivedInBackground", "eventID": event.id, "simulated": event.simulated])
                continue
            }
            reviewGeneration = UUID()
            refreshStatus()
            if paused {
                writeReceipt(["state": "receivedWhilePaused", "eventID": event.id, "simulated": event.simulated])
                continue
            }
            titleLabel.stringValue = (event.simulated ? "[模拟] " : "[Hooks] ") + (event.kind == "Stop" ? "Codex 回答结束" : "收到你的消息")
            messageLabel.stringValue = String(event.text.prefix(130))
            presentPanel()
            panel.displayIfNeeded()
            writeReceipt(["state": "displayed", "eventID": event.id, "kind": event.kind,
                          "session": event.session, "turn": event.turn, "simulated": event.simulated])
            if !event.simulated && event.kind == "Stop" && autoReview { reviewLatest() }
        }
    }

    func refreshSessions() {
        sessionPicker.removeAllItems()
        if let id = sessions.selectedID, !sessions.sessions.contains(id) {
            sessionPicker.addItem(withTitle: "所选会话暂不可用 · " + String(id.prefix(8)))
        }
        for id in sessions.sessions {
            sessionPicker.addItem(withTitle: sessions.title(for: id))
            sessionPicker.lastItem?.representedObject = id
            if id == sessions.selectedID { sessionPicker.select(sessionPicker.lastItem) }
        }
        if sessions.sessions.isEmpty { sessionPicker.addItem(withTitle: "等待真实会话 · 手动选择") }
        if let id = sessions.selectedID { UserDefaults.standard.set(id, forKey: "selectedSession") }
    }

    @objc func selectSession() {
        guard let id = sessionPicker.selectedItem?.representedObject as? String else { return }
        sessions.select(id)
        reviewGeneration = UUID()
        UserDefaults.standard.set(id, forKey: "selectedSession")
        refreshStatus()
        titleLabel.stringValue = "已切换观察会话"
        messageLabel.stringValue = String((lastEvent?.text ?? "等待此会话的消息").prefix(130))
    }

    @objc func showSettings() {
        statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 374, y: 38), in: panel.contentView)
    }

    @objc func selectMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let selected = ReviewMode(rawValue: value) else { return }
        mode = selected
        reviewGeneration = UUID()
        UserDefaults.standard.set(mode.rawValue, forKey: "reviewMode")
        for item in modeItems { item.state = (item.representedObject as? String) == mode.rawValue ? .on : .off }
    }

    @objc func toggleAutoReview() {
        autoReview.toggle()
        autoItem.state = autoReview ? .on : .off
        UserDefaults.standard.set(autoReview, forKey: "autoReview")
    }

    @objc func reviewLatest() {
        guard !paused else { return }
        guard !reviewing else {
            titleLabel.stringValue = "上次点评尚未结束"
            messageLabel.stringValue = "旧结果不会覆盖已切换的会话，请稍后再试。"
            return
        }
        guard lastEvent != nil else {
            titleLabel.stringValue = "还没有可点评的真实消息"
            messageLabel.stringValue = "先确认 Codex Hooks 接通。模拟事件不会发送给模型。"
            presentPanel()
            return
        }
        let history = sessions.history.suffix(6)
        let excerpts = history.map { ["role": $0.kind == "Stop" ? "assistant" : "user", "excerpt": $0.text] }
        guard let json = try? JSONSerialization.data(withJSONObject: excerpts), let context = String(data: json, encoding: .utf8) else { return }
        reviewing = true
        let generation = UUID()
        reviewGeneration = generation
        let selected = mode
        titleLabel.stringValue = selected.title + "正在点评…"
        messageLabel.stringValue = "通过本机 Codex 独立请求，不会向原聊天写入消息。"
        presentPanel()
        let options: [ReviewMode] = selected == .both ? [.expert, .roast] : [selected]
        let group = DispatchGroup()
        let lock = NSLock()
        var answers: [String: String] = [:]
        for option in options {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let result: String
                do { result = try CodexReviewer.review(context: context, mode: option) }
                catch { result = error.localizedDescription }
                lock.lock(); answers[option.rawValue] = result; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.reviewing = false
            guard self.reviewGeneration == generation && !self.paused else { return }
            self.titleLabel.stringValue = selected.title + "点评"
            self.messageLabel.stringValue = options.map { $0.title + "：" + String((answers[$0.rawValue] ?? "没有返回内容").prefix(selected == .both ? 65 : 120)) }.joined(separator: "\n")
            self.presentPanel()
        }
    }

    func refreshStatus() {
        if paused {
            connectionLabel.stringValue = "已暂停显示 · 仍在本地接收事件"
        } else if let event = lastEvent {
            let time = DateFormatter.localizedString(from: event.receivedAt, dateStyle: .none, timeStyle: .short)
            connectionLabel.stringValue = "固定会话 · 最近事件 \(time)"
        } else {
            connectionLabel.stringValue = "尚未收到真实事件"
        }
    }

    func loadAvatar() {
        let custom = storage.appendingPathComponent("avatar.gif")
        if let image = NSImage(contentsOf: custom) {
            avatar.image = image
        } else if let url = Bundle.main.url(forResource: "codex-companion", withExtension: "png") {
            avatar.image = NSImage(contentsOf: url)
        } else {
            avatar.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Codex 伙伴")
        }
    }

    @objc func importAvatar() {
        let picker = NSOpenPanel()
        picker.title = "选择 GIF 形象"
        picker.allowedContentTypes = [.gif]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= 20_000_000 else {
                throw NSError(domain: "ChimeBuddy", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择不超过 20 MB 的 GIF。"])
            }
            let data = try Data(contentsOf: url)
            guard data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)),
                  let image = NSImage(data: data), image.isValid else {
                throw NSError(domain: "ChimeBuddy", code: 2, userInfo: [NSLocalizedDescriptionKey: "这个文件不是可读取的 GIF。"])
            }
            try data.write(to: storage.appendingPathComponent("avatar.gif"), options: .atomic)
            loadAvatar()
            presentPanel()
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法导入形象"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func resetAvatar() {
        let url = storage.appendingPathComponent("avatar.gif")
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            loadAvatar()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc func togglePause() {
        paused.toggle()
        reviewGeneration = UUID()
        UserDefaults.standard.set(paused, forKey: "displayPaused")
        pauseItem.state = paused ? .on : .off
        refreshStatus()
    }
    @objc func hidePanel() { hiddenByUser = true; panel.orderOut(nil) }

    func writeReceipt(_ values: [String: Any]) {
        var record = values
        record["timestamp"] = ISO8601DateFormatter().string(from: Date())
        record["windowNumber"] = panel.windowNumber
        record["windowVisible"] = panel.isVisible
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            let url = storage.appendingPathComponent("receipts.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data + Data([10]))
            }
        }
    }
    func presentPanel() { if !hiddenByUser { panel.orderFrontRegardless() } }
    @objc func showPanel() { hiddenByUser = false; presentPanel() }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
