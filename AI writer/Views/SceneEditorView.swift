import AppKit
import SwiftUI

final class EditorActionBox: NSObject {
    var handler: ((String) -> Void)?

    @objc func run(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        handler?(key)
    }
}

final class RichTextHandle {
    fileprivate weak var textView: NSTextView?

    var plainText: String {
        textView?.string ?? ""
    }

    var attributedText: NSAttributedString {
        textView?.attributedString() ?? NSAttributedString()
    }

    func apply(_ action: WriterFormatAction) {
        guard let textView else { return }
        WriterText.apply(action, to: textView)
    }

    func replace(range: NSRange, with text: String) -> String? {
        guard let textView, let storage = textView.textStorage else { return nil }
        let length = (textView.string as NSString).length
        guard range.location <= length else { return nil }
        let clamped = NSRange(
            location: range.location,
            length: min(range.length, length - range.location)
        )
        let anchorAttributes = storage.length > 0
            ? storage.attributes(at: min(clamped.location, storage.length - 1), effectiveRange: nil)
            : [:]
        textView.undoManager?.beginUndoGrouping()
        defer { textView.undoManager?.endUndoGrouping() }
        _ = textView.shouldChangeText(in: clamped, replacementString: text)
        storage.replaceCharacters(in: clamped, with: NSAttributedString(string: text, attributes: anchorAttributes))
        let markdown = WriterText.markdown(from: textView.attributedString())
        textView.didChangeText()
        return markdown
    }
}

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
    @Environment(\.openSettings) private var openSettings
    @State private var draftTitle = ""
    @State private var markdownText = ""
    @State private var selectionRange = NSRange(location: 0, length: 0)
    @State private var actionBox = EditorActionBox()
    @State private var textHandle = RichTextHandle()

    static let synonymsActionKey = "ai-writer-synonyms"
    static let splitActionKey = "ai-writer-split"
    static let joinNextActionKey = "ai-writer-join-next"

    private var scene: SceneBlock? {
        workspace.selectedScene
    }

    var body: some View {
        VStack(spacing: 0) {
            if let scene {
                titleField(scene)
                Divider()
                formatBar
                Divider()
                contentEditor(scene)
                Divider()
                statusBar(scene)
                suggestionPanel
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear(perform: syncFromScene)
        .onAppear {
            actionBox.handler = { key in
                switch key {
                case Self.synonymsActionKey:
                    findSynonymsForSelection()
                case Self.splitActionKey:
                    splitSceneAtCaret()
                case Self.joinNextActionKey:
                    if let scene {
                        Task { await workspace.joinWithNext(scene.id) }
                    }
                default:
                    rephraseSelected(RephraseStyle(rawValue: key) ?? .artistic)
                }
            }
        }
        .onChange(of: scene?.content) { _, newValue in
            if let newValue, newValue != markdownText {
                markdownText = newValue
            }
        }
        .onChange(of: scene?.title) { _, newValue in
            if let newValue, newValue != draftTitle {
                draftTitle = newValue
            }
        }
        .sheet(
            isPresented: Binding(
                get: { workspace.rephraseRequest != nil },
                set: { if !$0 { workspace.cancelRephrase() } }
            )
        ) {
            if let request = workspace.rephraseRequest {
                RephraseSheetView(
                    request: request,
                    variants: workspace.rephraseVariants
                ) { variantIndex in
                    applyVariant(variantIndex)
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { workspace.synonymRequest != nil },
                set: { if !$0 { workspace.clearSynonyms() } }
            )
        ) {
            if let request = workspace.synonymRequest {
                SynonymSheetView(
                    request: request,
                    variants: workspace.synonymVariants
                ) { variantIndex in
                    applySynonym(variantIndex)
                }
            }
        }
    }

    private func syncFromScene() {
        draftTitle = scene?.title ?? ""
        markdownText = scene?.content ?? ""
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

    private var formatBar: some View {
        HStack(spacing: 6) {
            formatButton("bold", icon: "bold") {
                textHandle.apply(.bold)
            }
            formatButton("italic", icon: "italic") {
                textHandle.apply(.italic)
            }
            formatButton("strikethrough", icon: "strikethrough") {
                textHandle.apply(.strike)
            }
            formatButton("inline code", icon: "chevron.left.forwardslash.chevron.right") {
                textHandle.apply(.code)
            }

            Divider()
                .frame(height: 14)

            formatButton("Заголовок 1", label: "H1") {
                textHandle.apply(.heading(1))
            }
            formatButton("Заголовок 2", label: "H2") {
                textHandle.apply(.heading(2))
            }
            formatButton("Заголовок 3", label: "H3") {
                textHandle.apply(.heading(3))
            }

            Divider()
                .frame(height: 14)

            formatButton("Маркированный список", icon: "list.bullet") {
                textHandle.apply(.bullet)
            }
            formatButton("Нумерованный список", icon: "list.number") {
                textHandle.apply(.ordered)
            }
            formatButton("Цитата", icon: "text.quote") {
                textHandle.apply(.quote)
            }
            formatButton("Разделитель сцены", icon: "minus") {
                textHandle.apply(.rule)
            }

            Divider()
                .frame(height: 14)

            formatButton("Разделить сцену по курсору", icon: "scissors") {
                splitSceneAtCaret()
            }
            Spacer()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .font(.caption)
    }

    private func formatButton(
        _ help: String,
        icon systemName: String? = nil,
        label text: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                } else if let text {
                    Text(text).font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(width: 20, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func contentEditor(_ scene: SceneBlock) -> some View {
        SelectionTextView(
            markdown: markdownText,
            handle: textHandle,
            onChangeMarkdown: { newValue in
                markdownText = newValue
                workspace.updateSceneContent(scene.id, content: newValue)
            },
            onSelectionChange: { selectionRange = $0 },
            menuItemsBuilder: rephraseMenuItems,
            structuralItemsBuilder: structuralMenuItems
        )
        .onChange(of: markdownText) { _, newValue in
            workspace.updateSceneContent(scene.id, content: newValue)
        }
    }

    private func statusBar(_ scene: SceneBlock) -> some View {
        HStack(spacing: 12) {
            Text("Слов: \(textHandle.plainText.wordCount)")
            Text("Знаков: \(textHandle.plainText.count)")
            Spacer()
            if workspace.isGenerating {
                ProgressView()
                    .controlSize(.small)
            }
            providerMenu
            aiActionsMenu
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var providerMenu: some View {
        Menu {
            if workspace.connectedProviders.isEmpty {
                Text("Нет подключённых провайдеров")
                    .foregroundStyle(.secondary)
            }
            ForEach(workspace.connectedProviders) { info in
                Button {
                    workspace.setActiveProvider(info.id)
                } label: {
                    if workspace.activeProviderID == info.id {
                        Label(info.name, systemImage: "checkmark")
                    } else {
                        Text(info.name)
                    }
                }
            }
            Divider()
            Button("Настроить провайдеров…") {
                openSettings()
            }
        } label: {
            Label(workspace.activeProviderName ?? "ИИ не подключён", systemImage: "cpu")
        }
        .fixedSize()
    }

    private var aiActionsMenu: some View {
        Menu {
            ForEach(AIMode.allCases) { mode in
                Button(mode.title) {
                    Task { await workspace.generate(mode) }
                }
                .disabled(!workspace.hasActiveProvider || workspace.isGenerating)
            }
        } label: {
            Label("AI", systemImage: "sparkles")
        }
        .fixedSize()
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

    private func rephraseSelected(_ style: RephraseStyle) {
        guard let scene, selectionRange.length > 0 else { return }
        let plain = textHandle.plainText as NSString
        guard selectionRange.location <= plain.length else { return }
        let clampedLength = min(selectionRange.length, plain.length - selectionRange.location)
        guard clampedLength > 0 else { return }
        let fragment = plain.substring(with: NSRange(location: selectionRange.location, length: clampedLength))
        Task {
            await workspace.rephrase(
                style: style,
                sourceText: fragment,
                location: selectionRange.location,
                length: clampedLength,
                sceneID: scene.id
            )
        }
    }

    private func splitSceneAtCaret() {
        guard let scene else { return }
        let text = textHandle.attributedText
        let length = (text.string as NSString).length
        let location = min(max(selectionRange.location, 0), length)
        let head = location > 0
            ? text.attributedSubstring(from: NSRange(location: 0, length: location))
            : NSAttributedString()
        let tail = location < length
            ? text.attributedSubstring(from: NSRange(location: location, length: length - location))
            : NSAttributedString()
        Task {
            await workspace.splitScene(
                scene.id,
                firstContent: WriterText.markdown(from: head),
                secondContent: WriterText.markdown(from: tail)
            )
        }
    }

    private func findSynonymsForSelection() {
        guard let scene, selectionRange.length > 0 else { return }
        let plain = textHandle.plainText as NSString
        guard selectionRange.location <= plain.length else { return }
        let clampedLength = min(selectionRange.length, plain.length - selectionRange.location)
        guard clampedLength > 0 else { return }
        let range = NSRange(location: selectionRange.location, length: clampedLength)
        let fragment = plain.substring(with: range)
        let contextSentence = (textHandle.plainText as String).sentenceRange(containing: range)
        let context = plain.substring(with: contextSentence)
        Task {
            await workspace.findSynonyms(
                fragment: fragment,
                context: context,
                location: range.location,
                length: range.length,
                sceneID: scene.id
            )
        }
    }

    private func applySynonym(_ index: Int) {
        defer {
            selectionRange = NSRange(location: 0, length: 0)
        }
        guard let request = workspace.synonymRequest,
              workspace.synonymVariants.indices.contains(index)
        else {
            workspace.clearSynonyms()
            return
        }
        let replacement = workspace.synonymVariants[index]
        if let newMarkdown = textHandle.replace(
            range: NSRange(location: request.location, length: request.length),
            with: replacement
        ) {
            markdownText = newMarkdown
            workspace.updateSceneContent(request.sceneID, content: newMarkdown)
        }
        workspace.clearSynonyms()
    }

    private func applyVariant(_ index: Int) {
        defer {
            selectionRange = NSRange(location: 0, length: 0)
        }
        guard let request = workspace.rephraseRequest,
              workspace.rephraseVariants.indices.contains(index)
        else {
            workspace.cancelRephrase()
            return
        }
        let replacement = workspace.rephraseVariants[index]
        if let newMarkdown = textHandle.replace(
            range: NSRange(location: request.location, length: request.length),
            with: replacement
        ) {
            markdownText = newMarkdown
            workspace.updateSceneContent(request.sceneID, content: newMarkdown)
        }
        workspace.cancelRephrase()
    }

    private func structuralMenuItems() -> [NSMenuItem] {
        let split = NSMenuItem(
            title: "Разделить сцену здесь",
            action: #selector(EditorActionBox.run(_:)),
            keyEquivalent: ""
        )
        split.target = actionBox
        split.representedObject = Self.splitActionKey
        var items: [NSMenuItem] = [split]
        if let scene,
           let index = workspace.scenes.firstIndex(where: { $0.id == scene.id }),
           index < workspace.scenes.count - 1 {
            let join = NSMenuItem(
                title: "Объединить со следующей сценой",
                action: #selector(EditorActionBox.run(_:)),
                keyEquivalent: ""
            )
            join.target = actionBox
            join.representedObject = Self.joinNextActionKey
            items.append(join)
        }
        return items
    }

    private func rephraseMenuItems() -> [NSMenuItem] {
        let submenu = NSMenu(title: "Переформулировать")
        for style in RephraseStyle.allCases {
            let item = NSMenuItem(
                title: style.title,
                action: #selector(EditorActionBox.run(_:)),
                keyEquivalent: ""
            )
            item.target = actionBox
            item.representedObject = style.rawValue
            submenu.addItem(item)
        }
        let root = NSMenuItem(title: "Переформулировать ИИ", action: nil, keyEquivalent: "")
        root.submenu = submenu
        let synonymsItem = NSMenuItem(
            title: "Синонимы и фразы ИИ",
            action: #selector(EditorActionBox.run(_:)),
            keyEquivalent: ""
        )
        synonymsItem.target = actionBox
        synonymsItem.representedObject = Self.synonymsActionKey
        return [root, synonymsItem]
    }
}

private final class MenuableTextView: NSTextView {
    var menuItemsBuilder: (() -> [NSMenuItem])?
    var structuralItemsBuilder: (() -> [NSMenuItem])?

    override func menu(for event: NSEvent) -> NSMenu? {
        let baseMenu = super.menu(for: event)
        guard let baseMenu else { return nil }
        if selectedRange().length > 0 {
            let extraItems = menuItemsBuilder?() ?? []
            if !extraItems.isEmpty {
                baseMenu.addItem(.separator())
                extraItems.forEach(baseMenu.addItem)
            }
        }
        let structural = structuralItemsBuilder?() ?? []
        if !structural.isEmpty {
            baseMenu.addItem(.separator())
            structural.forEach(baseMenu.addItem)
        }
        return baseMenu
    }
}

struct SelectionTextView: NSViewRepresentable {
    let markdown: String
    let handle: RichTextHandle
    var onChangeMarkdown: (String) -> Void
    var onSelectionChange: (NSRange) -> Void
    var menuItemsBuilder: () -> [NSMenuItem]
    var structuralItemsBuilder: () -> [NSMenuItem]

    static let editorFont: NSFont = WriterText.bodyFont

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectionTextView
        var lastEmittedMarkdown: String?

        init(_ parent: SelectionTextView) {
            self.parent = parent
        }

        func emitMarkdown() {
            guard let textView = parent.handle.textView else { return }
            let markdown = WriterText.markdown(from: textView.attributedString())
            lastEmittedMarkdown = markdown
            parent.onChangeMarkdown(markdown)
        }

        func textDidChange(_ notification: Notification) {
            emitMarkdown()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onSelectionChange(textView.selectedRange())
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MenuableTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.font = Self.editorFont
        textView.typingAttributes = [
            .font: Self.editorFont,
            .paragraphStyle: defaultParagraphStyle(),
            .foregroundColor: NSColor.textColor,
        ]
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]

        textView.textStorage?.setAttributedString(WriterText.attributed(from: markdown))

        context.coordinator.lastEmittedMarkdown = markdown
        handle.textView = textView
        textView.menuItemsBuilder = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return [] }
            return coordinator.parent.menuItemsBuilder()
        }
        textView.structuralItemsBuilder = { [weak coordinator = context.coordinator] in
            guard let coordinator else { return [] }
            return coordinator.parent.structuralItemsBuilder()
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? MenuableTextView else { return }
        if markdown != context.coordinator.lastEmittedMarkdown {
            let currentSelection = textView.selectedRange()
            textView.textStorage?.setAttributedString(WriterText.attributed(from: markdown))
            let length = (textView.string as NSString).length
            let location = min(currentSelection.location, length)
            let clamped = NSRange(location: location, length: min(currentSelection.length, length - location))
            textView.setSelectedRanges(
                [NSValue(range: clamped)],
                affinity: .downstream,
                stillSelecting: false
            )
            context.coordinator.lastEmittedMarkdown = markdown
        }
    }

    private func defaultParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 6
        style.lineSpacing = 2
        return style
    }
}
