import AppKit

final class SettingsWindowController: NSWindowController {
    private let preview = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let resetButton = NSButton()
    private let modelPicker = NSPopUpButton()
    private let effortPicker = NSPopUpButton()
    private let refreshButton = NSButton()
    private let modelHint = NSTextField(wrappingLabelWithString: "")
    private var models: [CodexModel] = []
    private var loading = false
    var onImport: (() -> Void)?
    var onReset: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ChimeBuddy 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = window.contentView!
        let heading = NSTextField(labelWithString: "伙伴形象")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 453, width: 332, height: 23)
        content.addSubview(heading)
        preview.frame = NSRect(x: 22, y: 264, width: 136, height: 180)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("伙伴形象预览")
        content.addSubview(preview)
        nameLabel.frame = NSRect(x: 178, y: 410, width: 178, height: 20)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        content.addSubview(nameLabel)
        let description = NSTextField(wrappingLabelWithString: "选择你喜欢的 GIF，让她动起来。")
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        description.frame = NSRect(x: 178, y: 359, width: 178, height: 39)
        content.addSubview(description)
        let importButton = NSButton(title: "导入 GIF 形象…", target: self, action: #selector(importAvatar))
        importButton.bezelStyle = .rounded
        importButton.frame = NSRect(x: 174, y: 311, width: 186, height: 32)
        content.addSubview(importButton)
        resetButton.title = "恢复默认形象"
        resetButton.target = self
        resetButton.action = #selector(resetAvatar)
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 174, y: 272, width: 186, height: 32)
        content.addSubview(resetButton)
        let hint = NSTextField(labelWithString: "GIF · 最大 20 MB")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 24, y: 237, width: 332, height: 17)
        content.addSubview(hint)
        let divider = NSBox(frame: NSRect(x: 24, y: 218, width: 332, height: 1))
        divider.boxType = .separator
        content.addSubview(divider)
        let modelHeading = NSTextField(labelWithString: "吐槽模型")
        modelHeading.font = heading.font
        modelHeading.frame = NSRect(x: 24, y: 180, width: 332, height: 23)
        content.addSubview(modelHeading)
        for (title, y) in [("模型", 143.0), ("推理档位", 101.0)] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 24, y: y, width: 76, height: 20)
            content.addSubview(label)
        }
        modelPicker.frame = NSRect(x: 100, y: 138, width: 256, height: 28)
        modelPicker.setAccessibilityLabel("吐槽模型")
        modelPicker.target = self
        modelPicker.action = #selector(selectModel)
        content.addSubview(modelPicker)
        effortPicker.frame = NSRect(x: 100, y: 96, width: 256, height: 28)
        effortPicker.setAccessibilityLabel("推理档位")
        effortPicker.target = self
        effortPicker.action = #selector(selectEffort)
        content.addSubview(effortPicker)
        refreshButton.title = "刷新"
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: 290, y: 50, width: 70, height: 28)
        refreshButton.target = self
        refreshButton.action = #selector(loadModels)
        content.addSubview(refreshButton)
        modelHint.font = .systemFont(ofSize: 11)
        modelHint.textColor = .secondaryLabelColor
        modelHint.frame = NSRect(x: 24, y: 19, width: 250, height: 50)
        content.addSubview(modelHint)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func update(customURL: URL) {
        if let image = NSImage(contentsOf: customURL), image.isValid {
            preview.image = image
            nameLabel.stringValue = "自定义 GIF"
            resetButton.isEnabled = true
        } else {
            preview.image = Bundle.main.url(forResource: "codex-companion", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
            nameLabel.stringValue = "默认 Codex 伙伴"
            resetButton.isEnabled = false
        }
        preview.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @objc private func importAvatar() { onImport?() }
    @objc private func resetAvatar() { onReset?() }

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
