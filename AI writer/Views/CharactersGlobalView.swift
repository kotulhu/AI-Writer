import SwiftData
import SwiftUI

struct CharacterRowView: View {
    let character: Character

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: character.isMale ? "mars" : "venus")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(character.name.isEmpty ? "Без имени" : character.name)
                    .font(.body)
                HStack(spacing: 4) {
                    Image(systemName: character.species.icon)
                    Text(character.species.label)
                    if let preview = previewText {
                        Text("• \(preview)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var previewText: String? {
        guard let d = character.appearanceDescription, !d.isEmpty else { return nil }
        return d.count > 60 ? String(d.prefix(60)) + "…" : d
    }
}

/// Все персонажи всех рукописей, сгруппированные по рукописи.
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
                List {
                    ForEach(manuscripts) { manuscript in
                        let characters = manuscript.orderedCharacters.filter(matching)
                        Section {
                            if characters.isEmpty {
                                HStack {
                                    Text(searchText.isEmpty ? "Персонажей пока нет" : "Ничего не найдено")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        store.addCharacter(to: manuscript, context: context)
                                    } label: {
                                        Image(systemName: "plus")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Добавить персонажа")
                                }
                                .padding(.vertical, 2)
                            } else {
                                ForEach(characters) { character in
                                    HStack(spacing: 4) {
                                        NavigationLink(value: character) {
                                            CharacterRowView(character: character)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(Rectangle())
                                        }
                                        Button {
                                            store.deleteCharacter(character, context: context)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .padding(4)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Удалить персонажа")
                                    }
                                    .contextMenu {
                                        Button("Дублировать") {
                                            store.duplicateCharacter(character, context: context)
                                        }
                                        Divider()
                                        Button("Удалить персонажа", role: .destructive) {
                                            store.deleteCharacter(character, context: context)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("\(manuscript.title) (\(characters.count))")
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Поиск по имени")
        .navigationDestination(for: Character.self) { character in
            CharacterDetailView(character: character, store: store)
        }
        .navigationTitle("Персонажи")
        .toolbar {
            ToolbarItem {
                Button {
                    guard let manuscript = store.selectedManuscript ?? manuscripts.first else { return }
                    store.addCharacter(to: manuscript, context: context)
                } label: {
                    Label("Персонаж", systemImage: "plus")
                }
                .help("Добавить персонажа")
                .disabled(manuscripts.isEmpty)
            }
        }
    }
}