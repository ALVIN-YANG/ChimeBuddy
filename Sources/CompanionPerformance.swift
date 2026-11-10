import AppKit

/// Presentation effects share the same foreground lifetime. Cached text never
/// replays speech just because a chat is opened again.
final class CompanionPerformance {
    let voice = StreamingVoice()
    let library: ActionLibrary
    let preferences: VoicePreferences
    let avatar: CompanionAvatarView
    var restoreAvatar: (() -> Void)?
    var onVoiceError: ((String) -> Void)?
    private var resetTimer: Timer?
    private var token = UUID()
    private var active = false
    init(avatar: CompanionAvatarView, library: ActionLibrary, preferences: VoicePreferences) {
        self.avatar = avatar; self.library = library; self.preferences = preferences
        voice.onStatus = { [weak self] status in if case .failed(let message) = status { self?.onVoiceError?(message) } }
    }
    func cancel() {
        token = UUID(); resetTimer?.invalidate(); resetTimer = nil
        voice.onFinished = nil; voice.stop(notify: false)
        if active { restoreAvatar?(); avatar.setMood(.idle) }
        active = false
    }
    func play(text: String, action tag: String?) {
        cancel()
        active = true
        let current = token
        if let action = library.action(tag: tag), let url = library.url(for: action), let image = NSImage(contentsOf: url) { avatar.loadCustom(image) }
        avatar.setMood(.speaking)
        func restore() {
            guard self.token == current else { return }
            self.resetTimer?.invalidate(); self.resetTimer = nil
            self.restoreAvatar?(); self.avatar.setMood(.idle)
            self.active = false
            self.voice.onFinished = nil
        }
        if preferences.value.enabled {
            do {
                let provider = preferences.value.provider
                let request = try TTSRequest.build(provider: provider, configuration: preferences.configuration(for: provider), secrets: VoiceKeychain.load(provider), text: text)
                voice.onFinished = { restore() }
                try voice.speak(request, outputDeviceUID: preferences.value.outputDeviceUID)
                return
            } catch { onVoiceError?(error.localizedDescription) }
        }
        resetTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in restore() }
    }
}
