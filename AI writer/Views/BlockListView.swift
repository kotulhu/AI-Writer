import SwiftData
import SwiftUI

struct BlockListView: View {
    @Bindable var store: ManuscriptStore
    @Environment(\.modelContext) private var context
    @Query(sort: \Block.order) private var allBlocks: [Block]

    private var manuscriptID: PersistentIdentifier? {
        store.selectedManuscript?.persistentModelID
    }

    private var blocks: [Block] {
        guard let manuscriptID else { return [] }
        return allBlocks.filter { $0.manuscript?.persistentModelID == manuscriptID }
    }

    private var selection: Binding<UUID?> {
        Binding<UUID?>(
            get: { store.selectedBlock?.id },
            set: { newID in
                guard store.selectedBlock?.id != newID else { return }
                store.selectedBlock = blocks.first { $0.id == newID }
            }
        )
    }

    @State private var isRenaming = false
    @State private var renameTitle = ""
    @State private var blockToRename: Block?

    var body: some View {
        Group {
            if let manuscript = store.selectedManuscript {
                List(selection: selection) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        BlockRow(
                            block: block,
                            canMoveUp: index > 0,
                            canMoveDown: index < blocks.count - 1
                        ) { direction in
                            store.moveBlock(block, direction, context: context)
                        }
                        .tag(block.id)
                        .onTapGesture(count: 2) {
                            beginRename(block)
                        }
                            .contextMenu {
                                Button("Переименовать…") { beginRename(block) }
                                Button("Переместить вверх") { store.moveBlock(block, -1, context: context) }
                                    .disabled(index == 0)
                                Button("Переместить вниз") { store.moveBlock(block, 1, context: context) }
                                    .disabled(index == blocks.count - 1)
                                Divider()
                                Button("Дублировать") { store.duplicateBlock(block, context: context) }
                                Button("Объединить со следующим") { store.mergeBlockWithNext(block, context: context) }
                                Divider()
                                Button("Удалить блок", role: .destructive) { store.deleteBlock(block, context: context) }
                            }
                    }
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button {
                            store.addBlock(after: nil, manuscript: manuscript, context: context)
                        } label: {
                            Label("Блок", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding(6)
                }
            } else {
                ContentUnavailableView("Книга не выбрана", systemImage: "book.closed", description: Text("Создайте или выберите книгу в левом списке."))
            }
        }
        .frame(minWidth: 140)
        .alert("Переименовать блок", isPresented: $isRenaming) {
            TextField("Название", text: $renameTitle)
            Button("Переименовать") {
                if let block = blockToRename {
                    store.renameBlock(block, title: renameTitle, context: context)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear {
            ensureSelection()
        }
        .onChange(of: blocks.count) {
            ensureSelection()
        }
    }

    private func beginRename(_ block: Block) {
        renameTitle = block.title
        blockToRename = block
        isRenaming = true
    }

    private func ensureSelection() {
        guard let manuscript = store.selectedManuscript else { return }
        let current = store.selectedBlock
        if current == nil || current?.manuscript?.persistentModelID != manuscript.persistentModelID {
            store.selectedBlock = blocks.first
        }
    }
}

private struct BlockRow: View {
    let block: Block
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(block.title.isEmpty ? "Без названия" : block.title)
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(block.title.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            Spacer(minLength: 2)
            Button {
                onMove(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)
            .help("Переместить вверх")
            Button {
                onMove(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)
            .help("Переместить вниз")
        }
        .padding(.vertical, 2)
    }
}