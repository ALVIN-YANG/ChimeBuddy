import Foundation

struct CodexThreadTitle {
    let id: String
    let name: String?
    let path: String?
}

/// Reads metadata through the public protocol. Does not resume a conversation,
/// invoke a model, or parse private database files.
enum CodexThreadTitles {
    static func fetch(ids: [String]) throws -> [CodexThreadTitle] {
        guard !ids.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CodexReviewer.executable)
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: deadline)
        defer {
            deadline.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        var buffer = Data()
        func send(_ object: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            try input.fileHandleForWriting.write(contentsOf: data + Data([10]))
        }
        func response(_ id: Int) throws -> [String: Any] {
            while true {
                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: newline)
                    buffer.removeSubrange(...newline)
                    if let object = try JSONSerialization.jsonObject(with: line) as? [String: Any], object["id"] as? Int == id {
                        return object
                    }
                }
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else {
                    throw NSError(domain: "ChimeBuddy", code: 5, userInfo: [NSLocalizedDescriptionKey: "Codex 会话名称读取超时或连接已关闭"])
                }
                buffer.append(chunk)
            }
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "chimebuddy_titles", "version": "0.1"]]])
        let initial = try response(1)
        guard initial["error"] == nil else {
            throw NSError(domain: "ChimeBuddy", code: 6, userInfo: [NSLocalizedDescriptionKey: "Codex 拒绝会话名称连接"])
        }
        try send(["method": "initialized"])
        var titles: [CodexThreadTitle] = []
        for (offset, threadID) in ids.enumerated() {
            let requestID = offset + 2
            try send(["id": requestID, "method": "thread/read", "params": ["threadId": threadID, "includeTurns": false]])
            let result = try response(requestID)
            // Missing ephemeral/deleted threads do not erase previously read names.
            if let value = result["result"] as? [String: Any], let thread = value["thread"] as? [String: Any] {
                guard thread["id"] as? String == threadID, thread["ephemeral"] as? Bool != true else { continue }
                titles.append(CodexThreadTitle(id: threadID, name: thread["name"] as? String, path: thread["path"] as? String))
            }
        }
        return titles
    }
}
