import SwiftData
import SwiftUI

/// Все персонажи всех рукописей, сгруппированные по рукописи, в виде карточек.
struct CharactersGlobalView: View {
    @Bindable var store: ManuscriptStore
    @Environment(\.modelContext) private var context
    @Query(sort: \Manuscript.title) private var manuscripts: [Manuscript]
    @State private var searchText = ""

    private func matching(_ character: Character) -> Bool {
        searchText.isEmpty || character.name.localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        Group {
            if manuscripts.isEmpty {
                ContentUnavailableView(
                    "Нет рукописей",
                    systemImage: "books.vertical",
                    description: Text("Создайте рукопись в разделе «Книги», чтобы добавлять персонажей.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(manuscripts) { manuscript in
                            let characters = manuscript.orderedCharacters.filter(matching)
                            if !characters.isEmpty || searchText.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(manuscript.title) (\(characters.count))")
                                        .font(.headline)
                                    if characters.isEmpty {
                                        HStack {
                                            Text("Персонажей пока нет")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Button {
                                                store.addCharacter(to: manuscript, context: context)
                                            } label: {
                                                Image(systemName: "plus")
                                            }
                                            .buttonStyle(.plain)
                                            .help("Добавить персонажа в «\(manuscript.title)»")
                                        }
                                        .padding(.vertical, 2)
                                    } else {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                                            ForEach(characters) { character in
                                                CharacterCardItem(
                                                    character: character,
                                                    store: store,
                                                    onDelete: { store.deleteCharacter(character, context: context) },
                                                    onDuplicate: { store.duplicateCharacter(character, context: context) }
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Поиск по имени")
        .navigationTitle("Персонажи")
        .toolbar {
            ToolbarItem {
                Group {
                    if manuscripts.count > 1 {
                        Menu {
                            ForEach(manuscripts) { manuscript in
                                Button {
                                    store.addCharacter(to: manuscript, context: context)
                                } label: {
                                    Label(manuscript.title, systemImage: "book.closed")
                                }
                            }
                        } label: {
                            Label("Персонаж", systemImage: "plus")
                        }
                        .help("Добавить персонажа — выберите рукопись")
                    } else {
                        Button {
                            guard let manuscript = store.selectedManuscript ?? manuscripts.first else { return }
                            store.addCharacter(to: manuscript, context: context)
                        } label: {
                            Label("Персонаж", systemImage: "plus")
                        }
                        .help("Добавить персонажа")
                    }
                }
                .disabled(manuscripts.isEmpty)
            }
        }
    }
}