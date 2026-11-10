import AppKit

/// One real Codex structured reply, then the same production GIF resolver used
/// by the app. Isolated memory/cache/assets; no paid TTS call in this probe.
@main struct ProbeActions {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chimebuddy-actions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gif = directory.appendingPathComponent("fixture.gif")
        try Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!.write(to: gif)
        let library = ActionLibrary(directory: directory)
        _ = try library.save(tag: "得意", meaning: "用户明确要求“得意”动作时使用", gif: gif)
        let state = RoastState(cache: SessionReviews(directory: directory))
        state.sessions.select("fixture-A")
        let request = state.reply("给我一句得意的回应，这次动作标签请选“得意”。", sessionID: "fixture-A")!
        let answer = try CodexReviewer.respond(context: request.context, direct: true, memory: MemorySnapshot(), actions: Dictionary(uniqueKeysWithValues: library.available.map { ($0.tag, $0.meaning) }))
        guard answer.action == "得意", !answer.text.contains("[得意]") else { throw BuddySettingsError.invalid("模型没有按约定返回独立动作标签。") }
        try state.complete(request, text: answer.text, action: answer.action)
        let avatar = CompanionAvatarView()
        let performance = CompanionPerformance(avatar: avatar, library: library, preferences: VoicePreferences(directory: directory))
        var restores = 0
        performance.restoreAvatar = { avatar.image = nil; restores += 1 }
        performance.play(text: answer.text, action: answer.action)
        assert(avatar.image != nil)
        state.sessions.select("fixture-B")
        performance.cancel()
        assert(!state.canPresent(request) && avatar.image == nil && restores == 1)
        assert(state.text == nil)
        state.sessions.select("fixture-A")
        assert(state.text == answer.text && SessionReviews(directory: directory).review(sessionID: "fixture-A", mode: "roast")?.action == answer.action)
        print("model text: \(answer.text)")
        print("model action: \(answer.action!)")
        print("PASS: real AI action → imported GIF → cancel on chat switch → isolated text/action cache")
    }
}
