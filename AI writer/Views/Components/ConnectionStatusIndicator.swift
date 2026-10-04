import SwiftUI

/// Индикатор подключения: цветной кружок + текст статуса.
///
/// Используется в окне подключения и в селекторе моделей, поэтому вынесен
/// в отдельный файл, чтобы состояние выглядело одинаково в обоих местах.
struct ConnectionStatusIndicator: View {
    let status: ConnectionStatus
    /// Показывать ли текст статуса рядом с кружком.
    var showsTitle: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)
                .overlay {
                    if status.isChecking {
                        Circle()
                            .stroke(indicatorColor.opacity(0.4), lineWidth: 5)
                            .frame(width: 16, height: 16)
                    }
                }
                .accessibilityLabel(Text(status.title))

            if showsTitle {
                Text(status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var indicatorColor: Color {
        switch status.color {
        case .green: .green
        case .red: .red
        case .yellow: .yellow
        case .secondary: .secondary
        }
    }
}
