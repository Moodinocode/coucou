import AppKit
import Foundation

// MARK: - Model

enum CustomPillKind: String, Codable, CaseIterable, Sendable {
    case intellij
    case links

    var subtitle: String {
        switch self {
        case .intellij: return "IntelliJ"
        case .links:    return "Links"
        }
    }

    var defaultColor: String {
        switch self {
        case .intellij: return "#FE315D"
        case .links:    return "#38BDF8"
        }
    }

    /// Kinds that can be created and shown in the current build target.
    static var availableInBuild: [CustomPillKind] {
        #if APPSTORE
        [.links]
        #else
        allCases
        #endif
    }
}

struct CustomPillItem: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var title: String
    /// A folder path (IntelliJ) or an http(s) URL (links).
    var target: String
}

struct CustomPill: Codable, Hashable, Identifiable, Sendable {
    static let idPrefix = "custom_"
    static let palette = ["#FF9900", "#FE315D", "#22C55E", "#38BDF8", "#7C5CFF", "#F5A524", "#E879F9", "#C0C4CC"]

    let id: String
    var name: String
    var color: String
    var kind: CustomPillKind
    var items: [CustomPillItem]
    var includeRecent: Bool = false

    static func newID() -> String {
        idPrefix + UUID().uuidString.prefix(8).lowercased()
    }

    static func newIntelliJ() -> CustomPill {
        CustomPill(id: newID(), name: "IntelliJ", color: CustomPillKind.intellij.defaultColor,
                   kind: .intellij, items: [])
    }

    static func newLinks() -> CustomPill {
        CustomPill(id: newID(), name: "Links", color: CustomPillKind.links.defaultColor,
                   kind: .links, items: [])
    }

    static func awsPreset() -> CustomPill {
        CustomPill(id: newID(), name: "AWS", color: "#FF9900", kind: .links,
                   items: [CustomPillItem(title: "Console", target: "https://console.aws.amazon.com/")])
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var isSingleProject: Bool {
        kind == .intellij && items.count == 1 && !includeRecent
    }

    var definition: PillDefinition {
        PillDefinition(id: id, name: displayName, color: color, category: .custom,
                       subtitle: kind.subtitle, source: .n8n)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, kind, items, includeRecent
    }
}

extension CustomPill {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(CustomPillKind.self, forKey: .kind)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            color: try c.decodeIfPresent(String.self, forKey: .color) ?? kind.defaultColor,
            kind: kind,
            items: try c.decodeIfPresent([CustomPillItem].self, forKey: .items) ?? [],
            includeRecent: try c.decodeIfPresent(Bool.self, forKey: .includeRecent) ?? false
        )
    }
}

/// One line in a custom pill's card: a pinned item or a recent IntelliJ project.
struct CustomPillRow: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let target: String
    /// Trailing detail: branch, else time since last opened (projects), or host (links).
    let detail: String
    /// Full branch name when `detail` shows a branch.
    var branch: String? = nil
    let lastOpened: Date?
    let isRecent: Bool
    let isMissing: Bool
    let kind: CustomPillKind
}

// MARK: - Launcher

@MainActor
enum CustomPillLauncher {
    static let intellijBundleIds = ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]

    static var intellijAppURL: URL? {
        intellijBundleIds.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    static func openProject(path: String) {
        #if !APPSTORE
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            showNote("Folder not found")
            return
        }
        guard let appURL = intellijAppURL else {
            showNote("IntelliJ IDEA isn't installed")
            return
        }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path)],
            withApplicationAt: appURL,
            configuration: .init(),
            completionHandler: nil
        )
        #endif
    }

    static func openLink(_ string: String) {
        guard let url = safeWebURL(string) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The ↗ action of a custom pill.
    static func openPrimary(_ pill: CustomPill) {
        guard let first = pill.items.first else {
            if pill.kind == .intellij && pill.includeRecent {
                activateIntelliJ()
            } else {
                NotificationCenter.default.post(name: .openFullSettings, object: nil)
            }
            return
        }
        switch pill.kind {
        case .intellij:
            if pill.isSingleProject { openProject(path: first.target) } else { activateIntelliJ() }
        case .links:
            openLink(first.target)
        }
    }

    private static func activateIntelliJ() {
        #if !APPSTORE
        if let running = intellijBundleIds.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            running.activate()
            return
        }
        guard let appURL = intellijAppURL else {
            showNote("IntelliJ IDEA isn't installed")
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        #endif
    }

    private static func showNote(_ message: String) {
        let state = AppState.shared
        state.noteMessage = message
        state.view = .note
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }
}

// MARK: - Recent IntelliJ projects

@MainActor
final class RecentProjectsStore: ObservableObject {
    static let shared = RecentProjectsStore()
    static let maxRows = 10

    @Published private(set) var projects: [JetBrainsRecentProject] = []
    /// Current Git branch per normalized project path (pinned and recent projects).
    @Published private(set) var branches: [String: String] = [:]
    private var lastModified: Date?
    private var loading = false

    private init() {}

    /// Re-reads IntelliJ's recent projects (only if the file changed) and every project's branch, off the main thread.
    func refresh() {
        #if !APPSTORE
        guard !loading else { return }
        loading = true
        let since = lastModified
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pinnedPaths = AppState.shared.customPills
            .filter { $0.kind == .intellij }
            .flatMap { $0.items.map { Self.normalize($0.target) } }
        let knownPaths = projects.map(\.path)
        Task { [weak self] in
            let (result, branches) = await Task.detached(priority: .utility) {
                let result = JetBrainsRecentProjects.loadIfChanged(since: since, home: home)
                let paths = Set(pinnedPaths + (result?.projects.map(\.path) ?? knownPaths))
                var branches: [String: String] = [:]
                for path in paths {
                    if let branch = GitBranchReader.currentBranch(at: path) { branches[path] = branch }
                }
                return (result, branches)
            }.value
            guard let self else { return }
            self.loading = false
            if let result {
                self.lastModified = result.modified
                self.projects = result.projects
            }
            if branches != self.branches { self.branches = branches }
        }
        #endif
    }

    func lastOpened(path: String) -> Date? {
        let key = Self.normalize(path)
        return projects.first { $0.path == key }?.lastOpened
    }

    /// Pinned items first, then recent projects not already pinned (when enabled). Capped at 10.
    func rows(for pill: CustomPill) -> [CustomPillRow] {
        var rows: [CustomPillRow] = []
        switch pill.kind {
        case .links:
            rows = pill.items.map { item in
                CustomPillRow(id: item.id, title: item.title, target: item.target,
                              detail: safeWebURL(item.target)?.host ?? "", lastOpened: nil,
                              isRecent: false, isMissing: false, kind: .links)
            }
        case .intellij:
            var pinned = Set<String>()
            for item in pill.items {
                let path = Self.normalize(item.target)
                pinned.insert(path)
                let date = lastOpened(path: path)
                let branch = branches[path]
                rows.append(CustomPillRow(id: item.id, title: item.title, target: item.target,
                                          detail: branch.map(GitBranchReader.shortName) ?? Self.timeAgo(date),
                                          branch: branch, lastOpened: date,
                                          isRecent: false, isMissing: !Self.isDirectory(path),
                                          kind: .intellij))
            }
            if pill.includeRecent {
                for project in projects where !pinned.contains(project.path) {
                    let branch = branches[project.path]
                    rows.append(CustomPillRow(id: "recent:" + project.path, title: project.name,
                                              target: project.path,
                                              detail: branch.map(GitBranchReader.shortName) ?? project.timeAgo,
                                              branch: branch, lastOpened: project.lastOpened, isRecent: true,
                                              isMissing: false, kind: .intellij))
                }
            }
        }
        return Array(rows.prefix(Self.maxRows))
    }

    static func normalize(_ path: String) -> String {
        ((path as NSString).expandingTildeInPath as NSString).standardizingPath
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func timeAgo(_ date: Date?) -> String {
        guard let date else { return "" }
        return JetBrainsRecentProject(path: "", name: "", lastOpened: date).timeAgo
    }
}
