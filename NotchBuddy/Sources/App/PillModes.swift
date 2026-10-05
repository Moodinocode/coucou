import Foundation

/// A named preset of active pills plus a main pill ("Work", "Personal").
struct PillMode: Codable, Hashable, Identifiable, Sendable {
    static let idPrefix = "mode_"
    static let maxActive = 4

    let id: String
    var name: String
    var activePills: [String]
    var mainPillId: String

    static func newID() -> String {
        idPrefix + UUID().uuidString.prefix(8).lowercased()
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
