import AppKit
import ImageIO

struct BuddyAction: Codable, Equatable {
    var id = UUID()
    var tag: String
    var meaning: String
    var file: String?
}

/// User-owned assets are copied into application storage, independent of the
/// original download. No fixed limit on the number of actions.
final class ActionLibrary {
    let directory: URL
    private(set) var actions: [BuddyAction] = []
    var available: [BuddyAction] { actions.filter { url(for: $0) != nil } }
    init(directory: URL) {
        self.directory = directory.appendingPathComponent("actions", isDirectory: true)
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("index.json")),
           let values = try? JSONDecoder().decode([BuddyAction].self, from: data) { actions = values }
    }
    func url(for action: BuddyAction) -> URL? {
        guard let name = action.file, name == URL(fileURLWithPath: name).lastPathComponent,
              name.hasSuffix(".gif") else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func action(tag: String?) -> BuddyAction? { available.first { $0.tag == tag } }
    @discardableResult func save(id: UUID? = nil, tag: String, meaning: String, gif: URL? = nil) throws -> BuddyAction {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, tag.count <= 64, !tag.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue! < 32 }),
              !meaning.isEmpty, meaning.count <= 240 else { throw BuddySettingsError.invalid("标签需为 1–64 字，用途需为 1–240 字。") }
        guard !actions.contains(where: { $0.id != id && $0.tag.caseInsensitiveCompare(tag) == .orderedSame }) else {
            throw BuddySettingsError.invalid("这个标签已存在，请使用其他名字。")
        }
        var value = actions.first { $0.id == id } ?? BuddyAction(tag: tag, meaning: meaning)
        value.tag = tag; value.meaning = meaning
        let oldFile = value.file
        if let gif = gif {
            let data = try Self.gifData(at: gif)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            value.file = UUID().uuidString + ".gif"
            try data.write(to: directory.appendingPathComponent(value.file!), options: .atomic)
        }
        var updated = actions
        if let index = updated.firstIndex(where: { $0.id == value.id }) { updated[index] = value }
        else { updated.append(value) }
        do { try persist(updated) }
        catch { if value.file != oldFile, let file = value.file { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file)) }; throw error }
        if oldFile != value.file, let file = oldFile { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file)) }
        return value
    }
    func delete(id: UUID) throws {
        let old = actions.first { $0.id == id }
        try persist(actions.filter { $0.id != id })
        if let old = old, let url = url(for: old) { try? FileManager.default.removeItem(at: url) }
    }
    private func persist(_ values: [BuddyAction]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("index.json")
        try JSONEncoder().encode(values).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        actions = values
    }
    static func gifData(at url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 20_000_000 else { throw BuddySettingsError.invalid("请选择不超过 20 MB 的 GIF。") }
        let data = try Data(contentsOf: url)
        guard data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)),
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              let image = NSImage(data: data), image.isValid else { throw BuddySettingsError.invalid("GIF 无法读取，或尺寸超过 4096 × 4096。") }
        return data
    }
}

enum BuddySettingsError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let value) = self { return value }; return nil }
}
