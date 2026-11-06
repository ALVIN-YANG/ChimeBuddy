import Foundation

enum CodexModelCatalog {
    private struct Page: Decodable {
        let data: [CodexModel]
        let nextCursor: String?
    }
    static func fetch() throws -> [CodexModel] {
        let server = try CodexAppServer(clientName: "chimebuddy_models")
        var models: [CodexModel] = [], cursor: String?, visited = Set<String>()
        repeat {
            var params: [String: Any] = ["limit": 100, "includeHidden": false]
            if let cursor = cursor { params["cursor"] = cursor }
            let result = try server.call("model/list", params: params)
            let data = try JSONSerialization.data(withJSONObject: result)
            let page = try JSONDecoder().decode(Page.self, from: data)
            models += page.data.filter { $0.hidden != true && ($0.inputModalities?.contains("text") ?? true) }
            cursor = page.nextCursor
            if let cursor = cursor, !visited.insert(cursor).inserted {
                throw NSError(domain: "ChimeBuddy", code: 7, userInfo: [NSLocalizedDescriptionKey: "Codex 模型列表分页异常"])
            }
        } while cursor != nil
        guard !models.isEmpty else {
            throw NSError(domain: "ChimeBuddy", code: 8, userInfo: [NSLocalizedDescriptionKey: "Codex 没有返回可用的文本模型"])
        }
        return models
    }
}
