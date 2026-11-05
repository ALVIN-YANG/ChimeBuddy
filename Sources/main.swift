import AppKit
import Foundation

let workspace = "/Users/USER/Documents/my-learn/ChimeBuddy"
let storage = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ChimeBuddy")
let inbox = storage.appendingPathComponent("events")
try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])

struct HookEvent: Codable {
    let id: String
    let receivedAt: Date
    let kind: String
    let session: String
    let turn: String
    let text: String
    let simulated: Bool
}

// This executable also acts as the short-lived hook. It never calls a model or
// writes instructions back into the Codex conversation.
if CommandLine.arguments.contains("--hook") {
    do {
        let input = FileHandle.standardInput.readDataToEndOfFile()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = BuddyPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 190),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ChimeBuddy — Hooks 验证"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true

        let view = NSView(frame: panel.contentView!.bounds)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.91, alpha: 0.98).cgColor
        view.layer?.cornerRadius = 24
        let face = NSTextField(labelWithString: "🐥")
        face.font = .systemFont(ofSize: 42)
        face.frame = NSRect(x: 20, y: 120, width: 60, height: 55)
        titleLabel = NSTextField(labelWithString: "等待 Codex 消息")
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.textColor = .black
        titleLabel.frame = NSRect(x: 87, y: 141, width: 245, height: 25)
        messageLabel = NSTextField(wrappingLabelWithString: "本地验证，不调用 AI。\n收到真实 Hooks 后会显示消息摘要。\n可拖动此气泡；菜单栏 🐥 可退出。")
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .darkGray
        messageLabel.frame = NSRect(x: 22, y: 22, width: 306, height: 95)
        view.addSubview(face)
        view.addSubview(titleLabel)
        view.addSubview(messageLabel)
        panel.contentView = view
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 380, y: screen.visibleFrame.minY + 70))
        }
        panel.orderFrontRegardless()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐥"
        let menu = NSMenu()
        menu.addItem(withTitle: "显示气泡", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "退出 ChimeBuddy", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu

        // Ignore previous launches' events, then use filesystem notifications
        // rather than repeatedly polling conversation files.
        for url in (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [] {
            seen.insert(url.lastPathComponent)
        }
        fd = open(inbox.path, O_EVTONLY)
        guard fd >= 0 else { messageLabel.stringValue = "无法监听事件目录"; return }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source?.setEventHandler { [weak self] in self?.receive() }
        source?.resume()
        writeReceipt(["state": "ready", "pid": ProcessInfo.processInfo.processIdentifier])
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
            titleLabel.stringValue = (event.simulated ? "[模拟] " : "[Hooks] ") + (event.kind == "Stop" ? "Codex 回答结束" : "收到你的消息")
            messageLabel.stringValue = String(event.text.prefix(130))
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            writeReceipt(["state": "displayed", "eventID": event.id, "kind": event.kind,
                          "session": event.session, "turn": event.turn, "simulated": event.simulated])
        }
    }

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
    @objc func showPanel() { panel.orderFrontRegardless() }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
