import AppKit
import Foundation

/// Read-only by default. --roast explicitly replays the latest real message
/// through the production request/cache path; it does not send a chat message.
@main struct ProbeCurrent {
    static func main() throws {
        let storage = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ChimeBuddy")
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        let codex = applications.count == 1 ? applications.first : nil
        guard let page = DesktopSelectionReader().read(processID: codex?.processIdentifier, processStartedAt: codex?.launchDate), let id = page.sessionID,
              let metadata = try CodexThreadTitles.fetch(ids: [id]).first, let path = metadata.path else {
            print("{\"state\":\"selection_unavailable\"}")
            exit(1)
        }
        let events = SessionTranscript(sessionID: id, url: URL(fileURLWithPath: path)).read().sorted { $0.receivedAt < $1.receivedAt }
        let state = RoastState(cache: SessionReviews(directory: storage))
        state.sessions.select(id)
        state.sessions.updateTitle(metadata.name, for: id)
        let replay = CommandLine.arguments.contains("--roast")
        var invoked = false
        for event in events {
            let live = replay && event.id == events.last?.id
            if let request = state.receive(event, live: live) {
                let answer = try CodexReviewer.review(context: request.context)
                try state.complete(request, text: answer)
                invoked = true
            }
        }
        let output: [String: Any] = ["state": "current", "sessionID": id, "name": state.sessions.title(for: id),
                                    "historyMessages": state.sessions.history.count, "latestKind": events.last?.kind ?? "",
                                    "modelInvoked": invoked, "cachedRoast": state.text ?? ""]
        let json = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(data: json, encoding: .utf8)!)
    }
}
