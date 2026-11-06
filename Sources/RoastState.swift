import Foundation

struct RoastRequest {
    let event: HookEvent
    let context: String
    var key: String { event.deliveryKey }
}

/// The trigger and presentation boundary, shared by AppKit and regression tests.
/// Switching restores cache; only a fresh current-chat message can request work.
final class RoastState {
    let sessions: SessionStore
    let cache: SessionReviews
    private var requested = Set<String>()
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
        let excerpts = sessions.history.suffix(6).map {
            ["role": $0.kind == "Stop" ? "assistant" : "user", "excerpt": String($0.text.prefix(2000))]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: excerpts), let context = String(data: data, encoding: .utf8) else { return nil }
        requested.insert(event.deliveryKey)
        return RoastRequest(event: event, context: context)
    }
    func canStart(_ request: RoastRequest) -> Bool {
        sessions.selectedID == request.event.session
    }
    func complete(_ request: RoastRequest, text: String) throws {
        let value = Self.clean(text)
        guard !value.isEmpty else { return }
        try cache.save(SavedReview(sessionID: request.event.session, mode: "roast", eventID: request.key,
                                   eventDate: request.event.receivedAt, text: value))
    }
    func canPresent(_ request: RoastRequest) -> Bool {
        canStart(request) && sessions.latest?.deliveryKey == request.key
    }
    static func clean(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["吐槽：", "吐槽:"] where value.hasPrefix(prefix) { value = String(value.dropFirst(prefix.count)) }
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    }
}
