import SwiftUI

struct CustomPillCardView: View {
    let pill: CustomPill
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var recents = RecentProjectsStore.shared

    private var rows: [CustomPillRow] { recents.rows(for: pill) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: pill.color))
                    .frame(width: 7, height: 7)
                Text(pill.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.tail)
                Text(pill.kind.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            if pill.isSingleProject, let row = rows.first {
                singleProject(row)
            } else if rows.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .onAppear { recents.refresh() }
        .onChange(of: appState.mode) { _, mode in
            if mode == .expanded { recents.refresh() }
        }
    }

    private func singleProject(_ row: CustomPillRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1).truncationMode(.tail)
                if !row.detail.isEmpty {
                    RowDetail(row: row, size: 10, color: "#6B7079", maxWidth: 160)
                }
            }
            Text(shortPath(row.target))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#4D5159"))
                .lineLimit(1).truncationMode(.middle)
            if CustomPillLauncher.intellijAppURL == nil {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: "#F4505E")).frame(width: 5, height: 5)
                    Text("IntelliJ IDEA not found")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.top, 2)
            } else {
                Button("Open in IntelliJ") { CustomPillLauncher.openProject(path: row.target) }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: pill.color).opacity(0.85))
                    .buttonStyle(.plain)
                    .padding(.top, 2)
            }
        }
        .opacity(row.isMissing ? 0.5 : 1)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .padding(.top, 6)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Text(pill.kind == .intellij ? "No projects yet" : "No links yet")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
            Button("Settings…") {
                NotificationCenter.default.post(name: .openFullSettings, object: nil)
            }
            .font(.system(size: 11))
            .foregroundColor(Color(hex: "#8E939C"))
            .buttonStyle(.plain)
        }
        .padding(.leading, 108)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var list: some View {
        let stack = VStack(alignment: .leading, spacing: 2) {
            ForEach(rows) { row in
                CustomPillRowView(row: row)
            }
        }
        Group {
            if rows.count > 3 {
                ScrollView(.vertical, showsIndicators: false) { stack }
                    .frame(maxHeight: 66)
            } else {
                stack
            }
        }
        .padding(.leading, 102).padding(.trailing, 12).padding(.top, 5)
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

private struct CustomPillRowView: View {
    let row: CustomPillRow
    @State private var isHovered = false

    private var icon: String {
        switch row.kind {
        case .links:    return "link"
        case .intellij: return row.isRecent ? "clock" : "folder"
        }
    }

    var body: some View {
        Button {
            switch row.kind {
            case .intellij: CustomPillLauncher.openProject(path: row.target)
            case .links:    CustomPillLauncher.openLink(row.target)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 9))
                    .foregroundColor(Color(hex: "#6B7079")).frame(width: 14)
                Text(row.title).font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                Spacer(minLength: 4)
                RowDetail(row: row, size: 9, color: "#4B5563", maxWidth: 110)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(isHovered ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(row.isMissing ? 0.5 : 1)
        .onHover { isHovered = $0 }
    }
}

/// Trailing detail of a row. Branches get a branch glyph, are middle-truncated and show the full name on hover.
private struct RowDetail: View {
    let row: CustomPillRow
    let size: CGFloat
    let color: String
    let maxWidth: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            if row.branch != nil {
                Image(systemName: "arrow.triangle.branch").font(.system(size: size - 1))
            }
            Text(row.detail)
                .font(.system(size: size))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundColor(Color(hex: color))
        .frame(maxWidth: maxWidth, alignment: .trailing)
        .fixedSize(horizontal: false, vertical: true)
        .help(row.branch ?? "")
    }
}
