import SwiftData
import SwiftUI

struct ManuscriptListView: View {
    @Bindable var store: ManuscriptStore
    @Environment(\.modelContext) private var context
    @Query(sort: \Manuscript.updatedAt, order: .reverse) private var manuscripts: [Manuscript]

    private var selection: Binding<UUID?> {
        Binding<UUID?>(
            get: { store.selectedManuscript?.id },
            set: { newID in
                guard store.selectedManuscript?.id != newID else { return }
                store.selectedManuscript = manuscripts.first { $0.id == newID }
            }
        )
    }

    @State private var isRenaming = false
    @State private var renameTitle = ""
    @State private var manuscriptToDelete: Manuscript?

    var body: some View {
        List(selection: selection) {
            ForEach(manuscripts) { manuscript in
                Text(manuscript.title)
                    .tag(manuscript.id)
                    .onTapGesture(count: 2) {
                        beginRename(manuscript)
                    }
                    .contextMenu {
                        Button("Переименовать…") { beginRename(manuscript) }
                        Divider()
                        Button("Удалить книгу", role: .destructive) {
                            manuscriptToDelete = manuscript
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Книги")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    store.createManuscript(title: newBookTitle(), context: context)
                } label: {
                    Label("Новая книга", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(6)
        }
        .alert("Переименовать книгу", isPresented: $isRenaming) {
            TextField("Название", text: $renameTitle)
            Button("Переименовать") {
                if let manuscript = store.selectedManuscript {
                    store.renameManuscript(manuscript, title: renameTitle, context: context)
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Удалить книгу?", isPresented: Binding(
            get: { manuscriptToDelete != nil },
            set: { if !$0 { manuscriptToDelete = nil } }
        ), presenting: manuscriptToDelete) { manuscript in
            Button("Удалить", role: .destructive) {
                store.deleteManuscript(manuscript, context: context)
            }
            Button("Отмена", role: .cancel) {}
        } message: { manuscript in
            Text("«\(manuscript.title)» вместе со всеми её блоками будет удалена безвозвратно.")
        }
        .onAppear {
            if store.selectedManuscript == nil, let first = manuscripts.first {
                store.selectedManuscript = first
                EditorDiag.log("ManuscriptListView.onAppear selected \(first.title) (\(manuscripts.count) books)")
            } else {
                EditorDiag.log("ManuscriptListView.onAppear skip (selected=\(String(describing: store.selectedManuscript?.title))) books=\(manuscripts.count)")
            }
        }
    }

    private func beginRename(_ manuscript: Manuscript) {
        renameTitle = manuscript.title
        store.selectedManuscript = manuscript
        isRenaming = true
    }

    private func newBookTitle() -> String {
        let count = manuscripts.count
        return count == 0 ? "Книга" : "Книга \(count + 1)"
    }
}