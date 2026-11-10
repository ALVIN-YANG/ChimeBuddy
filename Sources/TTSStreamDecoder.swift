import Foundation

/// Incremental SSE framing. Transport fragments need not align to UTF-8,
/// lines, events, hex pairs, or PCM samples. Only audio bytes leave this layer.
struct TTSStreamDecoder {
    let format: TTSWireFormat
    private var pending = Data()
    private var lines: [String] = []
    private var eventBytes = 0
    private(set) var finished = false
    init(format: TTSWireFormat) { self.format = format }
    mutating func append(_ bytes: Data) throws -> [Data] {
        if format == .pcm { return [bytes] }
        guard !finished else { return [] }
        pending.append(bytes)
        guard pending.count <= 2_000_000 else { throw BuddySettingsError.invalid("语音事件过大。") }
        var audio: [Data] = []
        while let index = pending.firstIndex(of: 10) {
            let data = pending.prefix(upTo: index)
            pending.removeSubrange(...index)
            guard let raw = String(data: data, encoding: .utf8) else { throw BuddySettingsError.invalid("语音事件不是有效 UTF-8。") }
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.isEmpty {
                if let chunk = try event() { audio.append(chunk) }
                if finished { pending.removeAll(); break }
            } else if line.hasPrefix("data:") {
                let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                eventBytes += value.utf8.count
                guard eventBytes <= 2_000_000 else { throw BuddySettingsError.invalid("语音事件过大。") }
                lines.append(value)
            } else if line.hasPrefix("{") { // NDJSON form accepted by some compatible gateways.
                lines = [line]
                if let chunk = try event() { audio.append(chunk) }
            }
        }
        return audio
    }
    mutating func close() throws -> [Data] {
        guard format != .pcm else { return [] }
        var audio: [Data] = []
        if !pending.isEmpty { audio += try append(Data([10])) }
        if !lines.isEmpty, let chunk = try event() { audio.append(chunk) }
        if format == .miniMax || format == .doubao {
            guard finished else { throw BuddySettingsError.invalid("语音流在完成事件之前断开。") }
        }
        return audio
    }
    private mutating func event() throws -> Data? {
        guard !lines.isEmpty else { return nil }
        let value = lines.joined(separator: "\n"); lines.removeAll(); eventBytes = 0
        if value == "[DONE]" { finished = true; return nil }
        guard let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] else { throw BuddySettingsError.invalid("语音事件格式无效。") }
        if object["error"] != nil { throw BuddySettingsError.invalid("语音服务返回错误，请检查密钥、模型和额度。") }
        var encoded: String?
        var hex = false
        switch format {
        case .miniMax:
            if let base = object["base_resp"] as? [String: Any], let code = base["status_code"] as? Int, code != 0 { throw BuddySettingsError.invalid("MiniMax 返回错误码 \(code)。") }
            let data = object["data"] as? [String: Any]
            encoded = data?["audio"] as? String; hex = true
            if data?["status"] as? Int == 2 { finished = true }
        case .doubao:
            guard let code = object["code"] as? Int else { throw BuddySettingsError.invalid("豆包事件缺少 code。") }
            if code == 20000000 { finished = true }
            else if code != 0 { throw BuddySettingsError.invalid("豆包返回错误码 \(code)。") }
            encoded = object["data"] as? String
        case .custom(let path, let isHex):
            var element: Any = object
            for key in path.split(separator: ".") { element = (element as? [String: Any])?[String(key)] ?? NSNull() }
            encoded = element as? String; hex = isHex
        default: break
        }
        guard let encoded = encoded, !encoded.isEmpty else { return nil }
        if !hex {
            guard let data = Data(base64Encoded: encoded) else { throw BuddySettingsError.invalid("语音 Base64 数据无效。") }
            return data
        }
        guard encoded.utf8.count % 2 == 0 else { throw BuddySettingsError.invalid("语音 Hex 数据长度无效。") }
        let values = Array(encoded.utf8)
        func digit(_ c: UInt8) -> UInt8? { switch c { case 48...57: return c - 48; case 65...70: return c - 55; case 97...102: return c - 87; default: return nil } }
        var data = Data(capacity: values.count / 2)
        for index in stride(from: 0, to: values.count, by: 2) {
            guard let a = digit(values[index]), let b = digit(values[index + 1]) else { throw BuddySettingsError.invalid("语音 Hex 数据无效。") }
            data.append(a * 16 + b)
        }
        return data
    }
}
