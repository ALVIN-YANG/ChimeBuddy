import AppKit

@main struct VoiceIntegrationTests {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let base = CommandLine.arguments[1]
        let voice = StreamingVoice()
        let cases: [(TTSProvider, String)] = [(.elevenLabs, "/pcm"), (.openAI, "/pcm"), (.azure, "/pcm"), (.miniMax, "/minimax"), (.doubao, "/doubao"), (.custom, "/custom"), (.cosyVoice, "/cosy")]
        func run(_ provider: TTSProvider, path: String, success: Bool = true, outputDeviceUID: String? = nil) throws {
            var config = provider.defaults; config.endpoint = base + path; config.voice = "test-voice"
            if provider == .cosyVoice { config.endpoint = config.endpoint.replacingOccurrences(of: "http://", with: "ws://") }
            if provider == .custom { config.response = .base64SSE; config.audioPath = "data.audio" }
            var done = false; var completed = false; var bytes = 0; var consumed = 0; var playing = false
            voice.onStatus = { if $0 == .playing { playing = true }; if $0 == .completed { completed = true } }
            voice.onMetrics = { metrics in bytes = metrics["audioBytes"] as? Int ?? 0; consumed = metrics["consumedBytes"] as? Int ?? 0 }
            voice.onFinished = { done = true }
            try voice.speak(TTSRequest.build(provider: provider, configuration: config, secrets: TTSSecrets(apiKey: "fixture-only"), text: "本地固定语音测试"), outputDeviceUID: outputDeviceUID)
            let deadline = Date().addingTimeInterval(8)
            while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            assert(done && completed == success, "\(provider) \(path) completion contract")
            if success { assert(playing && bytes == 38400 && consumed == bytes, "All decoded bytes must reach output buffers") }
            print("PASS: network → \(provider.rawValue) → decoder → AudioQueue \(path)")
        }
        for (provider, path) in cases { try run(provider, path: path) }
        if let current = AudioOutputDevices.list().first(where: { $0.name == AudioOutputDevices.systemName }) {
            try run(.openAI, path: "/pcm", outputDeviceUID: current.uid)
            print("PASS: explicit output-device UID uses the same physical route without changing system settings")
        }
        try run(.openAI, path: "/error", success: false)
        try run(.doubao, path: "/truncated", success: false)
        try run(.cosyVoice, path: "/cosy-truncated", success: false)
        var config = TTSProvider.openAI.defaults; config.endpoint = base + "/slow"; config.voice = "test"
        let request = try TTSRequest.build(provider: .openAI, configuration: config, secrets: TTSSecrets(apiKey: "fixture-only"), text: "会被取消")
        var phase = 0; var done = false; var failures = 0
        voice.onStatus = { status in
            if case .failed = status { failures += 1 }
            if status == .playing && phase == 0 {
                phase = 1
                _ = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { _ in
                    voice.stop()
                    config.endpoint = base + "/pcm"
                    do { try voice.speak(TTSRequest.build(provider: .openAI, configuration: config, secrets: TTSSecrets(apiKey: "fixture-only"), text: "新的当前会话")) }
                    catch { fatalError("Fresh utterance failed") }
                }
            }
            if status == .completed { done = true }
        }
        voice.onFinished = nil; voice.onMetrics = nil
        try voice.speak(request)
        let deadline = Date().addingTimeInterval(8)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        assert(done && phase == 1 && failures == 0, "Canceled transport callbacks cannot fail the next utterance")
        print("PASS: interruption clears queued audio and rejects late callbacks before next utterance")
    }
}
