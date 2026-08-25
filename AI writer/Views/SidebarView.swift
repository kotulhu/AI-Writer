import SwiftUI

struct SidebarView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @State private var renamingManuscriptID: UUID?
    @State private var renameDraft = ""

    var body: some View {
        List(selection: Binding(
            get: { workspace.selectedManuscriptID },
            set: { newValue in
                if newValue != workspace.selectedManuscriptID {
                    Task { await workspace.selectManuscript(newValue) }
                }
            }
        )) {
            ForEach(workspace.manuscripts) { manuscript in
                Label(manuscript.title, systemImage: "book.closed")
                    .tag(manuscript.id)
                    .contextMenu {
                        Button("Переименовать…") {
                            renameDraft = workspace.manuscripts.first(where: { $0.id == manuscript.id })?.title ?? manuscript.title
                            renamingManuscriptID = manuscript.id
                        }
                        Divider()
                        Button("Удалить рукопись", role: .destructive) {
                            Task { await workspace.deleteManuscript(manuscript.id) }
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    Task { await workspace.addManuscript() }
                } label: {
                    Label("Новая рукопись", systemImage: "plus")
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
            }
            .padding(12)
        }
        .alert(
            "Переименовать рукопись",
            isPresented: Binding(
                get: { renamingManuscriptID != nil },
                set: { if !$0 { renamingManuscriptID = nil } }
            )
        ) {
            TextField("Название", text: $renameDraft)
                .onSubmit { commitRename() }
            Button("Сохранить") {
                commitRename()
            }
            Button("Отмена", role: .cancel) {
                renamingManuscriptID = nil
            }
        } message: {
            Text("Введите новое название рукописи.")
        }
    }

    private func commitRename() {
        guard let id = renamingManuscriptID else { return }
        renamingManuscriptID = nil
        Task { await workspace.renameManuscript(id, title: renameDraft) }
    }
}
