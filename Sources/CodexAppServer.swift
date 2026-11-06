import Foundation

/// Short-lived, read-only JSON-RPC connection to the bundled Codex runtime.
final class CodexAppServer {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private var deadline: DispatchWorkItem?

    init(clientName: String) throws {
        process.executableURL = URL(fileURLWithPath: CodexReviewer.executable)
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let child = process
        let timeout = DispatchWorkItem {
            if child.isRunning {
                child.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                    if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                }
            }
        }
        deadline = timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        do {
            _ = try call("initialize", params: ["clientInfo": ["name": clientName, "version": "0.1"]])
            try send(["method": "initialized"])
        } catch { close(); throw error }
    }

    func call(_ method: String, params: [String: Any]) throws -> [String: Any] {
        nextID += 1
        let id = nextID
        try send(["id": id, "method": method, "params": params])
        while true {
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any], object["id"] as? Int == id else { continue }
                guard object["error"] == nil, let result = object["result"] as? [String: Any] else {
                    throw NSError(domain: "ChimeBuddy", code: 6, userInfo: [NSLocalizedDescriptionKey: "Codex 未返回可读取的数据"])
                }
                return result
            }
            let data = output.fileHandleForReading.availableData
            guard !data.isEmpty else {
                throw NSError(domain: "ChimeBuddy", code: 5, userInfo: [NSLocalizedDescriptionKey: "Codex 读取超时或连接已关闭"])
            }
            buffer.append(data)
        }
    }

    private func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try input.fileHandleForWriting.write(contentsOf: data + Data([10]))
    }
    private func close() {
        deadline?.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
    deinit { close() }
}
