import Foundation

/// Explicit live-model smoke test. All memories/caches are isolated and deleted;
/// no test profile or message is written into Codex or the installed buddy data.
@main struct ProbeBuddy {
    static func main() {
        do { try probe() }
        catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func probe() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chimebuddy-smoke-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let memory = SharedMemory(directory: directory)
        let state = RoastState(cache: SessionReviews(directory: directory))
        state.sessions.select("test-A")
        let text = "我在做 ChimeBuddy 原生 Swift 桌面伙伴，界面尽量简单。我喜欢直接说重点。这轮测试临时暗号是蓝色纸箱。"
        let event = HookEvent(id: "test-user", receivedAt: Date(), kind: "UserPromptSubmit", session: "test-A", turn: "test-turn", text: text, simulated: false)
        let first = state.receive(event, live: true)!
        let result = try CodexReviewer.respond(context: first.context, direct: false, memory: memory.snapshot)
        try memory.apply(result, source: event, generation: memory.editGeneration)
        try state.complete(first, text: result.text)
        print("A: \(result.text.isEmpty ? "[安静]" : result.text)"); fflush(stdout)
        guard !memory.snapshot.profile.isEmpty, !memory.snapshot.projects.isEmpty,
              !memory.snapshot.profileText.contains("蓝色纸箱"), !memory.snapshot.projectsText.contains("蓝色纸箱") else {
            fatalError("Extraction must retain useful facts, not a temporary dialogue detail")
        }
        print("shared: \(memory.snapshot.profileText) / \(memory.snapshot.projectsText)"); fflush(stdout)
        state.sessions.select("test-B")
        let second = state.reply("你知道我在做什么、喜欢怎样交流吗？", sessionID: "test-B")!
        assert(!second.context.contains("蓝色纸箱") && !second.context.contains("test-A"))
        let reply = try CodexReviewer.respond(context: second.context, direct: true, memory: memory.snapshot)
        try state.complete(second, text: reply.text)
        print("B: \(reply.text)"); fflush(stdout)
        let third = state.reply("你懂个屁，这次骂错了，正常需求也要硬挑刺？", sessionID: "test-B")!
        let backtalk = try CodexReviewer.respond(context: third.context, direct: true, memory: memory.snapshot)
        try state.complete(third, text: backtalk.text)
        print("backtalk: \(backtalk.text)")
        assert(state.buddyMessages(sessionID: "test-B").filter { $0.speaker == "user" }.count == 2)
        print("PASS: real structured output, shared concise facts, no cross-chat quotations, explicit buddy replies and backtalk")
    }
}
