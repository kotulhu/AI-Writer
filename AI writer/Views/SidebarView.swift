import SwiftUI

struct SidebarView: View {
    @Environment(WorkspaceViewModel.self) private var workspace

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
    }
}
