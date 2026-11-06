import Foundation

@main struct RoastStateTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SessionReviews(directory: directory)
        let state = RoastState(cache: cache)
        func event(_ id: String, _ session: String, _ seconds: Double, kind: String = "UserPromptSubmit", simulated: Bool = false) -> HookEvent {
            HookEvent(id: id, receivedAt: Date(timeIntervalSince1970: seconds), kind: kind, session: session, turn: id, text: session + " 的 " + id, simulated: simulated)
        }
        state.sessions.select("A")
        assert(state.receive(event("old", "A", 0), live: false) == nil, "Startup history cannot invoke the model")
        assert(state.text == nil, "No cache means no bubble copy")
        let a = state.receive(event("a-user", "A", 1), live: true)!
        assert(a.context.contains("A 的 a-user"))
        assert(state.receive(event("a-user", "A", 1), live: true) == nil)
        state.sessions.select("B")
        assert(!state.canStart(a) && !state.canPresent(a))
        assert(state.receive(event("background-a", "A", 2, kind: "Stop"), live: true) == nil)
        let b = state.receive(event("b-user", "B", 3), live: true)!
        assert(!b.context.contains("A 的"), "Never mix conversations into a model request")
        try state.complete(b, text: "B 的吐槽")
        assert(state.text == "B 的吐槽")
        try state.complete(a, text: "吐槽：A 的吐槽")
        assert(state.text == "B 的吐槽", "Late A completion must not overwrite B")
        state.sessions.select("A")
        assert(state.text == "A 的吐槽", "Click switch restores per-conversation cache without a model call")
        let newer = state.receive(event("a-finish", "A", 4, kind: "Stop"), live: true)!
        assert(!state.canPresent(a) && state.canPresent(newer))
        try state.complete(newer, text: "回复完成后的新吐槽")
        try state.complete(a, text: "过期结果")
        assert(state.text == "回复完成后的新吐槽")
        assert(state.receive(event("sim", "A", 5, simulated: true), live: true) == nil)
        state.paused = true
        assert(state.receive(event("paused", "A", 6), live: true) == nil)
        state.sessions.select(nil)
        assert(state.text == nil)
        let restart = RoastState(cache: SessionReviews(directory: directory))
        restart.sessions.select("A")
        assert(restart.text == "回复完成后的新吐槽", "Cache persists across restart")
        assert(restart.receive(event("a-finish", "A", 4, kind: "Stop"), live: true) == nil, "Cached completion does not spend model usage twice")
        print("PASS: user and completion triggers, startup/background/simulation/pause exclusion, isolated request context, late result guard, cache restore and restart deduplication")
    }
}
