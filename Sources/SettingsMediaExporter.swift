import AppKit

enum SettingsMediaExporter {
    static func export(to directory: URL, storage: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let controller = SettingsWindowController(actions: ActionLibrary(directory: storage), voice: VoicePreferences(directory: storage), preview: true)
        controller.update(customURL: storage.appendingPathComponent("avatar.gif"))
        for (theme, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            controller.window?.appearance = NSAppearance(named: theme)
            for (index, section) in ["actions", "voice", "models"].enumerated() {
                controller.selectPage(index)
                guard let content = controller.window?.contentView else { continue }
                content.layoutSubtreeIfNeeded(); content.displayIfNeeded()
                guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw BuddySettingsError.invalid("无法导出设置截图。") }
                content.effectiveAppearance.performAsCurrentDrawingAppearance { content.cacheDisplay(in: content.bounds, to: bitmap) }
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw BuddySettingsError.invalid("无法编码设置截图。") }
                try data.write(to: directory.appendingPathComponent("settings-\(section)-\(name).png"))
            }
        }
        controller.close()
        print("Exported six native settings screenshots (isolated storage, no keys or model calls)")
    }
}
