import SwiftUI
import AppKit

struct PillModesSection: View {
    @ObservedObject private var state = AppState.shared
    @State private var modeHotkeyFlags: UInt = AppState.shared.modeHotkeyFlags
    @State private var modeHotkeyCode: UInt16 = AppState.shared.modeHotkeyCode
    @State private var pendingDeleteId: String?

    private var clashesWithIslandHotkey: Bool {
        state.hotkeyEnabled
            && state.hotkeyFlags == modeHotkeyFlags
            && state.hotkeyCode == modeHotkeyCode
    }

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

                Divider()

                Toggle("Switch mode with shortcut", isOn: $state.modeHotkeyEnabled)
                if state.modeHotkeyEnabled {
                    HStack(spacing: 8) {
                        Text("Shortcut")
                            .frame(width: 70, alignment: .leading)
                        ShortcutRecorderButton(flags: $modeHotkeyFlags, code: $modeHotkeyCode)
                            .onChange(of: modeHotkeyFlags) { _, v in state.modeHotkeyFlags = v }
                            .onChange(of: modeHotkeyCode)  { _, v in state.modeHotkeyCode  = v }
                        Text("presses this → next mode")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if clashesWithIslandHotkey {
                        Text("This is also the shortcut that shows the island. Pick a different one.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
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
