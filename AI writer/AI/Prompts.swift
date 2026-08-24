import Foundation

enum AIMode: String, CaseIterable, Identifiable {
    case alternative
    case dialogue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alternative: "Альтернативное описание сцены"
        case .dialogue: "Сгенерировать диалог"
        }
    }
}

enum Prompts {
    static func make(for mode: AIMode, scene: SceneBlock) -> (system: String, user: String) {
        let excerpt = scene.content.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .alternative:
            return (
                "Ты опытный литературный редактор и соавтор. Пишешь живым художественным языком на русском языке.",
                """
                Ниже приведён текст сцены. Предложи одну альтернативную версию этого фрагмента: сохрани сюжетные факты и смысл, но измени ритм, образы и лексику. Не добавляй пояснений — верни только текст сцены.

                Название сцены: \(scene.title)

                Текст:
                \(excerpt)
                """
            )
        case .dialogue:
            return (
                "Ты опытный драматург. Твои диалоги естественные, реплики короткие, у каждого героя свой голос. Пишешь на русском языке.",
                """
                Продолжи сцену в форме живого диалога между персонажами. Используй формат «Имя: реплика». Верни только диалог без пояснений.

                Название сцены: \(scene.title)

                Текст:
                \(excerpt)
                """
            )
        }
    }
}
