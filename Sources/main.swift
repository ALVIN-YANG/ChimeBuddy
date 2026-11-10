import AppKit
import Foundation
import UniformTypeIdentifiers

let workspace = HookWorkspace.resolve(bundleURL: Bundle.main.bundleURL, environment: ProcessInfo.processInfo.environment)
let exportingReadme = CommandLine.arguments.contains("--export-readme") || CommandLine.arguments.contains("--export-settings")
if let index = CommandLine.arguments.firstIndex(of: "--export-readme"), CommandLine.arguments.count <= index + 1 {
    fputs("Usage: ChimeBuddy --export-readme <output-directory>\n", stderr)
    exit(2)
}
let storage = exportingReadme
    ? FileManager.default.temporaryDirectory.appendingPathComponent("ChimeBuddyReadme-" + UUID().uuidString)
    : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ChimeBuddy")
let inbox = storage.appendingPathComponent("events")
try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])

if CommandLine.arguments.contains("--probe-voice") {
    do { try VoiceProbe.run(storage: storage); exit(0) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--check-voice-config") {
    do {
        let preferences = VoicePreferences(directory: storage)
        let provider = preferences.value.provider
        _ = try TTSRequest.build(provider: provider, configuration: preferences.configuration(for: provider), secrets: VoiceKeychain.load(provider), text: "配置检查")
        print("Saved voice configuration and Keychain readable: \(provider.title), \(preferences.configuration(for: provider).model)")
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

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
        guard let workspace = workspace, input.count <= 4_000_000,
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
    var speechScroll: NSScrollView!
    var laidOutSpeech: String?
    var avatar: CompanionAvatarView!
    var buddySurface: BuddySurface!
    var settingsController: SettingsWindowController?
    var dialogueController: BuddyDialogueWindow?
    var memoryController: MemoryWindowController?
    let actionLibrary = ActionLibrary(directory: storage)
    let voicePreferences = VoicePreferences(directory: storage)
    lazy var performance: CompanionPerformance = {
        let value = CompanionPerformance(avatar: avatar, library: actionLibrary, preferences: voicePreferences)
        value.restoreAvatar = { [weak self] in self?.loadAvatar() }
        value.onVoiceError = { [weak self] message in self?.settingsController?.setVoiceStatus(message) }
        value.voice.onMetrics = { [weak self] values in self?.writeReceipt(values) }
        return value
    }()
    var hiddenByUser = false
    var collapsedByUser = false
    let state = RoastState(cache: SessionReviews(directory: storage))
    let memory = SharedMemory(directory: storage)
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
    var mediaExportURL: URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--export-readme"), CommandLine.arguments.count > index + 1 else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    }
    var visualPreview: Bool { mediaExportURL != nil || CommandLine.arguments.contains("--preview-light") || CommandLine.arguments.contains("--preview-dark") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--export-settings") {
            guard CommandLine.arguments.count > index + 1 else { fputs("Usage: ChimeBuddy --export-settings <directory>\n", stderr); exit(2) }
            NSApp.setActivationPolicy(.prohibited)
            do {
                try SettingsMediaExporter.export(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), storage: storage)
                try? FileManager.default.removeItem(at: storage); exit(0)
            } catch { try? FileManager.default.removeItem(at: storage); fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        NSApp.setActivationPolicy(mediaExportURL == nil ? .accessory : .prohibited)
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
        messageLabel = CompanionSpeechLabel(wrappingLabelWithString: "")
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .labelColor
        speechScroll = NSScrollView()
        speechScroll.borderType = .noBorder
        speechScroll.drawsBackground = false
        speechScroll.contentView.drawsBackground = false
        speechScroll.scrollerStyle = .overlay
        speechScroll.autohidesScrollers = true
        speechScroll.hasHorizontalScroller = false
        speechScroll.documentView = messageLabel
        buddySurface.addSubview(speechScroll)
        let companionMenu = NSMenu()
        let chatItem = companionMenu.addItem(withTitle: "和她聊聊…", action: #selector(showDialogue), keyEquivalent: "")
        chatItem.target = self
        let hideItem = companionMenu.addItem(withTitle: "隐藏伙伴", action: #selector(hidePanel), keyEquivalent: "")
        hideItem.target = self
        avatar.menu = companionMenu
        buddySurface.menu = companionMenu
        messageLabel.menu = companionMenu
        speechScroll.menu = companionMenu
        avatar.toolTip = "点击收起/展开，右键和她聊聊"
        panel.contentView = buddySurface
        loadAvatar()
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 465, y: screen.visibleFrame.minY + 70))
        }
        if mediaExportURL == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "ChimeBuddy")
            statusItem.button?.toolTip = "ChimeBuddy · 当前会话吐槽"
            let menu = NSMenu()
            menu.addItem(withTitle: "显示伙伴", action: #selector(showPanel), keyEquivalent: "")
            menu.addItem(withTitle: "隐藏伙伴", action: #selector(hidePanel), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "退出 ChimeBuddy", action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            statusItem.menu = menu
        }
        render()
        if visualPreview {
            if let directory = mediaExportURL {
                do {
                    try ReadmeMediaExporter.export(to: directory, surface: buddySurface) { theme, text, visible, sprite in
                        self.panel.appearance = NSAppearance(named: theme)
                        self.messageLabel.stringValue = text
                        self.setSpeechVisible(visible)
                        self.layoutSpeech()
                        self.avatar.image = sprite
                    }
                    try? FileManager.default.removeItem(at: storage)
                    exit(0)
                } catch {
                    try? FileManager.default.removeItem(at: storage)
                    fputs("\(error.localizedDescription)\n", stderr); exit(1)
                }
            }
            panel.appearance = NSAppearance(named: CommandLine.arguments.contains("--preview-light") ? .aqua : .darkAqua)
            messageLabel.stringValue = "说好养只桌宠，结果先给她安排了会话隔离和缓存管理。"
            if CommandLine.arguments.contains("--preview-long") {
                messageLabel.stringValue = "说好只养一只安静的小桌宠，结果会话隔离、自动吐槽、缓存恢复和全屏跟随一个都不能少，她还没正式上岗，验收清单倒是先写满了一页。"
            }
            if CommandLine.arguments.contains("--preview-wrap") {
                messageLabel.stringValue = "你刚催完修 bug，又追问这台机器有没有问题，急得像 bug 会被你瞪没了。"
            }
            if CommandLine.arguments.contains("--preview-overflow") {
                messageLabel.stringValue = String(repeating: "这是一段超长气泡测试，内容保留，不用硬裁。", count: 18) + "最后一句也完整保留。"
            }
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
        if CommandLine.arguments.contains("--settings") { showSettings() }
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
            performance.cancel()
            candidateID = page?.sessionID
            liveSince = max(launchedAt, page?.timestamp ?? Date())
            selectionGeneration = UUID()
            transcript = nil
            dialogueController?.close()
            dialogueController = nil
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
        if CommandLine.arguments.contains("--dialogue") && dialogueController == nil { showDialogue() }
    }

    func readMessages() {
        // Hooks are a delivery inbox, not a transcript archive. Drain even when
        // the transcript source is available or no Codex page is selected.
        let urls = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        let events = urls.filter { $0.pathExtension == "json" }.compactMap { url -> HookEvent? in
            guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(HookEvent.self, from: data) else { return nil }
            try? FileManager.default.removeItem(at: url)
            return value
        }.sorted { $0.receivedAt < $1.receivedAt }
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
        for event in events where event.session == id {
            consume(event, live: event.receivedAt >= liveSince)
        }
    }

    func consume(_ event: HookEvent, live: Bool) {
        guard let request = state.receive(event, live: live) else { return }
        schedule(request)
    }

    func schedule(_ request: RoastRequest) {
        performance.cancel()
        avatar.setMood(.thinking)
        let memoryGeneration = memory.editGeneration
        let actions = Dictionary(uniqueKeysWithValues: actionLibrary.available.map { ($0.tag, $0.meaning) })
        writeReceipt(["state": "roastQueued", "contextSession": request.event.session, "eventKey": request.key, "kind": request.event.kind])
        reviews.addOperation { [weak self] in
            guard let self = self else { return }
            let current = DispatchQueue.main.sync { self.state.canStart(request) }
            guard current else { return }
            let selection = CodexModelPreferences.load()
            let memorySnapshot = DispatchQueue.main.sync { self.memory.snapshot }
            DispatchQueue.main.async {
                self.writeReceipt(["state": "roastStarted", "contextSession": request.event.session, "eventKey": request.key, "kind": request.event.kind,
                                   "model": selection?.model ?? "default", "reasoningEffort": selection?.effort ?? "default"])
            }
            let result = Result { try CodexReviewer.respond(context: request.context, direct: request.direct, memory: memorySnapshot, selection: selection, actions: actions) }
            DispatchQueue.main.async {
                var displayed = false
                switch result {
                case .success(let answer):
                    do {
                        // Assistant output never authorizes a memory extraction.
                        do { try self.memory.apply(answer, source: request.event, generation: memoryGeneration) }
                        catch { self.writeReceipt(["state": "memorySaveFailed"]) }
                        try self.state.complete(request, text: answer.text, action: answer.action)
                        if self.state.canPresent(request) {
                            self.render()
                            if !answer.text.isEmpty {
                                if self.panel.isVisible || (request.direct && self.dialogueController?.window?.isKeyWindow == true) {
                                    self.performance.play(text: answer.text, action: answer.action)
                                }
                                displayed = true
                            }
                        }
                        self.updateDialogue()
                        if request.direct, self.dialogueController?.sessionID == request.event.session { self.dialogueController?.finish(requestKey: request.key) }
                    } catch {
                        self.writeReceipt(["state": "roastCacheFailed", "contextSession": request.event.session])
                        if request.direct, self.dialogueController?.sessionID == request.event.session { self.dialogueController?.finish(error: "回复缓存失败，请重试。", requestKey: request.key) }
                    }
                case .failure(let error):
                    // Errors and connection status belong in diagnostics, never
                    // in the character's speech bubble. Keep the previous roast.
                    self.writeReceipt(["state": "roastFailed", "contextSession": request.event.session, "reason": error.localizedDescription])
                    if self.state.sessions.selectedID == request.event.session { self.render() }
                    if request.direct, self.dialogueController?.sessionID == request.event.session { self.dialogueController?.finish(error: error.localizedDescription, requestKey: request.key) }
                }
                self.writeReceipt(["state": "roastCompleted", "contextSession": request.event.session,
                                   "eventKey": request.key, "kind": request.event.kind, "displayed": displayed])
            }
        }
    }

    func render() {
        messageLabel.stringValue = state.text ?? ""
        setSpeechVisible(!collapsedByUser && !(state.text ?? "").isEmpty)
        avatar.setMood(.idle)
        presentPanel()
    }

    func setSpeechVisible(_ visible: Bool) {
        buddySurface.showsSpeech = visible
        speechScroll.isHidden = !visible
    }

    func layoutSpeech() {
        let y = BuddySurface.pet.midY + 18
        let layout = SpeechBubbleLayout.measure(messageLabel, maximumHeight: buddySurface.bounds.height - y - 28)
        let bubble = NSRect(x: BuddySurface.pet.minX + 20 - (layout.viewportSize.width + 20),
                            y: y, width: layout.viewportSize.width + 20, height: layout.viewportSize.height + 16)
        buddySurface.bubbleRect = bubble
        speechScroll.hasVerticalScroller = layout.scrolls
        speechScroll.verticalScroller?.controlSize = .small
        speechScroll.frame = NSRect(origin: NSPoint(x: bubble.minX + 10, y: bubble.minY + 8), size: layout.viewportSize)
        messageLabel.frame = NSRect(origin: .zero, size: layout.documentSize)
        if laidOutSpeech != messageLabel.stringValue {
            let top = messageLabel.isFlipped ? 0 : max(0, messageLabel.frame.height - speechScroll.contentSize.height)
            speechScroll.contentView.scroll(to: NSPoint(x: 0, y: top))
            speechScroll.reflectScrolledClipView(speechScroll.contentView)
            laidOutSpeech = messageLabel.stringValue
        }
        buddySurface.needsDisplay = true
    }

    func toggleSpeech() {
        collapsedByUser.toggle()
        setSpeechVisible(!collapsedByUser && !messageLabel.stringValue.isEmpty)
        writeReceipt(["state": collapsedByUser ? "speechCollapsed" : "speechExpanded"])
    }
    @objc func showSettings() {
        performance.cancel()
        if settingsController == nil {
            let controller = SettingsWindowController(actions: actionLibrary, voice: voicePreferences)
            controller.onImport = { [weak self] in self?.importAvatar() }
            controller.onReset = { [weak self] in self?.resetAvatar() }
            controller.onMemory = { [weak self] in self?.showMemory() }
            controller.onChange = { [weak self] in self?.performance.cancel() }
            settingsController = controller
        }
        settingsController?.update(customURL: storage.appendingPathComponent("avatar.gif"))
        settingsController?.loadModels()
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showMemory() {
        if memoryController == nil { memoryController = MemoryWindowController(memory: memory) }
        memoryController?.reload()
        memoryController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        memoryController?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showDialogue() {
        guard let id = state.sessions.selectedID else { return }
        if dialogueController?.sessionID != id {
            let controller = BuddyDialogueWindow(sessionID: id, title: state.sessions.title(for: id))
            controller.onSend = { [weak self, weak controller] text in
                guard let self = self, let request = self.state.reply(text, sessionID: id) else {
                    controller?.finish(error: "会话已切换，请在当前会话重新打开。")
                    return
                }
                controller?.bind(requestKey: request.key)
                self.updateDialogue()
                self.schedule(request)
            }
            dialogueController = controller
        }
        updateDialogue()
        dialogueController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        dialogueController?.window?.makeKeyAndOrderFront(nil)
    }
    func updateDialogue() {
        guard let id = dialogueController?.sessionID, state.sessions.selectedID == id else { return }
        dialogueController?.update(messages: state.buddyMessages(sessionID: id), cached: state.text)
    }
    @objc func hidePanel() { hiddenByUser = true; performance.cancel(); panel.orderOut(nil) }
    @objc func showPanel() { hiddenByUser = false; presentPanel() }
    func presentPanel() {
        layoutSpeech()
        guard mediaExportURL == nil else { return }
        let codexIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex"
        if !hiddenByUser && ((codexIsFrontmost && state.sessions.selectedID != nil) || visualPreview) { panel.orderFrontRegardless() }
        else {
            panel.orderOut(nil)
            let replyingToBuddy = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
                && dialogueController?.window?.isKeyWindow == true && dialogueController?.sessionID == state.sessions.selectedID
            if !replyingToBuddy { performance.cancel() }
        }
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
        if mediaExportURL == nil, let image = NSImage(contentsOf: custom) {
            avatar.loadCustom(image)
        } else if let url = Bundle.main.url(forResource: "codex-companion-atlas", withExtension: "png") {
            avatar.loadDefault(at: url)
        } else {
            avatar.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Codex 伙伴")
        }
        settingsController?.update(customURL: custom)
    }

    @objc func importAvatar() {
        let picker = NSOpenPanel()
        picker.title = "选择 GIF 形象"
        picker.allowedContentTypes = [.gif]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard let window = settingsController?.window else { return }
        picker.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = picker.url else { return }
            self?.installAvatar(at: url)
        }
    }

    func installAvatar(at url: URL) {
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
            if let window = settingsController?.window { alert.beginSheetModal(for: window) }
        }
    }

    @objc func resetAvatar() {
        let url = storage.appendingPathComponent("avatar.gif")
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            loadAvatar()
        } catch {
            let alert = NSAlert(error: error)
            if let window = settingsController?.window { alert.beginSheetModal(for: window) }
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
