import SwiftData
import SwiftUI

struct BlockEditorView: View {
    @Bindable var store: ManuscriptStore
    @Environment(\.modelContext) private var context
    let block: Block

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            BlockTextViewRepresentable(block: block, store: store, modelContext: context)
                .id(block.id)
        }
        .navigationTitle(title)
    }

    private var title: String {
        block.title.isEmpty ? "Блок" : block.title
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            toolbarButton("B", help: "Жирный (⌘B)") { BlockTextViewCoordinator.current?.toggleBold() }
            toolbarButton("I", help: "Курсив (⌘I)") { BlockTextViewCoordinator.current?.toggleItalic() }
            toolbarButton("U", help: "Подчёркнутый (⌘U)") { BlockTextViewCoordinator.current?.toggleUnderline() }
            toolbarButton("S", help: "Зачёркнутый") { BlockTextViewCoordinator.current?.toggleStrike() }

            Divider().frame(height: 18)

            ForEach(1...4, id: \.self) { level in
                toolbarButton("H\(level)", help: "Заголовок \(level)") {
                    BlockTextViewCoordinator.current?.applyHeading(level)
                }
            }
            toolbarButton("Body", help: "Обычный текст") {
                BlockTextViewCoordinator.current?.applyHeading(0)
            }

            Divider().frame(height: 18)

            toolbarButton("Цитата", help: "Цитата") {
                BlockTextViewCoordinator.current?.toggleQuote()
            }

            Divider().frame(height: 18)

            Button {
                splitBlock()
            } label: {
                Label("Разбить по курсору", systemImage: "arrow.left.and.line.vertical.and.arrow.right")
            }
            .buttonStyle(.borderless)
            .help("Разбить блок по позиции курсора")

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toolbarButton(_ label: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func splitBlock() {
        BlockTextViewCoordinator.current?.splitAtCursor()
    }
}