import Foundation
@main struct SessionReviewsTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let reviews = SessionReviews(directory: directory)
        func value(_ session: String, _ mode: String, _ date: Double, _ text: String) -> SavedReview {
            SavedReview(sessionID: session, mode: mode, eventID: String(date), eventDate: Date(timeIntervalSince1970: date), text: text)
        }
        try reviews.save(value("A", "roast", 1, "A 的吐槽"))
        assert(reviews.review(sessionID: "B", mode: "roast") == nil)
        try reviews.save(value("B", "roast", 2, "B 的吐槽"))
        // A completes late while B is displayed; save to A, never B.
        try reviews.save(value("A", "roast", 3, "A 的新吐槽"))
        assert(reviews.review(sessionID: "B", mode: "roast")?.text == "B 的吐槽")
        assert(reviews.review(sessionID: "A", mode: "roast")?.text == "A 的新吐槽")
        try reviews.save(value("A", "roast", 1, "过期结果"))
        assert(reviews.review(sessionID: "A", mode: "roast")?.text == "A 的新吐槽")
        assert(reviews.review(sessionID: "A", mode: "expert") == nil)
        let restored = SessionReviews(directory: directory)
        assert(restored.review(sessionID: "B", mode: "roast")?.text == "B 的吐槽")
        print("PASS: per-session review restore, late completion isolation, stale result rejection, mode isolation, persistence")
    }
}
