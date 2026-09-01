import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ManuscriptStore()
    @State private var navPath: [Character] = []
    @State private var isSectionBarVisible = true

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            TopSectionBar(store: store, isVisible: $isSectionBarVisible)
            Divider()

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

/// Горизонтальная панель выбора раздела с возможностью сворачивания.
struct TopSectionBar: View {
    @Bindable var store: ManuscriptStore
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            HStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        store.appSection = section
                    } label: {
                        Label(section.title, systemImage: section.icon)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                store.appSection == section
                                    ? AnyShapeStyle(Color.accentColor.opacity(0.9))
                                    : AnyShapeStyle(.clear),
                                in: Capsule()
                            )
                            .foregroundStyle(store.appSection == section ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                if store.appSection == .books {
                    toggleButton("Показать/скрыть книги", systemImage: "sidebar.left", isOn: $store.isBooksPaneVisible)
                    toggleButton("Показать/скрыть блоки", systemImage: "sidebar.right", isOn: $store.isBlocksPaneVisible)
                }

                Button {
                    isVisible = false
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Свернуть меню")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 2) {
                Button {
                    isVisible = true
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .help("Развернуть меню")

                Image(systemName: store.appSection.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.appSection.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if store.appSection == .books {
                    toggleButton("Показать/скрыть книги", systemImage: "sidebar.left", isOn: $store.isBooksPaneVisible)
                    toggleButton("Показать/скрыть блоки", systemImage: "sidebar.right", isOn: $store.isBlocksPaneVisible)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
    }

    private func toggleButton(_ help: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(5)
                .background(isOn.wrappedValue ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
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
            if store.isBooksPaneVisible {
                ManuscriptListView(store: store)
                    .frame(minWidth: 180, idealWidth: 230)
            }

            if store.isBlocksPaneVisible {
                BlockListView(store: store)
                    .frame(minWidth: 150, idealWidth: 190)
            }

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