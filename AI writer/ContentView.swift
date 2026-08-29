import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ManuscriptStore()

    var body: some View {
        HSplitView {
            ManuscriptListView(store: store)
                .frame(minWidth: 180, idealWidth: 230)

            BlockListView(store: store)
                .frame(minWidth: 150, idealWidth: 190)

            Group {
                if let block = store.selectedBlock {
                    BlockEditorView(store: store, block: block)
                } else {
                    ContentUnavailableView(
                        "Нет выбранного блока",
                        systemImage: "square.and.pencil",
                        description: Text("Создайте книгу и блок, чтобы начать писать.")
                    )
                }
            }
            .frame(minWidth: 420)
        }
        .frame(minWidth: 820, minHeight: 480)
        .onChange(of: store.selectedManuscript?.persistentModelID) {
            guard let manuscript = store.selectedManuscript else {
                store.selectedBlock = nil
                EditorDiag.log("ContentView.onChange manuscript -> nil (block cleared)")
                return
            }
            let current = store.selectedBlock
            if current == nil || current?.manuscript?.persistentModelID != manuscript.persistentModelID {
                store.selectedBlock = manuscript.orderedBlocks.first
                EditorDiag.log("ContentView.onChange manuscript \(manuscript.title) -> block #\(manuscript.orderedBlocks.count == 0 ? -1 : 1)")
            } else {
                EditorDiag.log("ContentView.onChange manuscript \(manuscript.title) kept block")
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                BlockTextViewCoordinator.current?.flush(saveNow: true)
            }
        }
    }
}