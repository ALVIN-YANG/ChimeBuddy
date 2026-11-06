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
        let message = (object["prompt"] as? String) ?? (object["last_assistant_message"] as? String) ?? ""
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
    var messageLabel: NSTextField!
    var sessionLabel: NSTextField!
    var closeButton: NSButton!
    var avatar: CompanionAvatarView!
    var buddySurface: BuddySurface!
    var pauseItem: NSMenuItem!
    var hiddenByUser = false
    var collapsedByUser = false
    let state = RoastState(cache: SessionReviews(directory: storage))
    let selectionReader = DesktopSelectionReader()
    let launchedAt = Date()
    let observationQueue = DispatchQueue(label: "ChimeBuddy.observation", qos: .utility)
    let reviews: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()
    var timer: Timer?
    var observationBusy = false
    var workspaceObservers: [NSObjectProtocol] = []
    var lastPage: DesktopPage?
    var candidateID: String?
    var selectionGeneration = UUID()
    var metadata: [String: CodexThreadTitle] = [:]
    var metadataRetryAt = Date.distantPast
    var transcript: SessionTranscript?
    var liveSince = Date()
    var seenHooks = Set<String>()
    var visualPreview: Bool { CommandLine.arguments.contains("--preview-light") || CommandLine.arguments.contains("--preview-dark") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.paused = UserDefaults.standard.bool(forKey: "roastPaused")
        panel = BuddyPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 282),
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
        buddySurface = BuddySurface(frame: panel.contentView!.bounds)
        buddySurface.pointerPassthroughEnabled = !visualPreview
        avatar = CompanionAvatarView(frame: BuddySurface.pet)
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.animates = true
        avatar.setAccessibilityLabel("Codex 伙伴，点击收起或展开吐槽")
        avatar.setAccessibilityRole(.button)
        avatar.onClick = { [weak self] in self?.toggleSpeech() }
        buddySurface.addSubview(avatar)
        sessionLabel = NSTextField(labelWithString: "")
        sessionLabel.font = .systemFont(ofSize: 11)
        sessionLabel.textColor = .secondaryLabelColor
        sessionLabel.lineBreakMode = .byTruncatingTail
        buddySurface.addSubview(sessionLabel)
        messageLabel = NSTextField(wrappingLabelWithString: "")
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .labelColor
        buddySurface.addSubview(messageLabel)
        closeButton = NSButton(title: "", target: self, action: #selector(hidePanel))
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "隐藏伙伴")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.setAccessibilityLabel("隐藏伙伴")
        closeButton.toolTip = "隐藏伙伴，可从菜单栏恢复"
        buddySurface.addSubview(closeButton)
        panel.contentView = buddySurface
        loadAvatar()
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 465, y: screen.visibleFrame.minY + 70))
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "ChimeBuddy")
        statusItem.button?.toolTip = "ChimeBuddy · 当前会话吐槽"
        let menu = NSMenu()
        menu.addItem(withTitle: "显示伙伴", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏伙伴", action: #selector(hidePanel), keyEquivalent: "")
        pauseItem = menu.addItem(withTitle: "暂停自动吐槽", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.state = state.paused ? .on : .off
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "导入 GIF 形象…", action: #selector(importAvatar), keyEquivalent: "")
        menu.addItem(withTitle: "恢复默认 Codex 伙伴", action: #selector(resetAvatar), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 ChimeBuddy", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        render()
        if visualPreview {
            panel.appearance = NSAppearance(named: CommandLine.arguments.contains("--preview-light") ? .aqua : .darkAqua)
            sessionLabel.stringValue = "调研 Codex 对话助手可行性"
            messageLabel.stringValue = "说好养只桌宠，结果先给她安排了会话隔离和缓存管理。"
            setSpeechVisible(true)
            avatar.setMood(.speaking)
            presentPanel()
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didHideApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.presentPanel(); self?.poll()
            })
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        writeReceipt(["state": "ready", "pid": ProcessInfo.processInfo.processIdentifier])
        poll()
    }

    func poll() {
        guard !visualPreview, !observationBusy else { return }
        observationBusy = true
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        let codex = applications.count == 1 ? applications.first : nil
        let processID = codex?.processIdentifier
        let processStartedAt = codex?.launchDate
        observationQueue.async { [weak self] in
            guard let self = self else { return }
            let page = self.selectionReader.read(processID: processID, processStartedAt: processStartedAt)
            DispatchQueue.main.async {
                self.observationBusy = false
                self.follow(page)
                self.readMessages()
            }
        }
    }

    func follow(_ page: DesktopPage?) {
        let changed = lastPage?.sessionID != page?.sessionID || lastPage?.windowID != page?.windowID || (lastPage == nil) != (page == nil)
        lastPage = page
        if changed {
            candidateID = page?.sessionID
            liveSince = max(launchedAt, page?.timestamp ?? Date())
            selectionGeneration = UUID()
            transcript = nil
            state.sessions.select(nil)
            reviews.cancelAllOperations() // Running calls may finish into their own cache.
            render()
            writeReceipt(["state": "pageChanged", "candidateSession": candidateID ?? ""])
            metadataRetryAt = .distantPast
            if let id = candidateID, let known = metadata[id] { activate(known) }
        }
        guard let id = candidateID, Date() >= metadataRetryAt else { return }
        metadataRetryAt = Date().addingTimeInterval(5)
        let generation = selectionGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try CodexThreadTitles.fetch(ids: [id]) }
            DispatchQueue.main.async {
                guard let self = self, self.selectionGeneration == generation, self.candidateID == id else { return }
                if case .success(let values) = result, let value = values.first {
                    self.metadata[id] = value
                    self.metadataRetryAt = Date().addingTimeInterval(30)
                    if self.state.sessions.selectedID == id {
                        self.state.sessions.updateTitle(value.name, for: id)
                        self.sessionLabel.stringValue = self.state.sessions.title(for: id)
                    } else {
                        self.activate(value)
                        self.readMessages()
                    }
                } else {
                    self.writeReceipt(["state": "pageIdentityUnavailable", "candidateSession": id])
                }
            }
        }
    }

    func activate(_ value: CodexThreadTitle) {
        guard candidateID == value.id else { return }
        state.sessions.updateTitle(value.name, for: value.id)
        state.sessions.select(value.id)
        if let path = value.path {
            transcript = SessionTranscript(sessionID: value.id, url: URL(fileURLWithPath: path))
        }
        render()
        writeReceipt(["state": "sessionSelected", "contextSession": value.id, "cacheRestored": state.text != nil])
    }

    func readMessages() {
        guard let id = state.sessions.selectedID else { return }
        // Transcript first: it preserves typed user items, excludes tool output,
        // and covers every local project without installing additional Hooks.
        if let transcript = transcript {
            for event in transcript.read().sorted(by: { $0.receivedAt < $1.receivedAt }) {
                consume(event, live: event.receivedAt >= liveSince)
            }
            return
        }
        // Use exactly one message source. A Hook has no transcript item ID,
        // so merging both would duplicate a user message or lose steering.
        let urls = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        let events = urls.filter { $0.pathExtension == "json" && !seenHooks.contains($0.lastPathComponent) }.compactMap { url -> HookEvent? in
            guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(HookEvent.self, from: data) else { return nil }
            seenHooks.insert(url.lastPathComponent)
            return value
        }.sorted { $0.receivedAt < $1.receivedAt }
        for event in events where event.session == id {
            consume(event, live: event.receivedAt >= liveSince)
        }
    }

    func consume(_ event: HookEvent, live: Bool) {
        guard let request = state.receive(event, live: live) else { return }
        schedule(request)
    }

    func schedule(_ request: RoastRequest) {
        avatar.setMood(.thinking)
        writeReceipt(["state": "roastQueued", "contextSession": request.event.session, "eventKey": request.key, "kind": request.event.kind])
        reviews.addOperation { [weak self] in
            guard let self = self else { return }
            let current = DispatchQueue.main.sync { self.state.canStart(request) }
            guard current else { return }
            DispatchQueue.main.async {
                self.writeReceipt(["state": "roastStarted", "contextSession": request.event.session, "eventKey": request.key, "kind": request.event.kind])
            }
            let result = Result { try CodexReviewer.review(context: request.context) }
            DispatchQueue.main.async {
                var displayed = false
                switch result {
                case .success(let answer):
                    do {
                        try self.state.complete(request, text: answer)
                        if self.state.canPresent(request) {
                            self.render()
                            self.avatar.setMood(.speaking)
                            displayed = true
                        }
                    } catch { self.writeReceipt(["state": "roastCacheFailed", "contextSession": request.event.session]) }
                case .failure(let error):
                    // Errors and connection status belong in diagnostics, never
                    // in the character's speech bubble. Keep the previous roast.
                    self.writeReceipt(["state": "roastFailed", "contextSession": request.event.session, "reason": error.localizedDescription])
                    if self.state.sessions.selectedID == request.event.session { self.render() }
                }
                self.writeReceipt(["state": "roastCompleted", "contextSession": request.event.session,
                                   "eventKey": request.key, "kind": request.event.kind, "displayed": displayed])
            }
        }
    }

    func render() {
        if let id = state.sessions.selectedID {
            sessionLabel.stringValue = state.sessions.title(for: id)
            sessionLabel.toolTip = sessionLabel.stringValue
        } else { sessionLabel.stringValue = "" }
        messageLabel.stringValue = state.text ?? ""
        setSpeechVisible(!collapsedByUser && !(state.text ?? "").isEmpty)
        avatar.setMood(.idle)
        presentPanel()
    }

    func setSpeechVisible(_ visible: Bool) {
        buddySurface.showsSpeech = visible
        for view in [messageLabel!, sessionLabel!, closeButton!] { view.isHidden = !visible }
    }

    func layoutSpeech() {
        let measured = (messageLabel.stringValue as NSString).boundingRect(
            with: NSSize(width: 266, height: 160), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: messageLabel.font!]).height
        let height = min(134, max(24, ceil(measured) + 4))
        let bottom = 274 - (height + 60)
        buddySurface.bubbleRect = NSRect(x: 8, y: bottom, width: 304, height: height + 60)
        messageLabel.frame = NSRect(x: 24, y: bottom + 16, width: 270, height: height)
        sessionLabel.frame = NSRect(x: 24, y: 246, width: 248, height: 17)
        closeButton.frame = NSRect(x: 280, y: 244, width: 22, height: 22)
        buddySurface.needsDisplay = true
    }

    func toggleSpeech() {
        collapsedByUser.toggle()
        setSpeechVisible(!collapsedByUser && !messageLabel.stringValue.isEmpty)
        writeReceipt(["state": collapsedByUser ? "speechCollapsed" : "speechExpanded"])
    }
    @objc func togglePause() {
        state.paused.toggle()
        UserDefaults.standard.set(state.paused, forKey: "roastPaused")
        pauseItem.state = state.paused ? .on : .off
        if state.paused { reviews.cancelAllOperations() }
        render()
    }
    @objc func hidePanel() { hiddenByUser = true; panel.orderOut(nil) }
    @objc func showPanel() { hiddenByUser = false; presentPanel() }
    func presentPanel() {
        layoutSpeech()
        let codexIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex"
        if !hiddenByUser && ((codexIsFrontmost && state.sessions.selectedID != nil) || visualPreview) { panel.orderFrontRegardless() }
        else { panel.orderOut(nil) }
    }
    func writeReceipt(_ values: [String: Any]) {
        var record = values
        record["timestamp"] = ISO8601DateFormatter().string(from: Date())
        record["followedSession"] = state.sessions.selectedID
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
    func loadAvatar() {
        let custom = storage.appendingPathComponent("avatar.gif")
        if let image = NSImage(contentsOf: custom) {
            avatar.loadCustom(image)
        } else if let url = Bundle.main.url(forResource: "codex-companion-atlas", withExtension: "png") {
            avatar.loadDefault(at: url)
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

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
