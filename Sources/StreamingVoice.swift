import Foundation

enum VoiceStatus: Equatable {
    case idle, connecting, playing, completed, stopped, failed(String)
    var text: String { switch self {
    case .idle: return "尚未试听"
    case .connecting: return "正在连接…"
    case .playing: return "正在流式播放…"
    case .completed: return "播放完成"
    case .stopped: return "已停止"
    case .failed(let reason): return reason
    } }
}

/// One foreground utterance owns the network and audio queue. Task identity
/// rejects late callbacks after interruption, settings changes, or chat switch.
final class StreamingVoice: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    var onStatus: ((VoiceStatus) -> Void)?
    var onFinished: (() -> Void)?
    var onMetrics: (([String: Any]) -> Void)?
    private(set) var status: VoiceStatus = .idle
    private var session: URLSession?
    private var task: URLSessionTask?
    private var receiveTask: Task<Void, Never>?
    private var decoder: TTSStreamDecoder?
    private var player: PCMStreamPlayer?
    private var deadline: Timer?
    private var generation = UUID()
    private var opened = Date()
    private var firstAudio: TimeInterval?
    private var networkEnded = false
    private var receivedBytes = 0
    private var wsStarted = false

    func speak(_ request: TTSRequest, outputDeviceUID: String? = nil) throws {
        stop(notify: false)
        let token = generation
        opened = Date(); firstAudio = nil; networkEnded = false; receivedBytes = 0; wsStarted = false
        decoder = TTSStreamDecoder(format: request.format)
        let output = try PCMStreamPlayer(sampleRate: request.sampleRate, outputDeviceUID: outputDeviceUID)
        player = output
        output.onStart = { [weak self] in guard let self = self, self.generation == token else { return }; self.update(.playing) }
        output.onFinish = { [weak self] result in
            guard let self = self, self.generation == token else { return }
            switch result { case .success: self.end(.completed); case .failure(let error): self.end(.failed(error.localizedDescription)) }
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 90
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        update(.connecting)
        deadline = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            guard let self = self, self.generation == token else { return }
            self.end(.failed("语音超过 120 秒，已停止。"))
        }
        if request.format == .cosyVoice {
            let websocket = session.webSocketTask(with: request.request)
            task = websocket; websocket.maximumMessageSize = 2_000_000; websocket.resume()
            receiveTask = Task { @MainActor [weak self] in
                do {
                    let data = try JSONSerialization.data(withJSONObject: request.websocketStart!)
                    try await websocket.send(.string(String(data: data, encoding: .utf8)!))
                    while !Task.isCancelled {
                        let message = try await websocket.receive()
                        guard let self = self, self.generation == token else { return }
                        switch message {
                        case .data(let bytes): try self.audio(bytes)
                        case .string(let string):
                            guard let object = try JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any],
                                  let header = object["header"] as? [String: Any], header["task_id"] as? String == request.taskID else { continue }
                            switch header["event"] as? String {
                            case "task-started":
                                guard !self.wsStarted else { continue }; self.wsStarted = true
                                try await websocket.send(.string(try request.websocketMessage("continue-task", input: ["text": request.text])))
                                try await websocket.send(.string(try request.websocketMessage("finish-task", input: [:])))
                            case "task-finished": try self.finishInput(); return
                            case "task-failed": throw BuddySettingsError.invalid("CosyVoice 合成失败，请检查区域、模型、音色及额度。")
                            default: break
                            }
                        @unknown default: break
                        }
                    }
                } catch {
                    guard let self = self, self.generation == token else { return }
                    self.end(.failed("WebSocket 语音连接失败，请检查配置和网络。"))
                }
            }
        } else {
            let task = session.dataTask(with: request.request); self.task = task; task.resume()
        }
    }
    func stop(notify: Bool = true) {
        let wasActive = task != nil || player != nil
        cleanup()
        if notify && wasActive { update(.stopped); onFinished?() }
    }
    private func cleanup() {
        generation = UUID()
        deadline?.invalidate(); deadline = nil
        receiveTask?.cancel(); receiveTask = nil
        task?.cancel(); task = nil
        session?.invalidateAndCancel(); session = nil
        player?.stop(); player = nil
        decoder = nil
    }
    private func update(_ value: VoiceStatus) { status = value; onStatus?(value) }
    private func end(_ status: VoiceStatus) {
        let metrics: [String: Any] = ["state": "voiceFinished", "audioBytes": receivedBytes,
            "consumedBytes": player?.consumedBytes ?? 0, "underruns": player?.underruns ?? 0,
            "firstAudioMs": firstAudio.map { Int($0 * 1000) } ?? -1,
            "elapsedMs": Int(Date().timeIntervalSince(opened) * 1000), "completed": status == .completed]
        cleanup(); update(status); onMetrics?(metrics); onFinished?()
    }
    private func audio(_ bytes: Data) throws {
        guard !bytes.isEmpty else { return }
        if firstAudio == nil { firstAudio = Date().timeIntervalSince(opened) }
        receivedBytes += bytes.count
        try player?.append(bytes)
    }
    private func finishInput() throws {
        guard !networkEnded else { return }; networkEnded = true
        deadline?.invalidate()
        // Playback can continue after the final network event, with a finite
        // deadline in case a device route disappears without returning buffers.
        let token = generation
        deadline = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            guard let self = self, self.generation == token else { return }; self.end(.failed("音频设备未完成播放。"))
        }
        try player?.finish()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask === task else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            end(.failed("语音请求失败，HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)。请检查密钥、音色和额度。")); return
        }
        let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if decoder?.format == .pcm && (type.contains("json") || type.contains("text/") || type.contains("audio/mpeg") || type.contains("audio/wav")) {
            completionHandler(.cancel); end(.failed("服务没有返回原始 PCM，请检查流格式。")); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === task, !networkEnded else { return }
        do { for chunk in try decoder?.append(data) ?? [] { try audio(chunk) } }
        catch { end(.failed(error.localizedDescription)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task, !networkEnded else { return }
        if task is URLSessionWebSocketTask {
            // The receive loop owns terminal-event ordering. A task completion
            // callback can arrive while a final WebSocket message is queued.
            return
        }
        do {
            if let error = error { throw BuddySettingsError.invalid("语音传输中断（网络码 \((error as NSError).code)），请检查网络后重试。") }
            for chunk in try decoder?.close() ?? [] { try audio(chunk) }
            try finishInput()
        } catch { end(.failed(error.localizedDescription)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the user's credentials across a redirect.
        completionHandler(nil)
    }
}
