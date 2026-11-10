import AppKit

@main struct ActionLibraryTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gif = directory.appendingPathComponent("source.gif")
        let data = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
        try data.write(to: gif)
        let library = ActionLibrary(directory: directory)
        let first = try library.save(tag: "嫌弃", meaning: "看到用户反复改需求时", gif: gif)
        assert(library.available.count == 1 && library.action(tag: "嫌弃")?.id == first.id)
        try FileManager.default.removeItem(at: gif)
        let imported = try Data(contentsOf: library.url(for: first)!)
        assert(imported == data, "Imported asset must survive deleting the source")
        do { _ = try library.save(tag: "嫌弃", meaning: "重复"); fatalError("Reject duplicate labels") } catch {}
        _ = try library.save(id: first.id, tag: "无语", meaning: "修改了用途")
        assert(library.action(tag: "嫌弃") == nil && library.action(tag: "无语") != nil)
        for index in 0..<130 { _ = try library.save(tag: "自定义\(index)", meaning: "使用场景\(index)") }
        assert(library.actions.count == 131, "No fixed action-count limit")
        let restored = ActionLibrary(directory: directory)
        assert(restored.actions.count == 131 && restored.available.count == 1)
        let file = restored.url(for: restored.actions[0])!
        try restored.delete(id: first.id)
        assert(!FileManager.default.fileExists(atPath: file.path) && restored.available.isEmpty)
        print("PASS: GIF import persistence, duplicate/edit/delete, no action-count cap, missing-asset exclusion")
    }
}
