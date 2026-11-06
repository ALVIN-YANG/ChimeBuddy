import Foundation

@main struct SessionStoreTests {
    static func main() {
        func event(_ id: String, _ session: String, _ seconds: Double, simulated: Bool = false) -> HookEvent {
            HookEvent(id: id, receivedAt: Date(timeIntervalSince1970: seconds), kind: "UserPromptSubmit",
                      session: session, turn: id, text: "message " + id, simulated: simulated)
        }
        let store = SessionStore()
        assert(!store.receive(event("sim", "demo", 0, simulated: true)))
        assert(store.selectedID == nil && store.sessions.isEmpty)
        assert(store.receive(event("a1", "A", 1)))
        assert(!store.receive(event("b1", "B", 2)))
        assert(store.selectedID == "A" && store.latest?.id == "a1")
        store.select("B")
        assert(store.latest?.id == "b1")
        assert(!store.receive(event("a2", "A", 3)))
        assert(store.latest?.id == "b1")
        assert(store.receive(event("b2", "B", 4)))
        assert(!store.receive(event("b2", "B", 4)))
        assert(store.history.map(\.id) == ["b1", "b2"])
        assert(store.sessions == ["A", "B"])
        store.updateTitle("Codex 中的真实标题", for: "A")
        assert(store.title(for: "A") == "Codex 中的真实标题")
        store.updateTitle("重命名后的标题", for: "A")
        assert(store.title(for: "A") == "重命名后的标题")
        assert(store.selectedID == "B")
        store.updateTitle(nil, for: "A")
        assert(store.title(for: "A") == "未命名会话 · A")
        assert(store.title(for: "B") == "未命名会话 · B")
        print("PASS: simulated isolation, selection, background isolation, history isolation, deduplication")
    }
}
