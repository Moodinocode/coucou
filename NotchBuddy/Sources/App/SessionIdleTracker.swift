import Foundation

/// Last hook activity per session pill. A session whose editor went away without
/// sending SessionEnd is ended once it has been silent for `timeout`.
struct SessionIdleTracker {
    static let defaultTimeout: TimeInterval = 30 * 60

    let timeout: TimeInterval
    private(set) var lastSeen: [String: Date] = [:]

    init(timeout: TimeInterval = SessionIdleTracker.defaultTimeout) {
        self.timeout = timeout
    }

    var isEmpty: Bool { lastSeen.isEmpty }

    mutating func touch(_ id: String, at now: Date) {
        lastSeen[id] = now
    }

    mutating func forget(_ id: String) {
        lastSeen[id] = nil
    }

    /// When the longest-silent pill reaches the timeout; nil when nothing is tracked.
    var nextDeadline: Date? {
        lastSeen.values.min().map { $0.addingTimeInterval(timeout) }
    }

    /// Stops tracking the pills silent for at least `timeout` and returns them, sorted.
    mutating func takeExpired(at now: Date) -> [String] {
        let expired = lastSeen.filter { now.timeIntervalSince($0.value) >= timeout }.keys.sorted()
        for id in expired { lastSeen[id] = nil }
        return expired
    }
}
