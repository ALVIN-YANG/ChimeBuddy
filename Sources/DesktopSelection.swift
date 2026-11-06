import Foundation

struct DesktopPage: Equatable {
    let sessionID: String?
    let windowID: String
    let timestamp: Date
}

/// Version-specific desktop diagnostics adapter. No message text, UI control,
/// IPC injection, or modification of Codex files is involved.
enum DesktopSelectionParser {
    static func parse(_ line: String) -> DesktopPage? {
        guard line.contains("IAB_LIFECYCLE received browser sidebar owner sync") || line.contains("thread_stream_view_activity_changed") else { return nil }
        let fields = Dictionary(line.split(whereSeparator: { $0.isWhitespace }).compactMap { part -> (String, String)? in
            let pair = part.split(separator: "=", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        }, uniquingKeysWith: { _, last in last })
        guard let timestamp = TranscriptParser.date(String(line.prefix(24))) else { return nil }
        if line.contains("IAB_LIFECYCLE received browser sidebar owner sync") {
            guard let route = fields["ownerRoutePath"], let window = fields["windowId"] else { return nil }
            if route == "/" { return DesktopPage(sessionID: nil, windowID: window, timestamp: timestamp) }
            guard route.hasPrefix("/local/"), UUID(uuidString: String(route.dropFirst(7))) != nil else { return nil }
            return DesktopPage(sessionID: String(route.dropFirst(7)), windowID: window, timestamp: timestamp)
        }
        // Some older builds expose explicit focus fields. Current builds omit
        // them, so a bare active=true must NOT override the page route above.
        guard line.contains("thread_stream_view_activity_changed"), fields["active"] == "true",
              fields["rendererWindowFocused"] == "true", fields["rendererWindowVisible"] != "false",
              fields["rendererWindowAppearance"] == "primary",
              let window = fields["rendererWindowId"], let id = fields["conversationId"], UUID(uuidString: id) != nil else { return nil }
        return DesktopPage(sessionID: id, windowID: window, timestamp: timestamp)
    }
}

/// One current desktop process, one primary window. Multiple window routes
/// without explicit focus evidence are ambiguous and produce no selection.
final class DesktopSelectionReader {
    private let root: URL
    private var processID: Int32?
    private var cursors: [URL: JSONLineCursor] = [:]
    private var pages: [String: DesktopPage] = [:]
    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/com.openai.codex")) {
        self.root = root
    }
    func read(processID: Int32?, processStartedAt: Date? = nil) -> DesktopPage? {
        guard let processID = processID else { reset(); return nil }
        if self.processID != processID { reset(); self.processID = processID }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        var additions: [DesktopPage] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "log", file.lastPathComponent.contains("-\(processID)-t0-") else { continue }
            let cursor = cursors[file] ?? JSONLineCursor(url: file, initialTail: 4 * 1024 * 1024)
            cursors[file] = cursor
            additions += cursor.readLines().compactMap(DesktopSelectionParser.parse).filter { page in
                guard let startedAt = processStartedAt else { return true }
                return page.timestamp >= startedAt
            }
        }
        for page in additions.sorted(by: { $0.timestamp < $1.timestamp }) {
            if pages[page.windowID].map({ $0.timestamp <= page.timestamp }) ?? true { pages[page.windowID] = page }
        }
        guard pages.count == 1 else { return nil }
        return pages.values.first
    }
    private func reset() { processID = nil; cursors = [:]; pages = [:] }
}
