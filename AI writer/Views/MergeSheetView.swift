import SwiftUI

struct MergeSheetView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    let candidate: MergeCandidate

    var body: some View {
        VStack(spacing: 18) {
            Label("Склеить сцены", systemImage: "arrow.triangle.merge")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 10) {
                previewCard(candidate.target, subtitle: "Целевая сцена")
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                previewCard(candidate.source, subtitle: "Присоединяемая сцена")
            }

            Text("Обе сцены будут объединены в одну. Выберите, какой текст окажется первым.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button("Сначала «\(candidate.target.title.truncated(to: 26))»") {
                    confirm(otherFirst: false)
                }
                .buttonStyle(.borderedProminent)
                Button("Сначала «\(candidate.source.title.truncated(to: 26))»") {
                    confirm(otherFirst: true)
                }
                Button("Отмена", role: .cancel) {
                    workspace.mergeCandidate = nil
                }
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    private func confirm(otherFirst: Bool) {
        Task { await workspace.performMerge(otherFirst: otherFirst) }
    }

    private func previewCard(_ scene: SceneBlock, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(scene.title.isEmpty ? "Без названия" : scene.title)
                .font(.subheadline.bold())
                .lineLimit(1)
            ScrollView {
                Text(scene.content.singleLine.truncated(to: 300))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 110)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }
}
