import Foundation

@main struct SessionStoreTests {
    static func main() {
        func event(_ id: String, _ session: String, _ seconds: Double, kind: String = "UserPromptSubmit", simulated: Bool = false) -> HookEvent {
            HookEvent(id: id, receivedAt: Date(timeIntervalSince1970: seconds), kind: kind,
                      session: session, turn: id, text: "message " + id, simulated: simulated)
        }
        let store = SessionStore()
        store.confirmSession("A")
        store.confirmSession("B")
        assert(!store.receive(event("sim", "demo", 0, simulated: true)))
        assert(!store.receive(event("orphan", "A", 0, kind: "Stop")))
        assert(store.selectedID == nil)
        assert(store.receive(event("a1", "A", 1)))
        assert(store.receive(event("b1", "B", 2)))
        assert(store.selectedID == "B")
        assert(!store.receive(event("a-stop", "A", 3, kind: "Stop")))
        assert(store.selectedID == "B" && store.latest?.id == "b1")
        assert(store.history.map(\.id) == ["b1"])
        assert(store.receive(event("b-stop", "B", 4, kind: "Stop")))
        assert(!store.receive(event("b-stop", "B", 4, kind: "Stop")))
        assert(store.history.map(\.id) == ["b1", "b-stop"])
        assert(store.receive(event("a2", "A", 5)))
        assert(store.selectedID == "A")
        assert(store.history.allSatisfy { $0.session == "A" })
        assert(store.history.map(\.id).contains("a1"))
        assert(!store.receive(event("late-old-prompt", "B", 1.5)))
        assert(store.selectedID == "A")
        let restored = SessionStore()
        for e in store.events.reversed() { restored.receive(e) }
        assert(restored.selectedID == nil)
        restored.confirmSession("B")
        restored.confirmSession("A")
        assert(restored.selectedID == "A", "Disk enumeration must not determine selection")
        assert(!store.receive(event("composer-suggestion", "internal-ephemeral", 100)))
        assert(store.selectedID == "A", "App-generated composer suggestions must not switch context")
        let delayed = SessionStore()
        assert(!delayed.receive(event("new-thread", "C", 3)))
        assert(delayed.selectedID == nil)
        delayed.confirmSession("C")
        assert(delayed.selectedID == "C")
        store.updateTitle("Codex 中的真实标题", for: "A")
        assert(store.title(for: "A") == "Codex 中的真实标题")
        store.updateTitle("重命名后的标题", for: "A")
        assert(store.title(for: "A") == "重命名后的标题")
        store.updateTitle(nil, for: "A")
        assert(store.title(for: "A") == "重命名后的标题", "Temporary missing metadata must keep the known title")
        print("PASS: prompt-follow, background reply isolation, context isolation, switch back, out-of-order restore, deduplication, titles")
    }
}
