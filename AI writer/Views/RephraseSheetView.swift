import SwiftUI

struct RephraseSheetView: View {
    let request: RephraseRequest
    let variants: [String]
    let onInsert: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Переформулировать: \(request.style.title)", systemImage: "text.badge.star")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Исходный фрагмент")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(request.originalText.singleLine.truncated(to: 220))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 0) {
                ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                    Button {
                        selectedIndex = index
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(
                                systemName: selectedIndex == index
                                    ? "largecircle.fill.circle"
                                    : "circle"
                            )
                            .foregroundStyle(selectedIndex == index ? Color.accentColor : Color.secondary)
                            .font(.callout)
                            .padding(.top, 2)
                            Text(variant)
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < variants.count - 1 {
                        Divider()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1))
            )

            HStack {
                Spacer()
                Button("Отмена", role: .cancel) {
                    dismiss()
                }
                Button("Вставить вариант") {
                    onInsert(selectedIndex)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
