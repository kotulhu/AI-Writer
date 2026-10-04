import SwiftData
import SwiftUI

@main
struct AI_writerApp: App {
    let container: ModelContainer
    /// Подключение к AI (OpenRouter): ключ в Keychain, модель в UserDefaults.
    @StateObject private var connectionStore = AIConnectionStore.shared

    init() {
        AILog.store("Запуск приложения")
        do {
            container = try ModelContainer(for: Manuscript.self, Block.self, Character.self)
            AILog.store("Хранилище данных создано")
        } catch {
            AILog.store("Не удалось создать хранилище данных: \(error)")
            fatalError("Не удалось создать хранилище данных: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("AI Writer") {
            ContentView()
                .environmentObject(connectionStore)
        }
        .modelContainer(container)
        .defaultSize(width: 1080, height: 680)
    }
}