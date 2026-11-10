import Foundation

struct SavedReview: Codable, Equatable {
    let sessionID: String
    let mode: String
    let eventID: String
    let eventDate: Date
    let text: String
    var action: String? = nil
}

/// Results belong to the conversation that produced their context, including
/// responses that finish after the user has moved to another conversation.
final class SessionReviews {
    private var entries: [String: [String: SavedReview]] = [:]
    private let file: URL
    init(directory: URL) {
        file = directory.appendingPathComponent("reviews.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: [String: SavedReview]].self, from: data) {
            entries = saved
        }
    }
    func review(sessionID: String, mode: String) -> SavedReview? { entries[sessionID]?[mode] }
    func save(_ value: SavedReview) throws {
        if let previous = review(sessionID: value.sessionID, mode: value.mode), previous.eventDate > value.eventDate { return }
        var updated = entries
        updated[value.sessionID, default: [:]][value.mode] = value
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(updated).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        entries = updated
    }
}
