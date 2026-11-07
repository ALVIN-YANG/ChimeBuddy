import Foundation

@main struct SharedMemoryTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let memory = SharedMemory(directory: directory)
        let generation = memory.editGeneration
        func source(_ seconds: Double, kind: String = "UserPromptSubmit", simulated: Bool = false) -> HookEvent {
            HookEvent(id: UUID().uuidString, receivedAt: Date(timeIntervalSince1970: seconds), kind: kind, session: "any-chat", turn: "turn", text: "用户明确表达的偏好", simulated: simulated)
        }
        func answer(_ value: String) -> BuddyAnswer {
            BuddyAnswer(text: "这句不会变成记忆", profileUpdates: [MemoryFact(key: "语言", value: value)],
                        projectUpdates: [MemoryFact(key: "ChimeBuddy", value: "原生 Swift 伙伴")])
        }
        try memory.apply(answer("不能从 AI 提取"), source: source(3, kind: "Stop"), generation: generation)
        try memory.apply(answer("不能从模拟事件提取"), source: source(3, simulated: true), generation: generation)
        assert(memory.snapshot.profile.isEmpty && memory.snapshot.projects.isEmpty)
        try memory.apply(answer("中文"), source: source(2), generation: generation)
        try memory.apply(answer("过期偏好"), source: source(1), generation: generation)
        assert(memory.snapshot.profileText == "语言：中文", "Out-of-order extraction cannot revert a fact")
        assert(!memory.snapshot.profileText.contains("这句"))
        let restored = SharedMemory(directory: directory)
        assert(restored.snapshot.profileText == memory.snapshot.profileText)
        assert(restored.snapshot.projectsText.contains("ChimeBuddy"), "Shared facts survive restart without session IDs")
        let huge = (0..<100).map { MemoryFact(key: "项目\($0)", value: String(repeating: "长", count: 500)) }
        for index in 0..<20 {
            try memory.apply(BuddyAnswer(text: "", profileUpdates: [huge[index]], projectUpdates: [huge[index]]), source: source(Double(index + 4)), generation: generation)
        }
        assert(memory.snapshot.profileText.count <= 400 && memory.snapshot.projectsText.count <= 800)
        assert(!memory.snapshot.profile.contains { $0.key == "项目0" } && memory.snapshot.profile.contains { $0.key == "项目19" }, "Older facts must be evicted instead of allowing a growing profile")
        try memory.replace(profile: "", projects: "")
        try memory.apply(answer("不该复活"), source: source(5), generation: generation)
        assert(memory.snapshot.profileText.isEmpty && memory.snapshot.projectsText.isEmpty, "An in-flight response cannot undo manual clearing")
        do { try memory.replace(profile: String(repeating: "字", count: 401), projects: ""); assertionFailure("Reject oversized manual edits") }
        catch {}
        try memory.replace(profile: "偏好：直说\n工具：Swift", projects: "ChimeBuddy：桌面伙伴")
        assert(memory.snapshot.profileText.contains("工具：Swift"))
        try memory.replace(profile: "备注：" + String(repeating: "长", count: 350), projects: "")
        assert(memory.snapshot.profileText.count == 353, "A valid manual edit is not silently cut to the extraction item limit")
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("shared-memory.json").path)
        assert((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        print("PASS: bounded shared facts, persistence, ordering, manual edit/clear, no resurrection and private file permissions")
    }
}
