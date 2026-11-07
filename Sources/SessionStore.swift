import Foundation

struct HookEvent: Codable {
    let id: String
    let receivedAt: Date
    let kind: String
    let session: String
    let turn: String
    let text: String
    let simulated: Bool
}

/// Only the desktop page selector can choose a conversation. Message arrival,
/// metadata lookup and background completion never change this selection.
final class SessionStore {
    private(set) var events: [HookEvent] = []
    private(set) var selectedID: String?
    private var titles: [String: String] = [:]
    var latest: HookEvent? { history.last }
    var history: [HookEvent] {
        events.filter { !$0.simulated && $0.session == selectedID }.sorted { $0.receivedAt < $1.receivedAt }
    }
    @discardableResult func receive(_ event: HookEvent) -> Bool {
        guard !event.simulated, ["UserPromptSubmit", "Stop"].contains(event.kind),
              !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !events.contains(where: { $0.id == event.id || $0.deliveryKey == event.deliveryKey }) else { return false }
        events.append(event)
        // Raw dialogue is a short window, never a growing session archive.
        let ordered = events.filter { $0.session == event.session }.sorted { $0.receivedAt < $1.receivedAt }
        let users = ordered.indices.filter { ordered[$0].kind == "UserPromptSubmit" }
        let start = users.count > 10 ? users[users.count - 10] : 0
        let keep = Set(ordered.dropFirst(start).suffix(40).map(\.id))
        events.removeAll { $0.session == event.session && !keep.contains($0.id) }
        return event.session == selectedID
    }
    @discardableResult func select(_ id: String?) -> Bool {
        guard selectedID != id else { return false }
        selectedID = id
        return true
    }
    func updateTitle(_ title: String?, for id: String) {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = value, !value.isEmpty { titles[id] = value }
    }
    func title(for id: String) -> String {
        titles[id] ?? "未命名会话 · " + String(id.prefix(8))
    }
}

struct ContextMessage: Codable {
    let id: String
    let date: Date
    let speaker: String
    let audience: String
    let text: String
    var startsRound: Bool { speaker == "user" }
}

enum ConversationWindow {
    static let maxRounds = 10
    static func recent(_ messages: [ContextMessage]) -> [ContextMessage] {
        let sorted = messages.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let starts = sorted.indices.filter { sorted[$0].startsRound }
        let start = starts.count > maxRounds ? starts[starts.count - maxRounds] : 0
        return Array(sorted.dropFirst(start).suffix(40))
    }
    // Keep both requirement/premise and conclusion for long messages.
    static func excerpt(_ text: String) -> String {
        guard text.count > 2000 else { return text }
        return String(text.prefix(1190)) + "\n[中段省略]\n" + String(text.suffix(790))
    }
}

extension HookEvent {
    /// A turn may contain several distinct user messages (steering). Preserve
    /// their item IDs; a finish is unique within its turn.
    var deliveryKey: String {
        kind == "UserPromptSubmit" || turn.isEmpty || turn == "unknown" ? id : session + ":" + turn + ":" + kind
    }
}
