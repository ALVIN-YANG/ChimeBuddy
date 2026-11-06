import Foundation
@main struct CompanionAnimationTests {
    static func main() {
        assert(CompanionAnimation.frame(mood: .idle, elapsed: 1, reducedMotion: false) == 0)
        assert(CompanionAnimation.frame(mood: .idle, elapsed: 4.9, reducedMotion: false) == 1)
        assert(CompanionAnimation.frame(mood: .thinking, elapsed: 1, reducedMotion: false) == 2)
        assert(CompanionAnimation.frame(mood: .speaking, elapsed: 0, reducedMotion: false) == 3)
        assert(CompanionAnimation.frame(mood: .speaking, elapsed: 0.3, reducedMotion: false) == 0)
        for mood in [CompanionMood.idle, .thinking, .speaking] {
            assert(CompanionAnimation.frame(mood: mood, elapsed: 4.9, reducedMotion: true) == 0)
        }
        print("PASS: idle blink, thinking, speaking timing, reduced motion")
    }
}
