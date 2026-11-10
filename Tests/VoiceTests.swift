import AppKit

@main struct VoiceTests {
    static func main() throws {
        for provider in TTSProvider.allCases {
            var config = provider.defaults
            if provider == .elevenLabs { config.voice = "demo/voice" }
            let request = try TTSRequest.build(provider: provider, configuration: config, secrets: TTSSecrets(apiKey: "test-key"), text: "你好\"<&\n")
            assert(request.sampleRate == 24000)
            if provider == .elevenLabs {
                assert(request.request.url!.absoluteString.contains("demo%2Fvoice"))
                assert(request.request.url!.query!.contains("pcm_24000"))
            }
            if provider == .miniMax {
                let object = try JSONSerialization.jsonObject(with: request.request.httpBody!) as! [String: Any]
                assert((object["stream_options"] as! [String: Any])["exclude_aggregated_audio"] as! Bool)
            }
            if provider == .azure { assert(String(data: request.request.httpBody!, encoding: .utf8)!.contains("&lt;&amp;")) }
            if provider == .cosyVoice {
                let message = try JSONSerialization.jsonObject(with: Data(request.websocketMessage("continue-task", input: ["text": "你好"]).utf8)) as! [String: Any]
                assert((message["header"] as! [String: Any])["task_id"] as! String == request.taskID)
            }
        }
        var custom = TTSProvider.custom.defaults
        custom.response = .base64SSE; custom.audioPath = "data.audio"
        custom.body = "{\"nested\":[{\"input\":\"${text}\"}]}"
        let request = try TTSRequest.build(provider: .custom, configuration: custom, secrets: TTSSecrets(), text: "literal ${voice} with \"quotes\"")
        let object = try JSONSerialization.jsonObject(with: request.request.httpBody!) as! [String: Any]
        assert(((object["nested"] as! [[String: String]])[0])["input"] == "literal ${voice} with \"quotes\"", "Data cannot be reinterpreted as a second placeholder")
        custom.endpoint = "http://untrusted.example/tts"
        do { _ = try TTSRequest.build(provider: .custom, configuration: custom, secrets: TTSSecrets(), text: "test"); fatalError("Require TLS off-loopback") } catch {}
        var fifo = PCMBufferFIFO(); fifo.append(Data([1, 2, 3])); assert(fifo.take(maximum: 10) == Data([1, 2]))
        fifo.append(Data([4])); assert(fifo.take(maximum: 10) == Data([3, 4]))
        let large = Data((0..<240000).map { UInt8($0 % 251) })
        fifo.append(large); var drained = Data()
        while fifo.count > 0 { drained.append(fifo.take(maximum: 4800)) }
        assert(drained == large, "Data slices keep non-zero indices after FIFO compaction")
        let pcm = Data([0, 1, 2, 3, 254, 255])
        let cases: [(TTSWireFormat, String)] = [
            (.miniMax, "data: {\"data\":{\"audio\":\"00010203feff\",\"status\":1}}\r\n\r\ndata: {\"data\":{\"status\":2}}\r\n\r\n"),
            (.doubao, "event: 352\ndata: {\"code\":0,\"data\":\"\(pcm.base64EncodedString())\"}\n\nevent: 152\ndata: {\"code\":20000000}\n\n"),
            (.custom(path: "data.audio", hex: false), "data: {\"data\":{\"audio\":\"\(pcm.base64EncodedString())\"},\"note\":\"中文\"}\n\ndata: [DONE]\n\n")]
        for (format, event) in cases {
            for length in [1, 3, 17, 4096] {
                var decoder = TTSStreamDecoder(format: format); var result = Data(); let bytes = Data(event.utf8)
                for start in stride(from: 0, to: bytes.count, by: length) {
                    for chunk in try decoder.append(bytes.subdata(in: start..<min(start + length, bytes.count))) { result.append(chunk) }
                }
                for chunk in try decoder.close() { result.append(chunk) }
                assert(result == pcm && decoder.finished)
            }
        }
        var truncated = TTSStreamDecoder(format: .doubao)
        _ = try truncated.append(Data("data: {\"code\":0,\"data\":\"AAE=\"}\n\n".utf8))
        do { _ = try truncated.close(); fatalError("Missing terminal event must fail") } catch {}
        var failure = TTSStreamDecoder(format: .miniMax)
        do { _ = try failure.append(Data("data: {\"base_resp\":{\"status_code\":1004}}\n\n".utf8)); fatalError("Provider error must fail") } catch {}
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefs = VoicePreferences(directory: directory)
        assert(!prefs.value.enabled)
        try prefs.save(provider: .custom, configuration: TTSProvider.custom.defaults, enabled: true)
        assert(VoicePreferences(directory: directory).value.enabled)
        let json = try String(contentsOf: directory.appendingPathComponent("voice.json"), encoding: .utf8)
        assert(!json.contains("apiKey") && !json.contains("test-key") && !json.contains("headers"))
        print("PASS: seven request adapters, literal JSON substitution, fragmented SSE/PCM, terminal/error events, private preferences")
    }
}
