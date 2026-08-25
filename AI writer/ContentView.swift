import SwiftUI

struct ContentView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @Environment(ChatViewModel.self) private var chat
    @State private var errorIsPresented = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                if workspace.selectedManuscriptID == nil {
                    ContentUnavailableView(
                        "Рукопись не выбрана",
                        systemImage: "book.closed",
                        description: Text("Создайте рукопись в боковой панели")
                    )
                } else {
                    SceneBoardView()
                }
                if chat.isPanelVisible {
                    Divider()
                    ChatPanelView()
                        .frame(height: 280)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: chat.isPanelVisible)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        chat.togglePanel()
                    } label: {
                        Label(
                            "Помощник",
                            systemImage: chat.isPanelVisible ? "message.fill" : "message"
                        )
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    AIAvailabilityIndicator()
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { workspace.mergeCandidate != nil },
                set: { if !$0 { workspace.mergeCandidate = nil } }
            )
        ) {
            if let candidate = workspace.mergeCandidate {
                MergeSheetView(candidate: candidate)
                    .interactiveDismissDisabled()
            }
        }
        .onChange(of: workspace.errorMessage) { _, message in
            errorIsPresented = message != nil
        }
        .alert("Ошибка", isPresented: $errorIsPresented) {
            Button("OK", role: .cancel) {
                workspace.errorMessage = nil
            }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
        .task {
            await workspace.start()
        }
    }
}
