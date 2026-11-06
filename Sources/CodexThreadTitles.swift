import Foundation

struct CodexThreadTitle {
    let id: String
    let name: String?
    let path: String?
}

/// Reads metadata through the public protocol. Does not resume a conversation,
/// invoke a model, or parse private database files.
enum CodexThreadTitles {
    static func fetch(ids: [String]) throws -> [CodexThreadTitle] {
        guard !ids.isEmpty else { return [] }
        let server = try CodexAppServer(clientName: "chimebuddy_titles")
        var titles: [CodexThreadTitle] = []
        for threadID in ids {
            let result = try? server.call("thread/read", params: ["threadId": threadID, "includeTurns": false])
            // Missing ephemeral/deleted threads do not erase previously read names.
            if let thread = result?["thread"] as? [String: Any] {
                guard thread["id"] as? String == threadID, thread["ephemeral"] as? Bool != true else { continue }
                titles.append(CodexThreadTitle(id: threadID, name: thread["name"] as? String, path: thread["path"] as? String))
            }
        }
        return titles
    }
}
