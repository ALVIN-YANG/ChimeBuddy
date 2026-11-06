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
    private var titles: [String: String] = [:]
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
    func updateTitle(_ title: String?, for id: String) {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        titles[id] = value?.isEmpty == false ? value : nil
    }
    func title(for id: String) -> String {
        titles[id] ?? "未命名会话 · " + String(id.prefix(8))
    }
}
