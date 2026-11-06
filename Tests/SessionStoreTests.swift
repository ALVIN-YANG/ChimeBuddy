import Foundation

@main struct SessionStoreTests {
    static func main() {
        func event(_ id: String, _ session: String, _ seconds: Double, kind: String = "UserPromptSubmit", simulated: Bool = false) -> HookEvent {
            HookEvent(id: id, receivedAt: Date(timeIntervalSince1970: seconds), kind: kind,
                      session: session, turn: id, text: "message " + id, simulated: simulated)
        }
        let store = SessionStore()
        assert(!store.receive(event("sim", "demo", 0, simulated: true)))
        assert(!store.receive(event("a1", "A", 1)))
        assert(store.selectedID == nil, "Messages cannot choose the desktop page")
        store.select("A")
        assert(store.latest?.id == "a1")
        assert(!store.receive(event("b1", "B", 2)))
        assert(store.selectedID == "A")
        store.select("B")
        assert(store.latest?.id == "b1")
        assert(!store.receive(event("a-stop", "A", 3, kind: "Stop")))
        assert(store.selectedID == "B" && store.latest?.id == "b1")
        assert(store.history.map(\.id) == ["b1"])
        assert(store.receive(event("b-stop", "B", 4, kind: "Stop")))
        assert(!store.receive(event("b-stop", "B", 4, kind: "Stop")))
        assert(store.history.map(\.id) == ["b1", "b-stop"])
        store.select("A")
        assert(store.history.allSatisfy { $0.session == "A" })
        assert(store.history.map(\.id) == ["a1", "a-stop"])
        assert(!store.receive(event("composer-suggestion", "internal-ephemeral", 100)))
        assert(store.selectedID == "A", "App-generated suggestions cannot switch context")
        store.select(nil)
        assert(store.history.isEmpty && store.latest == nil, "Home/unknown selection cannot retain another chat")
        store.updateTitle("Codex 中的真实标题", for: "A")
        assert(store.title(for: "A") == "Codex 中的真实标题")
        store.updateTitle("重命名后的标题", for: "A")
        assert(store.title(for: "A") == "重命名后的标题")
        store.updateTitle(nil, for: "A")
        assert(store.title(for: "A") == "重命名后的标题", "Temporary missing metadata must keep the known title")
        print("PASS: page-owned selection, background isolation, context restore, unknown-page clearing, deduplication, titles")
    }
}
