import AppKit
import UniformTypeIdentifiers

final class ActionSettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    override var isFlipped: Bool { true }
    let library: ActionLibrary
    private let preview = NSImageView()
    private let table = NSTableView()
    private let tagField = NSTextField()
    private let meaningField = NSTextField()
    private let fileLabel = NSTextField(labelWithString: "尚未选择 GIF")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var selectedID: UUID?
    private var selectedGIF: URL?
    private var customAvatarURL: URL?
    private var previewTimer: Timer?
    var onImport: (() -> Void)?
    var onReset: (() -> Void)?
    var onChange: (() -> Void)?
    init(library: ActionLibrary) {
        self.library = library
        super.init(frame: NSRect(x: 0, y: 0, width: SettingsStyle.width, height: 760))
        SettingsStyle.heading("形象与动作", subtitle: "每个动作绑定一个 GIF。AI 根据用途选标签，气泡只显示回复。", in: self)
        preview.frame = NSRect(x: 34, y: 108, width: 110, height: 126)
        preview.imageScaling = .scaleProportionallyUpOrDown; preview.setAccessibilityLabel("形象及动作预览"); addSubview(preview)
        SettingsStyle.label("默认形象", in: self, x: 170, y: 112, weight: .medium)
        SettingsStyle.label("没有动作匹配时使用。GIF 最大 20 MB。", in: self, x: 170, y: 140, width: 375, size: 12, secondary: true)
        SettingsStyle.button("导入 GIF", symbol: "photo", in: self, x: 166, y: 175, width: 114, target: self, action: #selector(importAvatar))
        SettingsStyle.button("恢复默认", symbol: "arrow.counterclockwise", in: self, x: 286, y: 175, width: 114, target: self, action: #selector(resetAvatar))
        SettingsStyle.divider(in: self, y: 248)
        SettingsStyle.label("动作标签", in: self, y: 270, weight: .semibold)
        SettingsStyle.button("新增", symbol: "plus", in: self, x: 484, y: 261, width: 88, target: self, action: #selector(newAction))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action")); column.width = 516
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 40
        table.dataSource = self; table.delegate = self; table.style = .plain
        table.setAccessibilityLabel("已保存的动作标签")
        let scroll = NSScrollView(frame: NSRect(x: 28, y: 306, width: 540, height: 148))
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .lineBorder
        addSubview(scroll)
        SettingsStyle.input(tagField, label: "标签", in: self, y: 476, placeholder: "例如：嫌弃、得意、开心")
        SettingsStyle.input(meaningField, label: "何时使用", in: self, y: 516, placeholder: "例如：发现用户反复改需求时")
        fileLabel.font = .systemFont(ofSize: 11); fileLabel.textColor = .secondaryLabelColor
        fileLabel.frame = NSRect(x: 146, y: 555, width: 422, height: 20); addSubview(fileLabel)
        SettingsStyle.button("选择 GIF…", symbol: "folder", in: self, x: 142, y: 584, width: 124, target: self, action: #selector(chooseGIF))
        SettingsStyle.button("预览", symbol: "play", in: self, x: 272, y: 584, width: 88, target: self, action: #selector(previewGIF))
        SettingsStyle.button("删除", symbol: "trash", in: self, x: 368, y: 584, width: 86, target: self, action: #selector(deleteAction))
        SettingsStyle.button("保存动作", symbol: "checkmark", in: self, x: 460, y: 584, width: 112, target: self, action: #selector(saveAction))
        status.frame = NSRect(x: 28, y: 632, width: 540, height: 36); status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; addSubview(status)
        SettingsStyle.label("保存并绑定 GIF 后自动参与 AI 动作选择。不限制标签数量。\n动作随回复播放，结束后恢复默认形象；切会话会停止旧动作。", in: self, y: 688, size: 11, secondary: true, height: 45)
        refreshTable()
    }
    required init?(coder: NSCoder) { nil }
    func update(customURL: URL) {
        customAvatarURL = customURL
        if previewTimer == nil { restorePreview() }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { max(1, library.actions.count) }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: library.actions.isEmpty ? "还没有动作，点击新增并绑定 GIF。" : library.actions[row].tag + "   ·   " + (library.url(for: library.actions[row]) == nil ? "未绑定 GIF" : library.actions[row].meaning))
        cell.font = .systemFont(ofSize: 12); cell.lineBreakMode = .byTruncatingTail; cell.textColor = library.actions.isEmpty ? .secondaryLabelColor : .labelColor
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, table.selectedRow < library.actions.count else { return }
        let action = library.actions[table.selectedRow]; selectedID = action.id; selectedGIF = nil
        tagField.stringValue = action.tag; meaningField.stringValue = action.meaning
        fileLabel.stringValue = library.url(for: action) == nil ? "GIF 文件缺失，请重新选择" : "已绑定 GIF"
        status.stringValue = "编辑后点击保存动作。"
    }
    private func refreshTable() { table.reloadData(); if library.actions.isEmpty { status.stringValue = "先新增标签，再选择对应的 GIF。" } }
    @objc private func newAction() {
        table.deselectAll(nil); selectedID = nil; selectedGIF = nil
        tagField.stringValue = ""; meaningField.stringValue = ""; fileLabel.stringValue = "尚未选择 GIF"
        status.stringValue = "填写标签、用途并选择 GIF，然后保存。"; window?.makeFirstResponder(tagField)
    }
    @objc private func chooseGIF() {
        guard let window = window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.gif]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            do { _ = try ActionLibrary.gifData(at: url); self.selectedGIF = url; self.fileLabel.stringValue = url.lastPathComponent; self.status.stringValue = "GIF 已选择，点击保存动作生效。" }
            catch { self.status.stringValue = error.localizedDescription }
        }
    }
    @objc private func previewGIF() {
        let existing = library.actions.first { $0.id == selectedID }.flatMap { library.url(for: $0) }
        guard let url = selectedGIF ?? existing, let image = NSImage(contentsOf: url) else { status.stringValue = "请先选择 GIF。"; return }
        previewTimer?.invalidate(); preview.image = image; preview.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        previewTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in self?.previewTimer = nil; self?.restorePreview() }
    }
    @objc private func saveAction() {
        do {
            guard selectedGIF != nil || library.actions.first(where: { $0.id == selectedID }).flatMap({ library.url(for: $0) }) != nil else { throw BuddySettingsError.invalid("请先为动作选择 GIF。") }
            let saved = try library.save(id: selectedID, tag: tagField.stringValue, meaning: meaningField.stringValue, gif: selectedGIF)
            selectedID = saved.id; selectedGIF = nil; refreshTable()
            if let row = library.actions.firstIndex(where: { $0.id == saved.id }) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            status.stringValue = "已保存，下次回复可使用“\(saved.tag)”。"; onChange?()
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func deleteAction() {
        guard let id = selectedID else { status.stringValue = "先选择一个动作。"; return }
        do { try library.delete(id: id); newAction(); refreshTable(); status.stringValue = "动作及对应 GIF 已删除。"; onChange?() }
        catch { status.stringValue = error.localizedDescription }
    }
    private func restorePreview() {
        preview.image = customAvatarURL.flatMap { NSImage(contentsOf: $0) } ?? Bundle.main.url(forResource: "codex-companion", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        preview.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    @objc private func importAvatar() { onImport?() }
    @objc private func resetAvatar() { onReset?() }
}
