import Foundation

/// Bounded append reader shared by the two local, read-only observation paths.
/// Keeps partial UTF-8 lines and notices file replacement/truncation.
final class JSONLineCursor {
    private let url: URL
    private let initialTail: UInt64
    private var offset: UInt64 = 0
    private var identity: UInt64?
    private var pending = Data()
    private var droppingLine = false
    init(url: URL, initialTail: UInt64 = 4 * 1024 * 1024) { self.url = url; self.initialTail = initialTail }
    func readLines() -> [String] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        if identity != inode || size < offset {
            identity = inode; offset = size > initialTail ? size - initialTail : 0
            pending = Data(); droppingLine = offset > 0
        }
        guard (try? handle.seek(toOffset: offset)) != nil else { return [] }
        var lines: [String] = []
        while offset < size {
            guard let data = try? handle.read(upToCount: Int(min(size - offset, 1024 * 1024))), !data.isEmpty else { break }
            offset += UInt64(data.count)
            pending.append(data)
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                if !droppingLine, let text = String(data: line, encoding: .utf8) { lines.append(text) }
                pending.removeSubrange(...newline); droppingLine = false
            }
            if pending.count > 4 * 1024 * 1024 { pending = Data(); droppingLine = true }
        }
        return lines
    }
}

enum TranscriptParser {
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
    /// Whitelist user-message items and turn-complete events. Never pass tools,
    /// reasoning, commentary, developer messages or environment data to roast.
    static func event(_ line: String, sessionID: String) -> HookEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              let timestamp = object["timestamp"] as? String, let receivedAt = date(timestamp),
              let turn = payload["turn_id"] as? String, !turn.isEmpty,
              payload["thread_id"] == nil || payload["thread_id"] as? String == sessionID else { return nil }
        let kind: String, text: String, eventID: String
        if payload["type"] as? String == "item_completed",
           let item = payload["item"] as? [String: Any], item["type"] as? String == "UserMessage",
           let content = item["content"] as? [[String: Any]], let itemID = item["id"] as? String {
            kind = "UserPromptSubmit"
            eventID = sessionID + ":user:" + itemID
            text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else if payload["type"] as? String == "task_complete", let message = payload["last_agent_message"] as? String {
            kind = "Stop"; text = message; eventID = sessionID + ":" + turn + ":Stop"
        } else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HookEvent(id: eventID, receivedAt: receivedAt, kind: kind,
                         session: sessionID, turn: turn, text: String(trimmed.prefix(2000)), simulated: false)
    }
}

final class SessionTranscript {
    let sessionID: String
    private let cursor: JSONLineCursor
    init(sessionID: String, url: URL) { self.sessionID = sessionID; cursor = JSONLineCursor(url: url) }
    func read() -> [HookEvent] { cursor.readLines().compactMap { TranscriptParser.event($0, sessionID: sessionID) } }
}
