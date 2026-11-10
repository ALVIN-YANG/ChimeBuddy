import Foundation
import Security

enum TTSProvider: String, Codable, CaseIterable {
    case elevenLabs, openAI, azure, miniMax, doubao, cosyVoice, custom
    var title: String {
        switch self {
        case .elevenLabs: return "ElevenLabs"
        case .openAI: return "OpenAI / 兼容接口"
        case .azure: return "Azure Speech"
        case .miniMax: return "MiniMax"
        case .doubao: return "火山豆包"
        case .cosyVoice: return "阿里云 CosyVoice"
        case .custom: return "自定义 HTTP 流"
        }
    }
    var defaults: TTSConfiguration {
        switch self {
        case .elevenLabs: return TTSConfiguration(endpoint: "https://api.elevenlabs.io/v1/text-to-speech/{voice}/stream", model: "eleven_flash_v2_5", voice: "")
        case .openAI: return TTSConfiguration(endpoint: "https://api.openai.com/v1/audio/speech", model: "gpt-4o-mini-tts", voice: "coral")
        case .azure: return TTSConfiguration(endpoint: "https://YOUR-REGION.tts.speech.microsoft.com/cognitiveservices/v1", model: "", voice: "zh-CN-XiaoxiaoNeural")
        case .miniMax: return TTSConfiguration(endpoint: "https://api.minimaxi.com/v1/t2a_v2", model: "speech-2.8-turbo", voice: "Chinese (Mandarin)_Warm_Bestie")
        case .doubao: return TTSConfiguration(endpoint: "https://openspeech.bytedance.com/api/v3/tts/unidirectional/sse", model: "seed-tts-2.0", voice: "zh_female_vv_uranus_bigtts")
        case .cosyVoice: return TTSConfiguration(endpoint: "wss://dashscope.aliyuncs.com/api-ws/v1/inference", model: "cosyvoice-v3-plus", voice: "longanyang")
        case .custom: return TTSConfiguration(endpoint: "http://localhost:8000/tts", model: "", voice: "")
        }
    }
    var help: String {
        switch self {
        case .elevenLabs: return "Voice ID 从 ElevenLabs 声音库复制。使用 PCM 24 kHz 流式输出。"
        case .openAI: return "填写完整 speech 地址，兼容服务须支持 response_format=pcm。OpenAI 当前 Speech 模型计划于 2027-01-06 退役。"
        case .azure: return "将 YOUR-REGION 换成资源区域。密钥使用 Speech 资源密钥。"
        case .miniMax: return "国内 api.minimaxi.com，国际 api.minimax.io。音色与模型需在账号内可用。"
        case .doubao: return "模型栏填写 Resource ID。使用新版 X-Api-Key 鉴权；旧版 App ID 可放在附加请求头。"
        case .cosyVoice: return "支持双向 WebSocket。可将默认域名改成百炼工作空间专属 wss 地址。"
        case .custom: return "仅支持单声道 PCM16 LE，或 SSE 包装的 PCM。请求体可用 ${text}、${model}、${voice}；请求头可用 ${key}。"
        }
    }
}

enum TTSCustomResponse: String, Codable, CaseIterable {
    case pcm, base64SSE, hexSSE
    var title: String { switch self { case .pcm: return "原始 PCM"; case .base64SSE: return "SSE · Base64 PCM"; case .hexSSE: return "SSE · Hex PCM" } }
}

struct TTSConfiguration: Codable, Equatable {
    var endpoint: String
    var model: String
    var voice: String
    var sampleRate = 24000
    var response: TTSCustomResponse = .pcm
    var audioPath = "audio"
    var body = "{\"text\":\"${text}\",\"model\":\"${model}\",\"voice\":\"${voice}\",\"stream\":true,\"format\":\"pcm\",\"sample_rate\":24000}"
}

struct TTSSecrets: Codable, Equatable {
    var apiKey = ""
    var headers = "{}"
}

/// Credentials never enter preferences, diagnostics, caches, or model context.
enum VoiceKeychain {
    static let service = "dev.chimebuddy.tts"
    static func load(_ provider: TTSProvider) throws -> TTSSecrets {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue, kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return TTSSecrets() }
        guard status == errSecSuccess, let data = result as? Data else { throw BuddySettingsError.invalid("无法读取钥匙串，错误码 \(status)。") }
        return try JSONDecoder().decode(TTSSecrets.self, from: data)
    }
    static func save(_ value: TTSSecrets, provider: TTSProvider) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue]
        if value.apiKey.isEmpty, value.headers.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw BuddySettingsError.invalid("删除密钥失败，错误码 \(status)。") }
            return
        }
        let data = try JSONEncoder().encode(value)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw BuddySettingsError.invalid("保存密钥失败，错误码 \(status)。") }
    }
}

final class VoicePreferences {
    struct Snapshot: Codable {
        var enabled = false
        var provider: TTSProvider = .elevenLabs
        var configurations: [String: TTSConfiguration] = [:]
        var outputDeviceUID: String? = nil
    }
    private(set) var value = Snapshot()
    private let file: URL
    init(directory: URL) {
        file = directory.appendingPathComponent("voice.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) { value = saved }
    }
    func configuration(for provider: TTSProvider) -> TTSConfiguration { value.configurations[provider.rawValue] ?? provider.defaults }
    func save(provider: TTSProvider, configuration: TTSConfiguration, enabled: Bool, outputDeviceUID: String? = nil) throws {
        var next = value; next.provider = provider; next.enabled = enabled; next.configurations[provider.rawValue] = configuration
        next.outputDeviceUID = outputDeviceUID
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        value = next
    }
}
