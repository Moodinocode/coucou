import SwiftUI
import AppKit

struct PillModesSection: View {
    @ObservedObject private var state = AppState.shared
    @State private var pendingDeleteId: String?

    var body: some View {
        GroupBox("Modes") {
            VStack(alignment: .leading, spacing: 10) {
                Text("A mode remembers your active pills and main pill. Switch from the menu bar, the island, or a shortcut. Changes below save to the current mode.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(state.pillModes) { mode in
                    modeRow(mode)
                }

                Button("Add mode") {
                    _ = state.addPillMode(name: "Mode \(state.pillModes.count + 1)")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.pendingApproval != nil)

                Text("Set a shortcut to switch modes in Shortcuts → Switch mode.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(6)
        }
        .confirmationDialog(
            "Delete this mode?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            presenting: pendingDeleteId
        ) { id in
            Button("Delete", role: .destructive) { state.deletePillMode(id: id) }
            Button("Cancel", role: .cancel) {}
        } message: { id in
            let name = state.pillModes.first { $0.id == id }?.displayName ?? ""
            Text("\"\(name)\" and its pill selection will be removed.")
        }
    }

    private func modeRow(_ mode: PillMode) -> some View {
        let isCurrent = mode.id == state.currentPillModeId
        return HStack(spacing: 8) {
            Button {
                state.switchPillMode(to: mode.id)
            } label: {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isCurrent ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(state.pendingApproval != nil && !isCurrent)
            .help(isCurrent ? "Current mode" : "Switch to this mode")

            TextField("Mode name", text: Binding(
                get: { state.pillModes.first { $0.id == mode.id }?.name ?? "" },
                set: { state.renamePillMode(id: mode.id, name: $0) }
            ))
            .textFieldStyle(.roundedBorder)

            Button {
                _ = state.duplicatePillMode(id: mode.id)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .disabled(state.pendingApproval != nil)
            .help("Duplicate")

            Button {
                pendingDeleteId = mode.id
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(state.pillModes.count <= 1)
            .help("Delete")
        }
    }
}
