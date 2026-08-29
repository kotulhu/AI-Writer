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

    var body: some View {
        Group {
            if let manuscript = store.selectedManuscript {
                List(selection: selection) {
                    ForEach(blocks) { block in
                        BlockRow(block: block)
                            .tag(block.id)
                            .contextMenu {
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
        .onAppear {
            ensureSelection()
        }
        .onChange(of: blocks.count) {
            ensureSelection()
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        let firstLine = block.content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Пустой блок" : firstLine
    }

    private var subtitle: String {
        let cleaned = block.content
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        return cleaned.isEmpty ? "Без содержимого" : cleaned
    }
}