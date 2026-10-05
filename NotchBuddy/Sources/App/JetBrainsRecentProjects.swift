import Foundation

struct JetBrainsRecentProject: Hashable, Identifiable, Sendable {
    let path: String
    let name: String
    let lastOpened: Date?

    var id: String { path }

    func shortPath(home: String) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    var timeAgo: String {
        guard let lastOpened else { return "" }
        let diff = Date().timeIntervalSince(lastOpened)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

/// Reads IntelliJ IDEA's own list of recent projects (`options/recentProjects.xml`).
enum JetBrainsRecentProjects {
    static let maxProjects = 15

    /// The most recently modified `recentProjects.xml` among IntelliJ IDEA (Ultimate or CE) config folders.
    static func recentProjectsFile(home: URL) -> URL? {
        let fm = FileManager.default
        let root = home.appendingPathComponent("Library/Application Support/JetBrains", isDirectory: true)
        guard let dirs = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }
        var best: (url: URL, date: Date)?
        for dir in dirs where dir.hasPrefix("IntelliJIdea") || dir.hasPrefix("IdeaIC") {
            let file = root.appendingPathComponent(dir).appendingPathComponent("options/recentProjects.xml")
            guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                  let date = attrs[.modificationDate] as? Date else { continue }
            if best == nil || date > best!.date { best = (file, date) }
        }
        return best?.url
    }

    /// Re-parses only when the file changed since `since`. Returns nil when nothing changed or no file exists.
    static func loadIfChanged(since: Date?, home: URL) -> (modified: Date, projects: [JetBrainsRecentProject])? {
        guard let file = recentProjectsFile(home: home),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        if let since, since == modified { return nil }
        guard let data = try? Data(contentsOf: file) else { return nil }
        let projects = parse(data, home: home.path) { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
        return (modified, projects)
    }

    static func parse(_ data: Data, home: String, fileExists: (String) -> Bool) -> [JetBrainsRecentProject] {
        let delegate = RecentProjectsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        var seen = Set<String>()
        var result: [JetBrainsRecentProject] = []
        for entry in delegate.entries {
            let expanded = entry.key.replacingOccurrences(of: "$USER_HOME$", with: home)
            guard !expanded.contains("$"), expanded.hasPrefix("/") else { continue }
            let path = (expanded as NSString).standardizingPath
            guard !seen.contains(path), fileExists(path) else { continue }
            seen.insert(path)
            let ms = entry.activation ?? entry.open
            let date = ms.map { Date(timeIntervalSince1970: $0 / 1000) }
            result.append(JetBrainsRecentProject(path: path, name: (path as NSString).lastPathComponent, lastOpened: date))
        }
        result.sort { a, b in
            switch (a.lastOpened, b.lastOpened) {
            case let (x?, y?): return x > y
            case (_?, nil):    return true
            default:           return false
            }
        }
        return Array(result.prefix(maxProjects))
    }
}

private final class RecentProjectsParser: NSObject, XMLParserDelegate {
    struct Entry {
        let key: String
        var activation: Double?
        var open: Double?
    }

    private(set) var entries: [Entry] = []
    private var mapDepth = 0
    private var entryDepth = 0
    private var current: Entry?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "map":
            mapDepth += 1
        case "entry":
            entryDepth += 1
            if entryDepth == 1, mapDepth > 0, let key = attributes["key"] {
                current = Entry(key: key)
            }
        case "option":
            guard current != nil, let name = attributes["name"],
                  let value = attributes["value"].flatMap(Double.init) else { return }
            if name == "activationTimestamp" { current?.activation = value }
            else if name == "projectOpenTimestamp" { current?.open = value }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "map":
            mapDepth = max(0, mapDepth - 1)
        case "entry":
            if entryDepth == 1, let entry = current {
                entries.append(entry)
                current = nil
            }
            entryDepth = max(0, entryDepth - 1)
        default:
            break
        }
    }
}
