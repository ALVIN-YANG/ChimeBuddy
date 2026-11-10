import AppKit

final class VoiceSettingsView: NSView {
    override var isFlipped: Bool { true }
    let preferences: VoicePreferences
    let audition = StreamingVoice()
    var onChange: (() -> Void)?
    private let providerPicker = NSPopUpButton()
    private let outputPicker = NSPopUpButton()
    private let enabled = NSButton(checkboxWithTitle: "自动朗读新的吐槽和聊天回复", target: nil, action: nil)
    private let endpoint = NSTextField()
    private let model = NSTextField()
    private let voice = NSTextField()
    private let key = NSSecureTextField()
    private let headers = NSTextView()
    private let body = NSTextView()
    private let responsePicker = NSPopUpButton()
    private let ratePicker = NSPopUpButton()
    private let path = NSTextField()
    private let help = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let sample = NSTextField(string: "别光改需求了，先听听我说话。")
    private var provider: TTSProvider
    private var drafts: [TTSProvider: (TTSConfiguration, TTSSecrets)] = [:]
    private var customViews: [NSView] = []
    private var keychainReadable = true
    private let readCredentials: Bool
    private let rates = [8000, 16000, 22050, 24000, 32000, 44100, 48000]

    init(preferences: VoicePreferences, readCredentials: Bool = true) {
        self.readCredentials = readCredentials
        self.preferences = preferences; provider = preferences.value.provider
        super.init(frame: NSRect(x: 0, y: 0, width: SettingsStyle.width, height: 1040))
        SettingsStyle.heading("声音", subtitle: "流式合成，边收边播。朗读的是伙伴的新回复，切回缓存不重播。", in: self)
        enabled.frame = NSRect(x: 28, y: 108, width: 540, height: 25)
        enabled.state = preferences.value.enabled ? .on : .off; addSubview(enabled)
        SettingsStyle.label("声音输出", in: self, y: 148, width: 110)
        outputPicker.frame = NSRect(x: 142, y: 140, width: 376, height: 30)
        outputPicker.setAccessibilityLabel("声音输出设备"); addSubview(outputPicker)
        SettingsStyle.button("", symbol: "arrow.clockwise", in: self, x: 522, y: 140, width: 48, target: self, action: #selector(refreshOutputs))
            .setAccessibilityLabel("刷新声音输出设备")
        reloadOutputs(selected: preferences.value.outputDeviceUID)
        SettingsStyle.label("TTS 单独使用服务商额度；回复模型仍复用 Codex 登录。", in: self, y: 179, size: 11, secondary: true)
        SettingsStyle.divider(in: self, y: 204)
        SettingsStyle.label("服务商", in: self, y: 232, width: 110)
        providerPicker.frame = NSRect(x: 142, y: 224, width: 430, height: 30)
        for item in TTSProvider.allCases { providerPicker.addItem(withTitle: item.title) }
        providerPicker.selectItem(at: TTSProvider.allCases.firstIndex(of: provider)!)
        providerPicker.target = self; providerPicker.action = #selector(changeProvider)
        providerPicker.setAccessibilityLabel("TTS 服务商"); addSubview(providerPicker)
        SettingsStyle.input(endpoint, label: "接口地址", in: self, y: 268)
        SettingsStyle.input(model, label: "模型 / 资源 ID", in: self, y: 308)
        SettingsStyle.input(voice, label: "Voice ID", in: self, y: 348)
        SettingsStyle.input(key, label: "API Key", in: self, y: 388, placeholder: "仅保存在本机钥匙串")
        SettingsStyle.textArea(headers, label: "附加请求头\nJSON", in: self, y: 430, height: 56)
        help.frame = NSRect(x: 28, y: 502, width: 540, height: 38); help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor; addSubview(help)
        SettingsStyle.divider(in: self, y: 554)
        SettingsStyle.input(sample, label: "试听文本", in: self, y: 577)
        SettingsStyle.button("试听", symbol: "play", in: self, x: 142, y: 617, width: 92, target: self, action: #selector(testVoice))
        SettingsStyle.button("停止", symbol: "stop", in: self, x: 240, y: 617, width: 92, target: self, action: #selector(stopVoice))
        SettingsStyle.button("保存设置", symbol: "checkmark", in: self, x: 444, y: 617, width: 128, target: self, action: #selector(save))
        status.frame = NSRect(x: 28, y: 667, width: 540, height: 40); status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; addSubview(status)
        let before = Set(subviews.map(ObjectIdentifier.init))
        SettingsStyle.divider(in: self, y: 714)
        SettingsStyle.label("自定义流格式", in: self, y: 738, weight: .semibold)
        SettingsStyle.label("响应格式", in: self, y: 781, width: 110)
        responsePicker.frame = NSRect(x: 142, y: 773, width: 256, height: 30)
        responsePicker.addItems(withTitles: TTSCustomResponse.allCases.map(\.title)); addSubview(responsePicker)
        SettingsStyle.label("PCM 采样率", in: self, y: 821, width: 110)
        ratePicker.frame = NSRect(x: 142, y: 813, width: 256, height: 30)
        ratePicker.addItems(withTitles: rates.map { "\($0) Hz" }); addSubview(ratePicker)
        SettingsStyle.input(path, label: "音频字段路径", in: self, y: 857, placeholder: "例如 data.audio，仅 SSE 使用")
        SettingsStyle.textArea(body, label: "请求体\nJSON", in: self, y: 899, height: 90)
        customViews = subviews.filter { !before.contains(ObjectIdentifier($0)) }
        audition.onStatus = { [weak self] value in self?.setStatus(value.text) }
        audition.onMetrics = { [weak self] metrics in
            guard metrics["completed"] as? Bool == true else { return }
            self?.setStatus("试听完成 · 首包 \(metrics["firstAudioMs"] ?? 0) ms · \(metrics["audioBytes"] ?? 0) 字节")
        }
        load(provider)
    }
    required init?(coder: NSCoder) { nil }
    func setStatus(_ value: String) { status.stringValue = value }
    private func current() -> (TTSConfiguration, TTSSecrets) {
        var config = TTSConfiguration(endpoint: endpoint.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), model: model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), voice: voice.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        config.sampleRate = rates[max(0, ratePicker.indexOfSelectedItem)]
        config.response = TTSCustomResponse.allCases[max(0, responsePicker.indexOfSelectedItem)]
        config.audioPath = path.stringValue; config.body = body.string
        return (config, TTSSecrets(apiKey: key.stringValue, headers: headers.string))
    }
    private func load(_ provider: TTSProvider) {
        keychainReadable = true
        let config: TTSConfiguration; let secrets: TTSSecrets
        if let draft = drafts[provider] { (config, secrets) = draft }
        else {
            config = preferences.configuration(for: provider)
            do { secrets = readCredentials ? try VoiceKeychain.load(provider) : TTSSecrets() }
            catch { secrets = TTSSecrets(); keychainReadable = false; setStatus(error.localizedDescription) }
        }
        endpoint.stringValue = config.endpoint; model.stringValue = config.model; voice.stringValue = config.voice
        key.stringValue = secrets.apiKey; headers.string = secrets.headers
        responsePicker.selectItem(at: TTSCustomResponse.allCases.firstIndex(of: config.response) ?? 0)
        ratePicker.selectItem(at: rates.firstIndex(of: config.sampleRate) ?? 3)
        path.stringValue = config.audioPath; body.string = config.body
        help.stringValue = provider.help
        for view in customViews { view.isHidden = provider != .custom }
        frame.size.height = provider == .custom ? 1030 : 720
        needsLayout = true; superview?.needsLayout = true
        if keychainReadable { setStatus("更改后点击保存。试听使用当前填写的配置。") }
    }
    @objc private func changeProvider() {
        audition.stop()
        if keychainReadable { drafts[provider] = current() }
        provider = TTSProvider.allCases[providerPicker.indexOfSelectedItem]; load(provider)
    }
    @objc private func testVoice() {
        do {
            let (config, secrets) = current()
            let request = try TTSRequest.build(provider: provider, configuration: config, secrets: secrets, text: sample.stringValue)
            try audition.speak(request, outputDeviceUID: outputPicker.selectedItem?.representedObject as? String)
        } catch { setStatus(error.localizedDescription) }
    }
    @objc private func stopVoice() { audition.stop() }
    @objc private func save() {
        do {
            guard keychainReadable || !key.stringValue.isEmpty else { throw BuddySettingsError.invalid("钥匙串读取失败，请先解锁或重新输入密钥。") }
            let (config, secrets) = current()
            if enabled.state == .on || !secrets.apiKey.isEmpty || provider == .custom { _ = try TTSRequest.build(provider: provider, configuration: config, secrets: secrets, text: "设置检查") }
            // Validate first, so malformed fields never overwrite a working setup.
            if readCredentials { try VoiceKeychain.save(secrets, provider: provider) }
            try preferences.save(provider: provider, configuration: config, enabled: enabled.state == .on, outputDeviceUID: outputPicker.selectedItem?.representedObject as? String)
            drafts[provider] = (config, secrets)
            onChange?(); setStatus("已保存。\(enabled.state == .on ? "新的伙伴回复会自动朗读。" : "自动朗读已关闭，仍可试听。")")
        } catch { setStatus(error.localizedDescription) }
    }
    func stop() { audition.stop() }
    @objc private func refreshOutputs() { reloadOutputs(selected: outputPicker.selectedItem?.representedObject as? String) }
    private func reloadOutputs(selected: String?) {
        outputPicker.removeAllItems()
        guard readCredentials else { outputPicker.addItem(withTitle: "跟随系统"); return }
        outputPicker.addItem(withTitle: "跟随系统 · " + AudioOutputDevices.systemName)
        for device in AudioOutputDevices.list() {
            outputPicker.addItem(withTitle: device.name); outputPicker.lastItem?.representedObject = device.uid
        }
        if let selected = selected {
            if let item = outputPicker.itemArray.first(where: { $0.representedObject as? String == selected }) { outputPicker.select(item) }
            else { outputPicker.addItem(withTitle: "所选设备已断开"); outputPicker.lastItem?.representedObject = selected; outputPicker.select(outputPicker.lastItem) }
        }
    }
}
