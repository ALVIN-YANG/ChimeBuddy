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
        try state.complete(b, text: "B 的吐槽", action: "得意")
        assert(state.text == "B 的吐槽")
        assert(SessionReviews(directory: directory).review(sessionID: "B", mode: "roast")?.action == "得意")
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
        state.sessions.select(nil)
        assert(state.text == nil)
        let restart = RoastState(cache: SessionReviews(directory: directory))
        restart.sessions.select("A")
        assert(restart.text == "回复完成后的新吐槽", "Cache persists across restart")
        assert(restart.receive(event("a-finish", "A", 4, kind: "Stop"), live: true) == nil, "Cached completion does not spend model usage twice")
        assert(restart.buddyMessages(sessionID: "A").isEmpty, "No buddy dialogue archive is loaded from disk")
        let backtalk = restart.reply("你这次骂错了", sessionID: "A")!
        assert(backtalk.direct && backtalk.context.contains("user_to_buddy") && backtalk.context.contains("回复完成后的新吐槽"))
        try restart.complete(backtalk, text: "行，这次嘴快了。")
        assert(restart.buddyMessages(sessionID: "A").last?.speaker == "buddy")
        restart.sessions.select("B")
        assert(restart.reply("不能发到 A", sessionID: "A") == nil && !restart.canPresent(backtalk))
        let isolated = restart.receive(event("b-new", "B", Date().timeIntervalSince1970), live: true)!
        assert(!isolated.context.contains("骂错了") && !isolated.context.contains("嘴快了"))
        let window = RoastState(cache: SessionReviews(directory: directory.appendingPathComponent("window")))
        window.sessions.select("C")
        for index in 0..<15 {
            _ = window.receive(event("round-\(index)", "C", Double(index * 2)), live: false)
            _ = window.receive(event("finish-\(index)", "C", Double(index * 2 + 1), kind: "Stop"), live: false)
        }
        let messages = window.messages(sessionID: "C")
        assert(messages.filter(\.startsRound).count == 10 && messages.count == 20)
        assert(!messages.contains { $0.text.contains("round-4") })
        for _ in 0..<12 { _ = window.reply("只在当前会话回怼", sessionID: "C") }
        assert(window.messages(sessionID: "C").filter(\.startsRound).count == 10, "Codex and buddy share one ten-round budget")
        assert(!window.messages(sessionID: "C").contains { $0.speaker == "codex" }, "Older source messages fall out when buddy rounds advance")
        let expired = window.reply("这句很快会退出窗口", sessionID: "C")!
        for _ in 0..<10 { _ = window.reply("推进窗口", sessionID: "C") }
        try window.complete(expired, text: "不能复活的过期回复")
        assert(!window.messages(sessionID: "C").contains { $0.text == "不能复活的过期回复" })
        let long = "开头要求" + String(repeating: "中", count: 3000) + "最终结论"
        let excerpt = ConversationWindow.excerpt(long)
        assert(excerpt.count <= 2000 && excerpt.hasPrefix("开头要求") && excerpt.hasSuffix("最终结论"))
        let fullReply = String(repeating: "完整的回复不应该在字符边界被截断。", count: 10) + "这里才是结尾。"
        let fullRequest = window.reply("说完整", sessionID: "C")!
        try window.complete(fullRequest, text: fullReply)
        assert(window.text == fullReply && SessionReviews(directory: directory.appendingPathComponent("window")).review(sessionID: "C", mode: "roast")?.text == fullReply)
        print("PASS: user and completion triggers, startup/background/simulation exclusion, isolated request context, late result guard, cache restore and restart deduplication")
    }
}
