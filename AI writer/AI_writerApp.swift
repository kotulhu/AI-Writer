import SwiftUI

@main
struct AI_writerApp: App {
    @State private var workspace: WorkspaceViewModel
    @State private var chat: ChatViewModel

    init() {
        let ws = WorkspaceViewModel(database: DatabaseService.live())
        workspace = ws
        chat = ChatViewModel(workspace: ws)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workspace)
                .environment(chat)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Отменить") {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
                Button("Повторить") {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsView()
                .environment(workspace)
                .environment(chat)
        }
    }
}
