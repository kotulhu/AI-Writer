import SwiftUI

struct SceneEditorPane: View {
    @Environment(WorkspaceViewModel.self) private var workspace

    var body: some View {
        if workspace.selectedSceneID != nil {
            SceneEditorView()
                .id(workspace.selectedSceneID)
        } else {
            ContentUnavailableView("Выберите сцену", systemImage: "doc.text")
        }
    }
}

struct SceneEditorView: View {
    @Environment(WorkspaceViewModel.self) private var workspace
    @State private var draftTitle = ""
    @State private var draftContent = ""

    private var scene: SceneBlock? {
        workspace.selectedScene
    }

    var body: some View {
        VStack(spacing: 0) {
            if let scene {
                titleField(scene)
                Divider()
                contentEditor(scene)
                Divider()
                statusBar(scene)
                suggestionPanel
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear(perform: syncFromScene)
        .onChange(of: scene?.content) { _, newValue in
            if let newValue, newValue != draftContent {
                draftContent = newValue
            }
        }
        .onChange(of: scene?.title) { _, newValue in
            if let newValue, newValue != draftTitle {
                draftTitle = newValue
            }
        }
    }

    private func syncFromScene() {
        draftTitle = scene?.title ?? ""
        draftContent = scene?.content ?? ""
    }

    private func titleField(_ scene: SceneBlock) -> some View {
        TextField("Название сцены", text: $draftTitle)
            .textFieldStyle(.plain)
            .font(.title2.bold())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onChange(of: draftTitle) { _, newValue in
                workspace.renameScene(scene.id, title: newValue)
            }
    }

    private func contentEditor(_ scene: SceneBlock) -> some View {
        TextEditor(text: $draftContent)
            .font(.system(.body, design: .serif))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .onChange(of: draftContent) { _, newValue in
                workspace.updateSceneContent(scene.id, content: newValue)
            }
    }

    private func statusBar(_ scene: SceneBlock) -> some View {
        HStack(spacing: 14) {
            Text("Слов: \(draftContent.wordCount)")
            Text("Знаков: \(draftContent.count)")
            Spacer()
            if workspace.isGenerating {
                ProgressView()
                    .controlSize(.small)
            }
            Menu {
                ForEach(AIMode.allCases) { mode in
                    Button(mode.title) {
                        Task { await workspace.generate(mode) }
                    }
                    .disabled(workspace.isGenerating || draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mode == .alternative)
                }
            } label: {
                Label("AI", systemImage: "sparkles")
            }
            .fixedSize()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var suggestionPanel: some View {
        if let suggestion = workspace.aiSuggestion {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Предложение ИИ", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Button("Вставить в сцену") {
                        workspace.acceptSuggestion()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Отклонить") {
                        workspace.discardSuggestion()
                    }
                    .controlSize(.small)
                }
                ScrollView {
                    Text(suggestion)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            }
            .padding(16)
            .background(Color(nsColor: .quaternarySystemFill))
        }
    }
}
