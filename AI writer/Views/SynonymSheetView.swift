import SwiftUI

struct SynonymSheetView: View {
    let request: SynonymRequest
    let variants: [String]
    let onInsert: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                "Синонимы к «\(request.originalFragment.singleLine.truncated(to: 28))»",
                systemImage: "character.book.closed"
            )
            .font(.title3.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Исходный фрагмент")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(request.originalFragment.singleLine.truncated(to: 220))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                        Button {
                            selectedIndex = index
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(
                                    systemName: selectedIndex == index
                                        ? "largecircle.fill.circle"
                                        : "circle"
                                )
                                .foregroundStyle(selectedIndex == index ? Color.accentColor : Color.secondary)
                                .font(.callout)
                                Text(variant)
                                    .font(.callout)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if variant.split(separator: " ").count > 1 {
                                    Text("фраза")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(nsColor: .quaternarySystemFill))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < variants.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(height: 260)
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
        .frame(width: 520)
    }
}
