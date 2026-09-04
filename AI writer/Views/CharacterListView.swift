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

struct CharacterCardItem: View {
    let character: Character
    let store: ManuscriptStore
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                CharacterDetailView(character: character, store: store)
            } label: {
                CharacterCardView(character: character)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isHovering ? false : true)

            if isHovering {
                HStack(spacing: 4) {
                    NavigationLink {
                        CharacterDetailView(character: character, store: store)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Редактировать персонажа")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Удалить персонажа")
                }
                .padding(8)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Дублировать") {
                onDuplicate()
            }
            Divider()
            Button("Удалить персонажа", role: .destructive) {
                onDelete()
            }
        }
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
                            CharacterCardItem(
                                character: character,
                                store: store,
                                onDelete: { store.deleteCharacter(character, context: context) },
                                onDuplicate: { store.duplicateCharacter(character, context: context) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Поиск по имени")
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