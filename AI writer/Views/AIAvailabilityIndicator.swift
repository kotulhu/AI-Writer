import SwiftUI

/// Маленький индикатор доступности AI в тулбаре:
/// зелёный кружок — модель подключена, серый — нет.
/// По нажатию открывает настройки.
struct AIAvailabilityIndicator: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(workspace.hasActiveProvider ? Color.green : Color.gray)
                    .frame(width: 9, height: 9)
                Text("AI")
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.borderless)
        .help(workspace.hasActiveProvider ? "AI подключён — открыть настройки" : "AI не подключён — настроить")
    }
}
