import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ManuscriptStore()
    @State private var navPath: [Character] = []

    var body: some View {
        NavigationSplitView {
            List(selection: $store.appSection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 210)
            .navigationTitle("Разделы")
        } detail: {
            NavigationStack(path: $navPath) {
                Group {
                    switch store.appSection {
                    case .books:
                        BooksWorkspace(store: store)
                    case .characters:
                        CharactersGlobalView(store: store)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 480)
        .onChange(of: store.appSection) {
            navPath = []
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                BlockTextViewCoordinator.current?.flush(saveNow: true)
            }
        }
    }
}

struct BooksWorkspace: View {
    @Bindable var store: ManuscriptStore
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Рабочая область", selection: $store.workspaceMode) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)

                if store.workspaceMode == .characters, let manuscript = store.selectedManuscript {
                    Text("Персонажи «\(manuscript.title)»")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            switch store.workspaceMode {
            case .blocks:
                blocksWorkspace
            case .characters:
                charactersWorkspace
            }
        }
    }

    private var blocksWorkspace: some View {
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
    }

    @ViewBuilder
    private var charactersWorkspace: some View {
        if let manuscript = store.selectedManuscript {
            CharacterListView(store: store, manuscript: manuscript)
        } else {
            ContentUnavailableView(
                "Книга не выбрана",
                systemImage: "person.2",
                description: Text("Выберите рукопись слева, чтобы увидеть её персонажей.")
            )
        }
    }
}