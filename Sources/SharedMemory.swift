import Foundation

struct MemoryFact: Codable, Equatable {
    let key: String
    let value: String
    var line: String { key + "：" + value }
}

struct BuddyAnswer: Codable {
    let text: String
    let profileUpdates: [MemoryFact]
    let projectUpdates: [MemoryFact]
    var action: String? = nil
}

struct MemorySnapshot: Codable {
    var profile: [MemoryFact] = []
    var projects: [MemoryFact] = []
    var profileText: String { profile.map(\.line).joined(separator: "\n") }
    var projectsText: String { projects.map(\.line).joined(separator: "\n") }
}

/// Only compact facts cross chats. No quotations, chat transcripts or roasts.
/// Mutations run on the main thread; each request carries an edit generation so
/// an in-flight extraction cannot resurrect facts after a manual clear/edit.
final class SharedMemory {
    static let profileLimit = 400
    static let projectsLimit = 800
    private(set) var snapshot = MemorySnapshot()
    private(set) var editGeneration = UUID()
    private var factDates: [String: Date] = [:]
    private let file: URL
    init(directory: URL) {
        file = directory.appendingPathComponent("shared-memory.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(MemorySnapshot.self, from: data) {
            snapshot.profile = Self.bounded(saved.profile, limit: Self.profileLimit)
            snapshot.projects = Self.bounded(saved.projects, limit: Self.projectsLimit)
        }
    }
    func apply(_ answer: BuddyAnswer, source: HookEvent, generation: UUID) throws {
        guard generation == editGeneration, !source.simulated,
              ["UserPromptSubmit", "BuddyReply"].contains(source.kind) else { return }
        let date = source.receivedAt
        var updated = snapshot
        var dates = factDates
        func merge(_ facts: [MemoryFact], _ updates: [MemoryFact], prefix: String, limit: Int) -> [MemoryFact] {
            var result = facts
            let concise = updates.prefix(2).map { MemoryFact(key: $0.key, value: String($0.value.prefix(80))) }
            for fact in Self.bounded(concise, limit: limit) {
                let identity = prefix + fact.key.lowercased()
                guard dates[identity, default: .distantPast] <= date else { continue }
                result.removeAll { $0.key.lowercased() == fact.key.lowercased() }
                result.append(fact)
                dates[identity] = date
            }
            return Self.bounded(result, limit: limit)
        }
        updated.profile = merge(updated.profile, answer.profileUpdates, prefix: "user:", limit: Self.profileLimit)
        updated.projects = merge(updated.projects, answer.projectUpdates, prefix: "project:", limit: Self.projectsLimit)
        guard updated.profile != snapshot.profile || updated.projects != snapshot.projects else { return }
        try save(updated)
        snapshot = updated; factDates = dates
    }
    func replace(profile: String, projects: String) throws {
        guard profile.count <= Self.profileLimit, projects.count <= Self.projectsLimit else {
            throw NSError(domain: "ChimeBuddy", code: 10, userInfo: [NSLocalizedDescriptionKey: "画像最多 400 字，项目概况合计最多 800 字。"])
        }
        func facts(_ text: String) -> [MemoryFact] {
            text.split(separator: "\n").enumerated().map { index, line in
                let value = String(line)
                if let colon = value.firstIndex(where: { $0 == ":" || $0 == "：" }) {
                    return MemoryFact(key: String(value[..<colon]), value: String(value[value.index(after: colon)...]))
                }
                return MemoryFact(key: "备注\(index + 1)", value: value)
            }
        }
        let updated = MemorySnapshot(profile: Self.bounded(facts(profile), limit: Self.profileLimit),
                                     projects: Self.bounded(facts(projects), limit: Self.projectsLimit))
        try save(updated)
        snapshot = updated; factDates = [:]; editGeneration = UUID()
    }
    private func save(_ value: MemorySnapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func bounded(_ facts: [MemoryFact], limit: Int) -> [MemoryFact] {
        var result: [MemoryFact] = []
        for fact in facts {
            let key = String(fact.key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            let value = String(fact.value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max(0, limit - key.count - 1)))
            guard !key.isEmpty, !value.isEmpty else { continue }
            result.removeAll { $0.key.lowercased() == key.lowercased() }
            result.append(MemoryFact(key: key, value: value))
            while result.map(\.line).joined(separator: "\n").count > limit { result.removeFirst() }
        }
        return result
    }
}
