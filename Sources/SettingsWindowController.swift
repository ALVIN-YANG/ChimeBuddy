import AppKit

/// Codex-like utility settings: quiet sidebar, monochrome line symbols,
/// one content column, native controls, and scrollable detail panes.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let actionPage: ActionSettingsView
    let voicePage: VoiceSettingsView
    private let root = SettingsCanvas()
    private let sidebar = SettingsCanvas()
    private let scroll = NSScrollView()
    private let modelPage = SettingsCanvas()
    private let modelPicker = NSPopUpButton()
    private let effortPicker = NSPopUpButton()
    private let refreshButton = NSButton()
    private let modelHint = NSTextField(wrappingLabelWithString: "")
    private var models: [CodexModel] = []
    private var loading = false
    private var navigation: [NSButton] = []
    var onImport: (() -> Void)? { didSet { actionPage.onImport = onImport } }
    var onReset: (() -> Void)? { didSet { actionPage.onReset = onReset } }
    var onMemory: (() -> Void)?
    var onChange: (() -> Void)? {
        didSet { actionPage.onChange = onChange; voicePage.onChange = onChange }
    }

    init(actions: ActionLibrary, voice: VoicePreferences, preview: Bool = false) {
        actionPage = ActionSettingsView(library: actions)
        voicePage = VoiceSettingsView(preferences: voice, readCredentials: !preview)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "ChimeBuddy 设置"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        root.frame = window.contentView!.bounds; window.contentView = root
        sidebar.frame = NSRect(x: 0, y: 0, width: 184, height: 720); sidebar.sidebar = true; root.addSubview(sidebar)
        SettingsStyle.label("设置", in: sidebar, x: 18, y: 22, width: 150, size: 13, secondary: true, weight: .medium)
        for (index, item) in [("形象与动作", "face.smiling"), ("声音", "waveform"), ("模型与记忆", "slider.horizontal.3")].enumerated() {
            let button = SettingsNavigationButton(title: item.0, target: self, action: #selector(navigate(_:)))
            button.image = NSImage(systemSymbolName: item.1, accessibilityDescription: nil)
            button.imagePosition = .imageLeading; button.image?.isTemplate = true
            button.isBordered = false; button.setButtonType(.momentaryChange)
            button.alignment = .left; button.font = .systemFont(ofSize: 13)
            button.frame = NSRect(x: 12, y: 64 + CGFloat(index) * 42, width: 160, height: 34)
            button.tag = index; button.setAccessibilityLabel(item.0)
            sidebar.addSubview(button); navigation.append(button)
        }
        SettingsStyle.label("ChimeBuddy", in: sidebar, x: 18, y: 665, width: 150, size: 11, secondary: true)
        scroll.frame = NSRect(x: 184, y: 0, width: 596, height: 720)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        root.addSubview(scroll)
        buildModelPage()
        selectPage(0); window.center()
    }
    required init?(coder: NSCoder) { nil }
    func update(customURL: URL) { actionPage.update(customURL: customURL) }
    func setVoiceStatus(_ value: String) { voicePage.setStatus(value) }
    func windowWillClose(_ notification: Notification) { voicePage.stop() }
    func selectPage(_ index: Int) {
        voicePage.stop()
        for button in navigation { button.state = button.tag == index ? .on : .off; button.needsDisplay = true }
        scroll.documentView = index == 0 ? actionPage : index == 1 ? voicePage : modelPage
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    }
    @objc private func navigate(_ sender: NSButton) { selectPage(sender.tag) }
    @objc private func openMemory() { onMemory?() }
    private func buildModelPage() {
        modelPage.frame = NSRect(x: 0, y: 0, width: 596, height: 654)
        SettingsStyle.heading("模型与记忆", subtitle: "回复模型复用 Codex 登录。可用模型和推理档位从 Codex 实时读取。", in: modelPage)
        SettingsStyle.label("模型", in: modelPage, y: 124, width: 110)
        modelPicker.frame = NSRect(x: 142, y: 116, width: 430, height: 30)
        modelPicker.target = self; modelPicker.action = #selector(selectModel); modelPicker.setAccessibilityLabel("吐槽模型"); modelPage.addSubview(modelPicker)
        SettingsStyle.label("推理档位", in: modelPage, y: 172, width: 110)
        effortPicker.frame = NSRect(x: 142, y: 164, width: 430, height: 30)
        effortPicker.target = self; effortPicker.action = #selector(selectEffort); effortPicker.setAccessibilityLabel("推理档位"); modelPage.addSubview(effortPicker)
        refreshButton.title = "刷新选项"; refreshButton.bezelStyle = .rounded
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil); refreshButton.imagePosition = .imageLeading
        refreshButton.target = self; refreshButton.action = #selector(loadModels)
        refreshButton.frame = NSRect(x: 440, y: 210, width: 132, height: 32); modelPage.addSubview(refreshButton)
        modelHint.font = .systemFont(ofSize: 12); modelHint.textColor = .secondaryLabelColor
        modelHint.frame = NSRect(x: 28, y: 262, width: 540, height: 42); modelPage.addSubview(modelHint)
        SettingsStyle.divider(in: modelPage, y: 326)
        SettingsStyle.label("共享记忆", in: modelPage, y: 352, weight: .semibold)
        SettingsStyle.label("不同会话共享简短画像和项目概况；聊天记录各自隔离。\n画像最多 400 字，全部项目记忆合计最多 800 字。", in: modelPage, y: 389, size: 12, secondary: true, height: 45)
        SettingsStyle.button("查看与编辑", symbol: "square.and.pencil", in: modelPage, x: 24, y: 453, width: 144, target: self, action: #selector(openMemory))
    }

    @objc func loadModels() {
        guard !loading else { return }
        loading = true
        refreshButton.isEnabled = false
        modelHint.stringValue = "正在从 Codex 读取可用选项…"
        if models.isEmpty {
            modelPicker.removeAllItems(); modelPicker.addItem(withTitle: "正在读取…")
            modelPicker.isEnabled = false
            effortPicker.isEnabled = false
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try CodexModelCatalog.fetch() }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading = false
                self.refreshButton.isEnabled = true
                switch result {
                case .success(let models): self.apply(models)
                case .failure:
                    self.modelHint.stringValue = self.models.isEmpty ? "读取失败，请确认 Codex 登录后点击刷新。" : "刷新失败，保留上次选项。请稍后重试。"
                    if self.models.isEmpty { self.modelPicker.removeAllItems(); self.modelPicker.addItem(withTitle: "未读取到模型") }
                }
            }
        }
    }

    private var selectedModel: CodexModel? {
        guard let id = modelPicker.selectedItem?.representedObject as? String else { return nil }
        return models.first { $0.model == id }
    }

    private func apply(_ models: [CodexModel]) {
        self.models = models
        let saved = CodexModelPreferences.load()
        modelPicker.removeAllItems()
        for model in models {
            modelPicker.addItem(withTitle: model.title)
            modelPicker.lastItem?.representedObject = model.model
        }
        modelPicker.isEnabled = true
        if let saved = saved, !models.contains(where: { $0.model == saved.model }) {
            modelPicker.addItem(withTitle: "不在当前列表：" + saved.model)
            modelPicker.lastItem?.isEnabled = false
            modelPicker.select(modelPicker.lastItem)
            effortPicker.removeAllItems(); effortPicker.addItem(withTitle: "请重新选择模型")
            effortPicker.isEnabled = false
            modelHint.stringValue = "已保存的模型不在当前列表中，请重新选择。"
            return
        }
        let model = models.first { $0.model == saved?.model } ?? models.first { $0.isDefault == true } ?? models[0]
        modelPicker.selectItem(at: models.firstIndex { $0.model == model.model }!)
        let choice = model.selection(effort: saved?.effort)
        updateEfforts(model, choice: choice)
        CodexModelPreferences.save(choice)
        if let saved = saved, saved.effort != choice.effort {
            modelHint.stringValue = "原档位当前不受支持，已使用模型默认档位。"
        } else {
            modelHint.stringValue = "选项来自 Codex。更改自动保存，下次吐槽生效。"
        }
    }

    private func updateEfforts(_ model: CodexModel, choice: CodexModelSelection) {
        effortPicker.removeAllItems()
        for effort in model.efforts {
            effortPicker.addItem(withTitle: effort.title)
            effortPicker.lastItem?.representedObject = effort.reasoningEffort
            effortPicker.lastItem?.toolTip = effort.description
        }
        effortPicker.isEnabled = !model.efforts.isEmpty
        if model.efforts.isEmpty { effortPicker.addItem(withTitle: "模型不提供档位选项") }
        else { effortPicker.selectItem(at: model.efforts.firstIndex { $0.reasoningEffort == choice.effort } ?? 0) }
    }

    @objc private func selectModel() {
        guard let model = selectedModel else { return }
        let choice = model.selection()
        updateEfforts(model, choice: choice)
        CodexModelPreferences.save(choice)
        modelHint.stringValue = "已保存，下次吐槽使用新的模型和档位。"
    }

    @objc private func selectEffort() {
        guard let model = selectedModel, let effort = effortPicker.selectedItem?.representedObject as? String else { return }
        CodexModelPreferences.save(model.selection(effort: effort))
        modelHint.stringValue = "已保存，下次吐槽使用新的模型和档位。"
    }
}
