import Foundation

struct RoastRequest {
    let event: HookEvent
    let context: String
    var direct = false
    var key: String { event.deliveryKey }
}

/// The trigger and presentation boundary, shared by AppKit and regression tests.
/// Switching restores cache; only a fresh current-chat message can request work.
final class RoastState {
    let sessions: SessionStore
    let cache: SessionReviews
    private var requested = Set<String>()
    private var dialogue: [String: [ContextMessage]] = [:]
    private var latestRequest: [String: String] = [:]
    init(sessions: SessionStore = SessionStore(), cache: SessionReviews) { self.sessions = sessions; self.cache = cache }
    var text: String? {
        guard let id = sessions.selectedID, let saved = cache.review(sessionID: id, mode: "roast") else { return nil }
        return Self.clean(saved.text)
    }
    func receive(_ event: HookEvent, live: Bool) -> RoastRequest? {
        guard sessions.receive(event), live,
              !requested.contains(event.deliveryKey),
              cache.review(sessionID: event.session, mode: "roast")?.eventID != event.deliveryKey else { return nil }
        // Do not request a stale boundary delivered after a newer user/finish.
        guard sessions.latest?.deliveryKey == event.deliveryKey else { return nil }
        requested.insert(event.deliveryKey)
        return request(event, direct: false)
    }
    func reply(_ text: String, sessionID: String) -> RoastRequest? {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard sessions.selectedID == sessionID, !text.isEmpty else { return nil }
        let event = HookEvent(id: UUID().uuidString, receivedAt: Date(), kind: "BuddyReply", session: sessionID,
                              turn: "", text: text, simulated: false)
        // A reply explicitly targets the visible cached line, even after restart.
        if buddyMessages(sessionID: sessionID).isEmpty, let cached = self.text {
            dialogue[sessionID, default: []].append(ContextMessage(id: "reply-target:" + event.id,
                date: event.receivedAt.addingTimeInterval(-0.001), speaker: "buddy", audience: "user", text: cached))
        }
        dialogue[sessionID, default: []].append(ContextMessage(id: event.id, date: event.receivedAt, speaker: "user", audience: "buddy", text: text))
        return request(event, direct: true)
    }
    func messages(sessionID: String) -> [ContextMessage] {
        guard sessions.selectedID == sessionID else { return [] }
        let codex = sessions.history.map {
            ContextMessage(id: $0.id, date: $0.receivedAt, speaker: $0.kind == "Stop" ? "codex" : "user",
                           audience: $0.kind == "Stop" ? "user" : "codex", text: ConversationWindow.excerpt($0.text))
        }
        return ConversationWindow.recent(codex + (dialogue[sessionID] ?? []))
    }
    func buddyMessages(sessionID: String) -> [ContextMessage] {
        messages(sessionID: sessionID).filter { $0.speaker == "buddy" || $0.audience == "buddy" }
    }
    private func request(_ event: HookEvent, direct: Bool) -> RoastRequest? {
        let messages = messages(sessionID: event.session)
        let retained = Set(messages.map(\.id))
        dialogue[event.session] = (dialogue[event.session] ?? []).filter { retained.contains($0.id) }
        let quoted: [String: Any] = ["messages": messages.map {
            ["speaker": $0.speaker, "audience": $0.audience, "text": $0.text]
        }, "trigger": direct ? "user_to_buddy" : event.kind, "currentMessage": event.text,
           "replyingTo": direct ? (text ?? "") : ""]
        guard let data = try? JSONSerialization.data(withJSONObject: quoted), let context = String(data: data, encoding: .utf8) else { return nil }
        latestRequest[event.session] = event.deliveryKey
        return RoastRequest(event: event, context: context, direct: direct)
    }
    func canStart(_ request: RoastRequest) -> Bool {
        sessions.selectedID == request.event.session
    }
    func complete(_ request: RoastRequest, text: String) throws {
        let value = Self.clean(text)
        guard !value.isEmpty else { return }
        try cache.save(SavedReview(sessionID: request.event.session, mode: "roast", eventID: request.key,
                                   eventDate: request.event.receivedAt, text: value))
        let directStillInWindow = request.direct && canStart(request) && messages(sessionID: request.event.session).contains { $0.id == request.event.id }
        if canPresent(request) || directStillInWindow {
            dialogue[request.event.session, default: []].append(ContextMessage(id: "buddy:" + request.key, date: Date(), speaker: "buddy", audience: "user", text: value))
            let retained = Set(messages(sessionID: request.event.session).map(\.id))
            dialogue[request.event.session]?.removeAll { !retained.contains($0.id) }
        }
    }
    func canPresent(_ request: RoastRequest) -> Bool {
        canStart(request) && latestRequest[request.event.session] == request.key
    }
    static func clean(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["吐槽：", "吐槽:"] where value.hasPrefix(prefix) { value = String(value.dropFirst(prefix.count)) }
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    }
}
