import Foundation

enum CompanionMood { case idle, thinking, speaking }

struct CompanionAnimation {
    static func frame(mood: CompanionMood, elapsed: TimeInterval, reducedMotion: Bool) -> Int {
        if reducedMotion { return 0 }
        switch mood {
        case .idle: return elapsed.truncatingRemainder(dividingBy: 5) > 4.8 ? 1 : 0
        case .thinking: return elapsed.truncatingRemainder(dividingBy: 3) > 2.8 ? 1 : 2
        case .speaking:
            guard elapsed < 5 else { return frame(mood: .idle, elapsed: elapsed, reducedMotion: false) }
            return Int(elapsed / 0.22) % 2 == 0 ? 3 : 0
        }
    }
}
