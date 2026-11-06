import Foundation

@main struct ModelPreferencesTests {
    static func main() throws {
        let json = """
        {"id":"test-model","model":"test-model","displayName":"Test Model","supportedReasoningEfforts":[{"reasoningEffort":"low","description":"quick"},{"reasoningEffort":"high"}],"defaultReasoningEffort":"low"}
        """
        let model = try JSONDecoder().decode(CodexModel.self, from: Data(json.utf8))
        assert(model.selection().effort == "low")
        assert(model.selection(effort: "high").effort == "high")
        assert(model.selection(effort: "ultra").effort == "low", "Unsupported effort resets to this model's advertised default")
        let noEffort = try JSONDecoder().decode(CodexModel.self, from: Data("{\"id\":\"plain\",\"model\":\"plain\"}".utf8))
        assert(noEffort.selection(effort: "high").effort == nil)
        assert(noEffort.selection().arguments == ["--model", "plain"], "Do not send an effort override to a model with no effort options")
        assert(model.selection(effort: "high").arguments == ["--model", "test-model", "-c", "model_reasoning_effort=\"high\""])
        let unusual = CodexModelSelection(model: "model name", effort: "value\"\nnext")
        let literal = String(unusual.arguments.last!.dropFirst("model_reasoning_effort=".count))
        let decoded = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
        assert(decoded == unusual.effort, "Quote the config value as data, not shell text")
        let suite = "ChimeBuddyTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        assert(CodexModelPreferences.load(from: defaults) == nil)
        let choice = model.selection(effort: "high")
        CodexModelPreferences.save(choice, to: defaults)
        assert(CodexModelPreferences.load(from: defaults) == choice)
        let reopened = UserDefaults(suiteName: suite)!
        assert(CodexModelPreferences.load(from: reopened) == choice)
        defaults.set(Data("broken".utf8), forKey: CodexModelPreferences.key)
        assert(CodexModelPreferences.load(from: defaults) == nil)
        print("PASS: model-specific efforts, default resolution, no-effort model, CLI overrides and quoting, saved selection restore and corrupt preference handling")
    }
}
