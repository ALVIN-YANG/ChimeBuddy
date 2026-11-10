import AppKit

@main struct SettingsFlowTests {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = VoicePreferences(directory: directory)
        let controller = SettingsWindowController(actions: ActionLibrary(directory: directory), voice: preferences, preview: true)
        var changed = false; controller.onChange = { changed = true }
        func all(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(all) }
        func find<T: NSView>(_ type: T.Type, label: String, in root: NSView) -> T {
            guard let item = all(root).first(where: { $0 is T && $0.accessibilityLabel() == label }) as? T else { fatalError("Missing accessible control: \(label)") }
            return item
        }
        func click(_ button: NSButton) { _ = NSApp.sendAction(button.action!, to: button.target, from: button) }
        controller.selectPage(1)
        let view = controller.voicePage
        let provider = find(NSPopUpButton.self, label: "TTS 服务商", in: view)
        provider.selectItem(at: TTSProvider.allCases.firstIndex(of: .custom)!)
        _ = NSApp.sendAction(provider.action!, to: provider.target, from: provider)
        let endpoint = find(NSTextField.self, label: "接口地址", in: view)
        endpoint.stringValue = "http://localhost:8000/speech"
        let model = find(NSTextField.self, label: "模型 / 资源 ID", in: view); model.stringValue = "user-local-model"
        let voice = find(NSTextField.self, label: "Voice ID", in: view); voice.stringValue = "user-voice"
        let save = all(view).compactMap { $0 as? NSButton }.first { $0.title == "保存设置" }!
        click(save)
        assert(changed && preferences.value.provider == .custom && preferences.configuration(for: .custom).model == "user-local-model")
        changed = false; endpoint.stringValue = "http://untrusted.example/tts"; click(save)
        assert(!changed && preferences.configuration(for: .custom).endpoint == "http://localhost:8000/speech", "Invalid input cannot replace the working setup")
        endpoint.stringValue = "http://localhost:8000/speech"
        for item in TTSProvider.allCases {
            provider.selectItem(at: TTSProvider.allCases.firstIndex(of: item)!)
            _ = NSApp.sendAction(provider.action!, to: provider.target, from: provider)
            assert(find(NSTextField.self, label: "模型 / 资源 ID", in: view).isEditable)
            assert(find(NSTextField.self, label: "Voice ID", in: view).isEditable)
        }
        provider.selectItem(at: TTSProvider.allCases.firstIndex(of: .custom)!)
        _ = NSApp.sendAction(provider.action!, to: provider.target, from: provider)
        assert(model.stringValue == "user-local-model" && voice.stringValue == "user-voice", "Provider drafts survive switching")
        for index in 0..<3 { controller.selectPage(index) }
        controller.close()
        print("PASS: real settings controls → provider drafts → custom model/voice save → validation → persistence; no user keys touched")
    }
}
