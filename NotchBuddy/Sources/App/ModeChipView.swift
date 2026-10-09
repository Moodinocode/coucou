import SwiftUI

struct ModeChip: View {
    @ObservedObject var state: AppState
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(state.pillModes) { mode in
                Button {
                    if state.switchPillMode(to: mode.id) {
                        SoundEngine.shared.play("blip")
                    }
                } label: {
                    if mode.id == state.currentPillModeId {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
                .disabled(state.pendingApproval != nil && mode.id != state.currentPillModeId)
            }
            Divider()
            Button("Edit modes…") {
                NotificationCenter.default.post(name: .openFullSettings, object: nil)
            }
        } label: {
            HStack(spacing: 4) {
                Text(state.currentPillMode?.displayName ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundColor(isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C"))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .frame(maxWidth: 90)
            .background(isHovered ? Color.white.opacity(0.07) : Color.clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
    }
}
