import SwiftUI

@main
struct AI_writerApp: App {
    @State private var workspace: WorkspaceViewModel

    init() {
        workspace = WorkspaceViewModel(database: DatabaseService.live())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(workspace)
                .frame(minWidth: 1080, minHeight: 700)
        }
        Settings {
            SettingsView()
                .environment(workspace)
        }
    }
}
