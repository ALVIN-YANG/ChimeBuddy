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

/// Follow the latest user submission, never a background assistant reply.
final class SessionStore {
    private(set) var events: [HookEvent] = []
    private(set) var selectedID: String?
    private var titles: [String: String] = [:]
    private var latestPrompt: HookEvent?
    private var verifiedSessions = Set<String>()
    var sessions: [String] { Array(Set(events.filter { !$0.simulated }.map { $0.session })).sorted() }
    var latest: HookEvent? { history.last }
    var history: [HookEvent] {
        events.filter { !$0.simulated && $0.session == selectedID }.sorted { $0.receivedAt < $1.receivedAt }
    }
    @discardableResult func receive(_ event: HookEvent) -> Bool {
        guard !events.contains(where: { $0.id == event.id }) else { return false }
        events.append(event)
        if !event.simulated && event.kind == "UserPromptSubmit" && verifiedSessions.contains(event.session) {
            if latestPrompt == nil || event.receivedAt > latestPrompt!.receivedAt ||
                (event.receivedAt == latestPrompt!.receivedAt && event.id > latestPrompt!.id) {
                latestPrompt = event
                selectedID = event.session
            }
        }
        return !event.simulated && event.session == selectedID
    }
    /// Called only after thread/read returns real thread metadata. The desktop
    /// also emits UserPromptSubmit for ephemeral composer prediction requests.
    func confirmSession(_ id: String) {
        verifiedSessions.insert(id)
        latestPrompt = events.filter {
            !$0.simulated && $0.kind == "UserPromptSubmit" && verifiedSessions.contains($0.session)
        }.max {
            $0.receivedAt == $1.receivedAt ? $0.id < $1.id : $0.receivedAt < $1.receivedAt
        }
        selectedID = latestPrompt?.session
    }
    func updateTitle(_ title: String?, for id: String) {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        titles[id] = value?.isEmpty == false ? value : nil
    }
    func title(for id: String) -> String {
        titles[id] ?? "未命名会话 · " + String(id.prefix(8))
    }
}
