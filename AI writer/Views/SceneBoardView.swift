import AppKit
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
        let isFirst = workspace.scenes.first?.id == scene.id
        let isLast = workspace.scenes.last?.id == scene.id
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
                    Button("Объединить со следующей") {
                        Task { await workspace.joinWithNext(scene.id) }
                    }
                    .disabled(isLast)
                    Button("Объединить с предыдущей") {
                        Task { await workspace.joinWithPrevious(scene.id) }
                    }
                    .disabled(isFirst)
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
                HStack(spacing: 2) {
                    Button {
                        Task { await workspace.moveScene(scene.id, offset: -1) }
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 18, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isFirst)
                    .help("Поменять местами с предыдущей сценой")

                    Divider()
                        .frame(height: 10)

                    Button {
                        Task { await workspace.moveScene(scene.id, offset: 1) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 18, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLast)
                    .help("Поменять местами со следующей сценой")
                }
                .background(Color(nsColor: .quaternarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 5))
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
        .onDrag { scene.itemProvider }
        .onDrop(of: [SceneBlock.sceneType], isTargeted: $isDropTargeted) { providers in
            Self.receive(providers) { dropped in
                guard let dropped, dropped.id != scene.id else { return }
                workspace.proposeMerge(source: dropped, into: scene)
            }
        }
        .contextMenu {
            Button("Дублировать") {
                Task { await workspace.duplicateScene(scene.id) }
            }
            Divider()
            Button("Объединить со следующей") {
                Task { await workspace.joinWithNext(scene.id) }
            }
            .disabled(isLast)
            Button("Объединить с предыдущей") {
                Task { await workspace.joinWithPrevious(scene.id) }
            }
            .disabled(isFirst)
            Divider()
            Button("Удалить сцену", role: .destructive) {
                Task { await workspace.deleteScene(scene.id) }
            }
        }
    }

    static func receive(
        _ providers: [NSItemProvider],
        handler: @escaping @MainActor (SceneBlock?) -> Void
    ) -> Bool {
        guard let provider = providers.first else { return false }
        let typeIdentifier = SceneBlock.sceneType.identifier
        _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            let decoded = data.flatMap { try? JSONDecoder().decode(SceneBlock.self, from: $0) }
            Task { @MainActor in
                handler(decoded)
            }
        }
        return true
    }

    private func strokeColor(isSelected: Bool) -> Color {
        if isDropTargeted { return Color.red.opacity(0.9) }
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
            .frame(height: isTargeted ? 36 : 12)
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
            .onDrop(of: [SceneBlock.sceneType], isTargeted: $isTargeted) { providers in
                SceneCardView.receive(providers) { dropped in
                    guard let dropped else { return }
                    Task { await workspace.moveScene(dropped, toGap: index) }
                }
            }
    }
}
