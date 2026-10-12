import Foundation

@main
enum SessionIdleTrackerTests {
    static func main() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

        // Nothing tracked: no deadline, nothing expires
        var tracker = SessionIdleTracker()
        precondition(tracker.timeout == 30 * 60)
        precondition(tracker.isEmpty)
        precondition(tracker.nextDeadline == nil)
        precondition(tracker.takeExpired(at: at(999)).isEmpty)

        // One pill: deadline is last activity + timeout
        tracker.touch("integration_claude", at: at(0))
        precondition(!tracker.isEmpty)
        precondition(tracker.nextDeadline == at(30))
        precondition(tracker.takeExpired(at: at(29.9)).isEmpty)

        // Activity pushes the deadline back
        tracker.touch("integration_claude", at: at(20))
        precondition(tracker.nextDeadline == at(50))
        precondition(tracker.takeExpired(at: at(30)).isEmpty)

        // Several pills: the deadline is the longest-silent one, and only that one expires
        tracker.touch("agent_cursor", at: at(5))
        precondition(tracker.nextDeadline == at(35))
        precondition(tracker.takeExpired(at: at(35)) == ["agent_cursor"])
        precondition(tracker.nextDeadline == at(50))

        // Expired pills are no longer tracked
        precondition(tracker.takeExpired(at: at(50)) == ["integration_claude"])
        precondition(tracker.isEmpty)
        precondition(tracker.nextDeadline == nil)

        // Several pills expiring together come back sorted
        tracker.touch("agent_b", at: at(0))
        tracker.touch("agent_a", at: at(1))
        precondition(tracker.takeExpired(at: at(60)) == ["agent_a", "agent_b"])

        // Forgetting a pill (SessionEnd) drops it
        tracker.touch("agent_codex", at: at(0))
        tracker.forget("agent_codex")
        precondition(tracker.isEmpty)
        tracker.forget("never_seen")
        precondition(tracker.isEmpty)

        // Custom timeout
        var short = SessionIdleTracker(timeout: 60)
        short.touch("x", at: at(0))
        precondition(short.takeExpired(at: at(0.5)).isEmpty)
        precondition(short.takeExpired(at: at(1)) == ["x"])

        print("Session idle tracker: 20 cases passed")
    }
}
