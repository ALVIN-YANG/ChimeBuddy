import Foundation

struct CodexReasoningEffort: Decodable {
    let reasoningEffort: String
    let description: String?
    var title: String {
        let names = ["none": "无", "minimal": "最少", "low": "低", "medium": "中", "high": "高", "xhigh": "超高", "max": "最大", "ultra": "极限"]
        return names[reasoningEffort].map { $0 + "（" + reasoningEffort + "）" } ?? reasoningEffort
    }
}

struct CodexModel: Decodable {
    let id: String
    let model: String
    var displayName: String?
    var hidden: Bool?
    var supportedReasoningEfforts: [CodexReasoningEffort]?
    var defaultReasoningEffort: String?
    var inputModalities: [String]?
    var isDefault: Bool?
    var title: String { displayName ?? model }
    var efforts: [CodexReasoningEffort] { supportedReasoningEfforts ?? [] }
    func selection(effort: String? = nil) -> CodexModelSelection {
        let allowed = efforts.map(\.reasoningEffort)
        let value = [effort, defaultReasoningEffort].compactMap { $0 }.first { allowed.contains($0) } ?? allowed.first
        return CodexModelSelection(model: model, effort: value)
    }
}

struct CodexModelSelection: Codable, Equatable {
    let model: String
    let effort: String?
    var arguments: [String] {
        var values = ["--model", model]
        if let effort = effort, let data = try? JSONEncoder().encode(effort), let literal = String(data: data, encoding: .utf8) {
            values += ["-c", "model_reasoning_effort=" + literal]
        }
        return values
    }
}

enum CodexModelPreferences {
    static let key = "roastModelSelection"
    static let store = UserDefaults(suiteName: "dev.chimebuddy.prototype") ?? .standard
    static func load(from defaults: UserDefaults = CodexModelPreferences.store) -> CodexModelSelection? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CodexModelSelection.self, from: data)
    }
    static func save(_ selection: CodexModelSelection, to defaults: UserDefaults = CodexModelPreferences.store) {
        if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: key) }
    }
}
