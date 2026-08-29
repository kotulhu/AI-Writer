import SwiftData
import SwiftUI

@main
struct AI_writerApp: App {
    let container: ModelContainer

    init() {
        EditorDiag.log("App.init start")
        do {
            container = try ModelContainer(for: Manuscript.self, Block.self, Character.self)
            EditorDiag.log("App.init container OK")
        } catch {
            EditorDiag.log("App.init fatal: \(error)")
            fatalError("Не удалось создать хранилище данных: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("AI Writer") {
            ContentView()
                .onAppear {
                    EditorDiag.log("ContentView.onAppear")
                }
        }
        .modelContainer(container)
        .defaultSize(width: 1080, height: 680)
    }
}