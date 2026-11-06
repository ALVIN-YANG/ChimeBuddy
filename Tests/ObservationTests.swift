import Foundation

@main struct ObservationTests {
    static func main() throws {
        let a = "00000000-0000-4000-8000-000000000001"
        let b = "00000000-0000-4000-8000-000000000002"
        func route(_ id: String?, _ time: String = "2026-11-06T09:00:00.000Z", window: String = "2") -> String {
            "\(time) info [electron-message-handler] IAB_LIFECYCLE received browser sidebar owner sync browserTabId=null ownerRoutePath=\(id.map { "/local/" + $0 } ?? "/") windowId=\(window)"
        }
        assert(DesktopSelectionParser.parse(route(a))?.sessionID == a)
        assert(DesktopSelectionParser.parse(route(nil))?.sessionID == nil)
        assert(DesktopSelectionParser.parse(route("client-new-thread:temporary")) == nil)
        assert(DesktopSelectionParser.parse("2026-11-06T09:00:00.000Z thread_stream_view_activity_changed active=true conversationId=\(b) streamRole=owner") == nil,
               "Background stream activity without focus must not change the current route")
        assert(DesktopSelectionParser.parse("2026-11-06T09:00:00.000Z thread_stream_view_activity_changed active=true conversationId=\(b) rendererWindowId=2 rendererWindowAppearance=primary rendererWindowFocused=false") == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("codex-desktop-instance-42-t0-i1-000-0.log")
        try Data((route(a) + "\n").utf8).write(to: log)
        let foreign = directory.appendingPathComponent("codex-desktop-instance-43-t0-i1-000-0.log")
        try Data((route(b, "2026-11-06T10:00:00.000Z") + "\n").utf8).write(to: foreign)
        let reader = DesktopSelectionReader(root: directory)
        assert(reader.read(processID: 42)?.sessionID == a)
        func append(_ value: String, to url: URL) throws {
            let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: Data(value.utf8))
        }
        let next = route(b, "2026-11-06T09:00:01.000Z")
        try append(String(next.prefix(75)), to: log)
        assert(reader.read(processID: 42)?.sessionID == a, "Incomplete log lines cannot select a page")
        try append(String(next.dropFirst(75)) + "\n", to: log)
        assert(reader.read(processID: 42)?.sessionID == b, "Click route switches an already-loaded chat")
        let rotation = directory.appendingPathComponent("codex-desktop-instance-42-t0-i1-000-1.log")
        try Data((route(a, "2026-11-06T08:00:00.000Z") + "\n").utf8).write(to: rotation)
        assert(reader.read(processID: 42)?.sessionID == b, "New file mtime cannot override newer event time")
        try append(route(nil, "2026-11-06T09:00:02.000Z") + "\n", to: log)
        assert(reader.read(processID: 42)?.sessionID == nil, "Home clears current context")
        try append(route(a, "2026-11-06T09:00:03.000Z", window: "9") + "\n", to: log)
        assert(reader.read(processID: 42) == nil, "Do not guess between windows when focus fields are absent")
        assert(reader.read(processID: nil) == nil)
        assert(reader.read(processID: 43)?.sessionID == b, "Process restart discards previous selection")

        func json(_ payload: [String: Any], type: String = "event_msg") -> String {
            let data = try! JSONSerialization.data(withJSONObject: ["timestamp": "2026-11-06T09:00:00.123Z", "type": type, "payload": payload])
            return String(data: data, encoding: .utf8)!
        }
        func user(_ itemID: String, text: String = "只吐槽这句话") -> String {
            json(["type": "item_completed", "thread_id": a, "turn_id": "turn-1", "item": ["type": "UserMessage", "id": itemID, "content": [["type": "text", "text": text], ["type": "local_image", "path": "/not-a-text-message"]]]])
        }
        let prompt = TranscriptParser.event(user("message-1"), sessionID: a)!
        assert(prompt.kind == "UserPromptSubmit" && prompt.text == "只吐槽这句话")
        assert(TranscriptParser.event(user("message-1"), sessionID: b) == nil)
        let steer = TranscriptParser.event(user("message-2"), sessionID: a)!
        assert(prompt.deliveryKey != steer.deliveryKey, "Steering in the same turn remains a separate user input")
        let complete = TranscriptParser.event(json(["type": "task_complete", "turn_id": "turn-1", "last_agent_message": "AI 最终回复"]), sessionID: a)!
        assert(complete.kind == "Stop" && complete.text == "AI 最终回复")
        for item in ["AgentMessage", "Reasoning", "CommandExecution", "McpToolCall"] {
            assert(TranscriptParser.event(json(["type": "item_completed", "turn_id": "turn-1", "item": ["type": item, "id": "x", "phase": "commentary", "content": [["type": "text", "text": "不应进入上下文"]]]]), sessionID: a) == nil)
        }
        assert(TranscriptParser.event(json(["type": "message", "role": "user", "content": [["type": "input_text", "text": "环境或宿主上下文"]]], type: "response_item"), sessionID: a) == nil)
        assert(TranscriptParser.event("not json", sessionID: a) == nil)
        let source = directory.appendingPathComponent("session.jsonl")
        try Data((user("message-1") + "\n").utf8).write(to: source)
        let tail = SessionTranscript(sessionID: a, url: source)
        assert(tail.read().count == 1 && tail.read().isEmpty)
        let unicode = user("message-2", text: "中文眨眼🙂") + "\n"
        let bytes = Data(unicode.utf8)
        let split = bytes.range(of: Data("🙂".utf8))!.lowerBound + 2
        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd(); try handle.write(contentsOf: bytes.prefix(split))
        assert(tail.read().isEmpty)
        try handle.write(contentsOf: bytes.suffix(bytes.count - split)); try handle.close()
        assert(tail.read().first?.text == "中文眨眼🙂", "Keep partial UTF-8 messages across reads")
        try Data((user("message-3") + "\n").utf8).write(to: source, options: .atomic)
        assert(tail.read().first?.id.hasSuffix("message-3") == true, "Replacement resets transcript cursor")
        print("PASS: desktop route switch/clear, process and window isolation, timestamp ordering, partial lines, message whitelist, steering identity, UTF-8 tail and rotation")
    }
}
