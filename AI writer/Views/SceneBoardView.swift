import SwiftUI

struct SceneBoardView: View {
    @Environment(WorkspaceViewModel.self) private var workspace

    var body: some View {
        HStack(spacing: 0) {
            board
                .frame(width: 330)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            SceneEditorPane()
        }
        .navigationTitle(workspace.selectedManuscript?.title ?? "AI Writer")
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Сцены")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await workspace.addScene() }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Добавить сцену")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if workspace.scenes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(
                            Array(workspace.scenes.enumerated()),
                            id: \.element.id
                        ) { index, scene in
                            GapDropZone(index: index)
                            SceneCardView(scene: scene)
                        }
                        GapDropZone(index: workspace.scenes.count)
                        Color.clear.frame(height: 20)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Пока нет сцен",
                systemImage: "rectangle.stack.badge.plus",
                description: Text("Добавьте первую сцену — её можно будет перетаскивать и склеивать с другими.")
            )
            Button("Добавить сцену") {
                Task { await workspace.addScene() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SceneCardView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    let scene: SceneBlock
    @State private var isDropTargeted = false

    var body: some View {
        let isSelected = workspace.selectedSceneID == scene.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.justify.left")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                Text(scene.title.isEmpty ? "Без названия" : scene.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button("Дублировать") {
                        Task { await workspace.duplicateScene(scene.id) }
                    }
                    Divider()
                    Button("Удалить сцену", role: .destructive) {
                        Task { await workspace.deleteScene(scene.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Text(scene.content.singleLine.truncated(to: 170))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(minHeight: 18, alignment: .topLeading)
            HStack {
                Label("\(scene.content.wordCount)", systemImage: "character.cursor.ibeam")
                Spacer()
                Image(systemName: "hand.draw")
                    .foregroundStyle(.tertiary)
                    .help("Перетащите карточку, чтобы изменить порядок, или бросьте на другую — склеить сцены")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(strokeColor(isSelected: isSelected), lineWidth: isSelected || isDropTargeted ? 2.5 : 1)
        )
        .onTapGesture {
            workspace.selectedSceneID = scene.id
        }
        .draggable(scene)
        .dropDestination(for: SceneBlock.self) { payload, _ in
            guard let dropped = payload.first, dropped.id != scene.id else { return false }
            workspace.proposeMerge(source: dropped, into: scene)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            Button("Дублировать") {
                Task { await workspace.duplicateScene(scene.id) }
            }
            Divider()
            Button("Удалить сцену", role: .destructive) {
                Task { await workspace.deleteScene(scene.id) }
            }
        }
    }

    private func strokeColor(isSelected: Bool) -> Color {
        if isDropTargeted { return .red.opacity(0.9) }
        return isSelected ? Color.accentColor : Color.primary.opacity(0.08)
    }
}

struct GapDropZone: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    let index: Int
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: isTargeted ? 36 : 10)
            .contentShape(Rectangle())
            .overlay {
                if isTargeted {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.4))
                        .frame(height: 5)
                        .padding(.horizontal, 8)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isTargeted)
            .dropDestination(for: SceneBlock.self) { payload, _ in
                guard let dropped = payload.first else { return false }
                Task { await workspace.moveScene(dropped, toGap: index) }
                return true
            } isTargeted: { isTargeted = $0 }
    }
}
