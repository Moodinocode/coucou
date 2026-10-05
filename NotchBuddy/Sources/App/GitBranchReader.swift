import Foundation

/// Reads a repository's current branch straight from `.git/HEAD` (no `git` process). Handles worktrees.
enum GitBranchReader {
    /// The branch checked out at `projectPath`, a 7-char hash when detached, or nil if it isn't a Git repo.
    static func currentBranch(at projectPath: String) -> String? {
        guard let gitDir = gitDirectory(for: projectPath),
              let head = try? String(contentsOfFile: gitDir + "/HEAD", encoding: .utf8)
        else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref:") {
            let ref = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let prefix = "refs/heads/"
            return ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
        }
        return line.isEmpty ? nil : String(line.prefix(7))
    }

    /// Short form for tight spaces: drops a `feature/`-style prefix ("feature/TEC-1-x" → "TEC-1-x").
    static func shortName(_ branch: String) -> String {
        guard let slash = branch.lastIndex(of: "/"), branch.index(after: slash) < branch.endIndex else { return branch }
        return String(branch[branch.index(after: slash)...])
    }

    private static func gitDirectory(for projectPath: String) -> String? {
        let dotGit = (projectPath as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }
        // Worktree or submodule: `.git` is a file containing "gitdir: <path>".
        guard let contents = try? String(contentsOfFile: dotGit, encoding: .utf8),
              let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let absolute = path.hasPrefix("/") ? path : (projectPath as NSString).appendingPathComponent(path)
        return (absolute as NSString).standardizingPath
    }
}
