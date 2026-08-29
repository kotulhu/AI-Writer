import SwiftData
import SwiftUI

struct CharacterCardView: View {
    let character: Character

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: character.isMale ? "mars" : "venus")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(character.name.isEmpty ? "Без имени" : character.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Image(systemName: character.species.icon)
                Text(character.species.label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let preview = previewText {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private var previewText: String? {
        guard let d = character.appearanceDescription, !d.isEmpty else { return nil }
        return d.count > 80 ? String(d.prefix(80)) + "…" : d
    }
}

struct CharacterListView: View {
    @Bindable var store: ManuscriptStore
    @Environment(\.modelContext) private var context
    let manuscript: Manuscript

    @State private var searchText = ""

    private var characters: [Character] {
        let ordered = manuscript.orderedCharacters
        guard !searchText.isEmpty else { return ordered }
        return ordered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if characters.isEmpty {
                ContentUnavailableView(
                    "Нет персонажей",
                    systemImage: "person.2",
                    description: Text(searchText.isEmpty ? "Нажмите «+», чтобы добавить первого персонажа." : "Ничего не найдено по запросу \(searchText).")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(characters) { character in
                            NavigationLink(value: character) {
                                CharacterCardView(character: character)
                            }
                            .buttonStyle(.plain)
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
                    .padding(12)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Поиск по имени")
        .navigationDestination(for: Character.self) { character in
            CharacterDetailView(character: character, store: store)
        }
        .navigationTitle(manuscript.title)
        .toolbar {
            ToolbarItem {
                Button {
                    store.addCharacter(to: manuscript, context: context)
                } label: {
                    Label("Персонаж", systemImage: "plus")
                }
                .help("Добавить персонажа")
            }
        }
    }
}