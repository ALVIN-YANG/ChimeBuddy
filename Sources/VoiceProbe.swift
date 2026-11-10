import AppKit

/// Explicit manual probe. Input is JSON on stdin so credentials never appear
/// in process arguments or logs. No personal chat or model call is involved.
enum VoiceProbe {
    struct Input: Decodable {
        var provider: TTSProvider
        var configuration: TTSConfiguration
        var secrets: TTSSecrets
        var install: Bool?
    }
    static func run(storage: URL) throws {
        let input = try JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
        NSApplication.shared.setActivationPolicy(.prohibited)
        let voice = StreamingVoice()
        var turn = 0
        var done = false
        var failed = false
        let texts = ["这是伙伴的流式语音测试。你现在听到的是第一句。", "这一句会被主动打断，不应该串到下一句。", "打断后重新播放，只有当前这句话应该被听到。"]
        func next() {
            guard turn < texts.count else { done = true; return }
            let number = turn
            do {
                let request = try TTSRequest.build(provider: input.provider, configuration: input.configuration, secrets: input.secrets, text: texts[number])
                try voice.speak(request)
            } catch { fputs("Probe failed: \(error.localizedDescription)\n", stderr); failed = true; done = true }
        }
        voice.onStatus = { status in
            print("turn=\(turn + 1) status=\(status.text)"); fflush(stdout)
            if status == .playing, turn == 1 {
                Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in voice.stop() }
            }
            if case .failed = status { failed = true }
        }
        voice.onMetrics = { metrics in
            if let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text); fflush(stdout) }
        }
        voice.onFinished = {
            if failed { done = true; return }
            turn += 1
            _ = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in next() }
        }
        next()
        let deadline = Date().addingTimeInterval(180)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        voice.stop(notify: false)
        guard done, !failed else { throw BuddySettingsError.invalid("语音探针失败或超时。") }
        if input.install == true {
            try VoiceKeychain.save(input.secrets, provider: input.provider)
            try VoicePreferences(directory: storage).save(provider: input.provider, configuration: input.configuration, enabled: true)
            print("Installed working configuration; credentials saved to Keychain only")
        }
        print("PASS: consecutive playback, interruption, fresh stream after cancellation")
    }
}
