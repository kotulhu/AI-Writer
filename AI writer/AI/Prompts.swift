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

enum RephraseStyle: String, CaseIterable, Identifiable {
    case shorter
    case longer
    case artistic
    case simpler
    case formal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shorter: "Короче"
        case .longer: "Подробнее"
        case .artistic: "Художественнее"
        case .simpler: "Проще"
        case .formal: "Официальнее"
        }
    }

    var instruction: String {
        switch self {
        case .shorter:
            "сожмите текст до самой сути, уберите воду, сохранив ключевые образы и факты"
        case .longer:
            "расширь фрагмент деталями обстановки, ощущений и действий героев, не добавляя новых сюжетных событий"
        case .artistic:
            "усильте образность и метафоричность языка, сделайте ритм более выразительным"
        case .simpler:
            "упростите синтаксис и лексику, сделайте текст максимально ясным и разговорным"
        case .formal:
            "переведите текст в нейтрально-официальный регистр, убрав разговорные обороты"
        }
    }
}

enum Prompts {
    static let variantMarker = "===ВАРИАНТ==="

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

    static func synonyms(word: String, context: String) -> (system: String, user: String) {
        (
            "Ты опытный литературный редактор и лексикограф. Работаешь с художественной прозой на русском языке.",
            """
            Подбери замены для выделенного фрагмента так, чтобы они естественно звучали в предложении-контексте.

            Фрагмент: \(word)
            Контекст: \(context)

            Верни 6-8 вариантов: сначала одиночные слова-синонимы, затем 2-3 развёрнутые фразы, которыми можно заменить фрагмент целиком. Учитывай род, падеж и стилистику контекста. Разделяй варианты строкой \(variantMarker). Без нумерации и пояснений.
            """
        )
    }

    static func rephrase(style: RephraseStyle, text: String) -> (system: String, user: String) {
        (
            "Ты опытный литературный редактор. Работаешь с художественной прозой на русском языке.",
            """
            Перепиши приведённый фрагмент в стиле «\(style.title)»: \(style.instruction).

            Верни ровно три различных варианта. Разделяй варианты строкой \(variantMarker). Без нумерации и пояснений.

            Фрагмент:
            \(text.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        )
    }
}
