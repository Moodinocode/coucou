import AppKit
import SwiftUI

struct CustomPillsSection: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        GroupBox("My pills") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your own launchers: IntelliJ projects or links. Turn them on in Active pills below.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                ForEach(state.customPills) { pill in
                    CustomPillEditor(pill: binding(for: pill.id))
                    Divider()
                }

                HStack(spacing: 8) {
                    #if !APPSTORE
                    Button("Add IntelliJ pill") { state.addCustomPill(.newIntelliJ()) }
                    #endif
                    Menu("Add links pill") {
                        Button("Empty") { state.addCustomPill(.newLinks()) }
                        Button("AWS") { state.addCustomPill(.awsPreset()) }
                    }
                    .fixedSize()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(6)
        }
        .onAppear { RecentProjectsStore.shared.refresh() }
    }

    private func binding(for id: String) -> Binding<CustomPill> {
        let fallback = state.customPill(id: id) ?? .newLinks()
        return Binding(
            get: { state.customPill(id: id) ?? fallback },
            set: { newValue in
                if let idx = state.customPills.firstIndex(where: { $0.id == id }) {
                    state.customPills[idx] = newValue
                }
            }
        )
    }
}

private struct CustomPillEditor: View {
    @Binding var pill: CustomPill
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var recents = RecentProjectsStore.shared
    @State private var confirmingDelete = false
    @State private var newTitle = ""
    @State private var newURL = ""

    private static let maxItems = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: pill.color)).frame(width: 10, height: 10)
                TextField("Name", text: $pill.name)
                    .textFieldStyle(.roundedBorder)
                Text(pill.kind.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .confirmationDialog("Delete \(pill.displayName)?", isPresented: $confirmingDelete) {
                    Button("Delete", role: .destructive) { state.deleteCustomPill(id: pill.id) }
                    Button("Cancel", role: .cancel) {}
                }
            }

            HStack(spacing: 6) {
                ForEach(CustomPill.palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(pill.color == hex ? 0.8 : 0), lineWidth: 1.5)
                                .padding(-3)
                        )
                        .contentShape(Circle())
                        .onTapGesture { pill.color = hex }
                }
            }
            .padding(.leading, 3)

            ForEach(pill.items) { item in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .lineLimit(1).truncationMode(.tail)
                        Text(pill.kind == .intellij ? shortPath(item.target) : item.target)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        pill.items.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            switch pill.kind {
            case .intellij:
                #if !APPSTORE
                intellijControls
                #else
                EmptyView()
                #endif
            case .links:
                linksControls
            }
        }
    }

    #if !APPSTORE
    private var unpinnedRecents: [JetBrainsRecentProject] {
        let pinned = Set(pill.items.map { RecentProjectsStore.normalize($0.target) })
        return recents.projects.filter { !pinned.contains($0.path) }
    }

    private var isFull: Bool { pill.items.count >= Self.maxItems }

    private var intellijControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Menu("Add recent project") {
                    ForEach(unpinnedRecents) { project in
                        Button(project.name) { addProject(path: project.path, title: project.name) }
                    }
                }
                .fixedSize()
                .disabled(unpinnedRecents.isEmpty || isFull)
                Button("Choose folder…") { chooseFolders() }
                    .disabled(isFull)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if recents.projects.isEmpty {
                Text("No recent projects found")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Toggle("Include recent projects", isOn: $pill.includeRecent)
                .toggleStyle(.checkbox)
        }
    }

    private func addProject(path: String, title: String) {
        let key = RecentProjectsStore.normalize(path)
        guard pill.items.count < Self.maxItems,
              !pill.items.contains(where: { RecentProjectsStore.normalize($0.target) == key }) else { return }
        pill.items.append(CustomPillItem(title: title, target: key))
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.prompt = "Add"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addProject(path: url.path, title: url.lastPathComponent)
        }
    }
    #endif

    private var trimmedURL: String { newURL.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var linksControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Title", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                TextField("https://…", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addLink() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(safeWebURL(trimmedURL) == nil)
            }
            if !trimmedURL.isEmpty && safeWebURL(trimmedURL) == nil {
                Text("Enter an http(s) link")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
        }
    }

    private func addLink() {
        let urlString = trimmedURL
        guard let url = safeWebURL(urlString) else { return }
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        pill.items.append(CustomPillItem(title: title.isEmpty ? (url.host ?? urlString) : title, target: urlString))
        newTitle = ""
        newURL = ""
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
