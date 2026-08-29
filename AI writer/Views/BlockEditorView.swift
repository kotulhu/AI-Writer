import SwiftData
import SwiftUI

struct BlockEditorView: View {
    @Bindable var store: ManuscriptStore
    @Environment(\.modelContext) private var context
    let block: Block

    @Query(sort: \BlockVersion.createdAt) private var allVersions: [BlockVersion]
    @State private var selectedVersion: BlockVersion?

    private var versions: [BlockVersion] {
        allVersions.filter { $0.block?.persistentModelID == block.persistentModelID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            versionTabs
            Divider()
            Group {
                if let version = selectedVersion {
                    versionView(version)
                } else {
                    editorView
                }
            }
        }
        .navigationTitle(title)
        .onChange(of: block.id) {
            selectedVersion = nil
        }
    }

    private var title: String {
        block.title.isEmpty ? "Блок" : block.title
    }

    private var editorView: some View {
        BlockTextViewRepresentable(block: block, store: store, modelContext: context)
            .id(block.id)
    }

    private func versionView(_ version: BlockVersion) -> some View {
        VStack(spacing: 8) {
            BlockTextViewRepresentable(
                block: block,
                store: store,
                modelContext: context,
                editedContent: version.content,
                isReadOnly: true
            )
            .id(version.id)
            HStack(spacing: 12) {
                Button {
                    restore(version)
                } label: {
                    Label("Восстановить", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)

                if version.isPinned {
                    Button {
                        store.setVersionPinned(version, false, context: context)
                    } label: {
                        Label("Снять закрепление", systemImage: "pin.slash")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        store.setVersionPinned(version, true, context: context)
                    } label: {
                        Label("Закрепить", systemImage: "pin")
                    }
                    .buttonStyle(.bordered)
                }

                if let label = version.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private var versionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(versions) { version in
                    versionTab(version)
                }
                currentTab
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func versionTab(_ version: BlockVersion) -> some View {
        Button {
            if selectedVersion?.id == version.id {
                selectedVersion = nil
            } else {
                selectedVersion = version
            }
        } label: {
            HStack(spacing: 4) {
                if version.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                }
                Text(version.createdAt, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                selectedVersion?.id == version.id
                    ? Color.accentColor.opacity(0.18)
                    : Color(nsColor: .controlBackgroundColor)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var currentTab: some View {
        Button {
            selectedVersion = nil
        } label: {
            Text("Текущий")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    selectedVersion == nil
                        ? Color.accentColor.opacity(0.18)
                        : Color(nsColor: .controlBackgroundColor)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

            Button {
                BlockTextViewCoordinator.current?.saveVersionManually()
            } label: {
                Label("Сохранить версию", systemImage: "clock.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Сохранить текущий текст как версию")
        }
        .disabled(selectedVersion != nil)
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

    private func restore(_ version: BlockVersion) {
        selectedVersion = nil
        store.restoreVersion(version, context: context)
    }
}