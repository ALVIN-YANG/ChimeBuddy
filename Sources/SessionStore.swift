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

extension HookEvent {
    /// A turn may contain several distinct user messages (steering). Preserve
    /// their item IDs; a finish is unique within its turn.
    var deliveryKey: String {
        kind == "UserPromptSubmit" || turn.isEmpty || turn == "unknown" ? id : session + ":" + turn + ":" + kind
    }
}
