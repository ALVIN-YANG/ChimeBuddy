import Foundation

enum TTSWireFormat: Equatable { case pcm, miniMax, doubao, custom(path: String, hex: Bool), cosyVoice }

struct TTSRequest {
    let request: URLRequest
    let format: TTSWireFormat
    let sampleRate: Int
    let websocketStart: [String: Any]?
    let text: String
    let taskID: String

    static func build(provider: TTSProvider, configuration c: TTSConfiguration, secrets: TTSSecrets, text: String) throws -> TTSRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4096 else {
            throw BuddySettingsError.invalid("朗读文本需为 1–4096 字。")
        }
        guard provider == .custom || !secrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BuddySettingsError.invalid("请先填写 API Key。") }
        guard provider == .custom || !c.voice.isEmpty else { throw BuddySettingsError.invalid("请先填写 Voice ID。") }
        let encodedVoice = c.voice.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard let url = URL(string: c.endpoint.replacingOccurrences(of: "{voice}", with: encodedVoice)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              ["https", "wss"].contains(url.scheme) || (["localhost", "127.0.0.1", "::1"].contains(host) && ["http", "ws"].contains(url.scheme)) else {
            throw BuddySettingsError.invalid("请填写完整 HTTPS / WSS 地址；本机服务可用 HTTP / WS。")
        }
        guard (provider == .cosyVoice) == ["wss", "ws"].contains(url.scheme) else { throw BuddySettingsError.invalid("CosyVoice 使用 WSS，其他服务使用 HTTPS。") }
        let rate = provider == .custom ? c.sampleRate : 24000
        guard [8000, 16000, 22050, 24000, 32000, 44100, 48000].contains(rate) else { throw BuddySettingsError.invalid("不支持这个 PCM 采样率。") }
        let headersObject = try JSONSerialization.jsonObject(with: Data(secrets.headers.utf8))
        guard let extraHeaders = headersObject as? [String: String] else { throw BuddySettingsError.invalid("附加请求头需为 JSON 字符串字典。") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = provider == .cosyVoice ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ChimeBuddy/0.2", forHTTPHeaderField: "User-Agent")
        let key = secrets.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var body: [String: Any] = [:]
        var format: TTSWireFormat = .pcm
        let taskID = UUID().uuidString
        var websocketStart: [String: Any]?
        switch provider {
        case .elevenLabs:
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "output_format" } + [URLQueryItem(name: "output_format", value: "pcm_24000")]
            request.url = parts.url
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            body = ["text": text, "model_id": c.model]
        case .openAI:
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            body = ["input": text, "model": c.model, "voice": c.voice, "response_format": "pcm"]
        case .azure:
            request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            request.setValue("raw-24khz-16bit-mono-pcm", forHTTPHeaderField: "X-Microsoft-OutputFormat")
            request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
            let ssml = "<speak version='1.0' xml:lang='zh-CN'><voice name='\(xml(c.voice))'>\(xml(text))</voice></speak>"
            request.httpBody = Data(ssml.utf8)
        case .miniMax:
            format = .miniMax
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            body = ["text": text, "model": c.model, "stream": true, "output_format": "hex",
                    "stream_options": ["exclude_aggregated_audio": true],
                    "voice_setting": ["voice_id": c.voice], "audio_setting": ["format": "pcm", "sample_rate": 24000, "channel": 1]]
        case .doubao:
            format = .doubao
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
            request.setValue(c.model, forHTTPHeaderField: "X-Api-Resource-Id")
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
            body = ["user": ["uid": "chimebuddy"], "req_params": ["text": text, "speaker": c.voice, "audio_params": ["format": "pcm", "sample_rate": 24000]]]
        case .cosyVoice:
            format = .cosyVoice
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            websocketStart = ["header": ["action": "run-task", "task_id": taskID, "streaming": "duplex"],
                "payload": ["task_group": "audio", "task": "tts", "function": "SpeechSynthesizer", "model": c.model,
                    "parameters": ["text_type": "PlainText", "voice": c.voice, "format": "pcm", "sample_rate": 24000], "input": [:]]]
        case .custom:
            if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
            let object = try JSONSerialization.jsonObject(with: Data(c.body.utf8))
            guard let mapped = replace(object, values: ["${text}": text, "${model}": c.model, "${voice}": c.voice]) as? [String: Any] else { throw BuddySettingsError.invalid("请求体需为 JSON 对象。") }
            body = mapped
            switch c.response { case .pcm: break
            case .base64SSE: format = .custom(path: c.audioPath, hex: false)
            case .hexSSE: format = .custom(path: c.audioPath, hex: true) }
        }
        for (name, value) in extraHeaders {
            let value = value.replacingOccurrences(of: "${key}", with: key)
            guard !name.isEmpty, !name.contains(where: { !$0.isASCII || $0.isWhitespace || $0 == ":" }),
                  !value.contains("\r"), !value.contains("\n"),
                  !["host", "content-length", "transfer-encoding"].contains(name.lowercased()) else { throw BuddySettingsError.invalid("附加请求头包含无效字段。") }
            request.setValue(value, forHTTPHeaderField: name)
        }
        if request.httpBody == nil, provider != .cosyVoice { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return TTSRequest(request: request, format: format, sampleRate: rate, websocketStart: websocketStart, text: text, taskID: taskID)
    }
    func websocketMessage(_ action: String, input: [String: String]) throws -> String {
        let object: [String: Any] = ["header": ["action": action, "task_id": taskID, "streaming": "duplex"], "payload": ["input": input]]
        return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func replace(_ object: Any, values: [String: String]) -> Any {
        if let string = object as? String {
            // Scan only the original template. User text containing another
            // placeholder is data and must not be substituted again.
            let pattern = #"\$\{(?:text|model|voice)\}"#
            let regex = try! NSRegularExpression(pattern: pattern)
            var result = string
            for match in regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).reversed() {
                guard let original = Range(match.range, in: string), let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: values[String(string[original])] ?? String(string[original]))
            }
            return result
        }
        if let dict = object as? [String: Any] { return dict.mapValues { replace($0, values: values) } }
        if let array = object as? [Any] { return array.map { replace($0, values: values) } }
        return object
    }
}
