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

/// Selection is explicit. Background events never change the selected session.
final class SessionStore {
    private(set) var events: [HookEvent] = []
    private(set) var selectedID: String?
    init(selectedID: String? = nil) { self.selectedID = selectedID }
    var sessions: [String] { Array(Set(events.filter { !$0.simulated }.map { $0.session })).sorted() }
    var latest: HookEvent? { history.last }
    var history: [HookEvent] {
        events.filter { !$0.simulated && $0.session == selectedID }.sorted { $0.receivedAt < $1.receivedAt }
    }
    @discardableResult func receive(_ event: HookEvent) -> Bool {
        guard !events.contains(where: { $0.id == event.id }) else { return false }
        events.append(event)
        if selectedID == nil && !event.simulated { selectedID = event.session }
        return !event.simulated && event.session == selectedID
    }
    func select(_ id: String) { selectedID = id }
    func title(for id: String) -> String {
        let first = events.filter { !$0.simulated && $0.session == id && $0.kind == "UserPromptSubmit" }
            .sorted { $0.receivedAt < $1.receivedAt }.first
        let text = first?.text.replacingOccurrences(of: "\n", with: " ") ?? "未收到用户消息"
        return String(text.prefix(16)) + " · " + String(id.prefix(8))
    }
}
