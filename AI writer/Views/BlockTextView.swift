import AppKit
import SwiftData
import SwiftUI
import OSLog

private let editorLog = Logger(subsystem: "AIWriter", category: "Editor")

enum EditorDiag {
    static let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        .map { $0.appendingPathComponent("editor.log") }

    static func log(_ message: String) {
        editorLog.info("\(message, privacy: .public)")
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)
        guard let url = logURL else { return }
        let didExist = FileManager.default.fileExists(atPath: url.path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        if !didExist {
            try? FileHandle.standardError.write(contentsOf: "EditorDiag file: \(url.path)\n".data(using: .utf8)!)
        }
    }
}

// MARK: - Coordinator (bridge from SwiftUI toolbar to NSTextView)

@MainActor
final class BlockTextViewCoordinator: NSObject, NSTextViewDelegate {
    static weak var current: BlockTextViewCoordinator?

    var textView: BlockTextViewEditor?
    var block: Block?
    weak var store: ManuscriptStore?
    weak var modelContext: ModelContext?

    override init() {
        super.init()
        Self.current = self
    }

    var markdown: String {
        guard let storage = textView?.textStorage else { return block?.content ?? "" }
        return WriterText.serialize(storage)
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        flush()
    }

    func flush(saveNow: Bool = false) {
        guard let block, let modelContext else { return }
        let md = markdown
        if saveNow {
            store?.saveNow(block, content: md, context: modelContext)
        } else {
            store?.scheduleAutoSave(block, content: md, context: modelContext)
        }
    }

    // MARK: Formatting commands (invoked from the SwiftUI toolbar)

    func toggleBold() {
        toggleFontTrait(.bold)
    }

    func toggleItalic() {
        toggleFontTrait(.italic)
    }

    func toggleUnderline() {
        toggleDecoration(.underlineStyle)
    }

    func toggleStrike() {
        toggleDecoration(.strikethroughStyle)
    }

    private func toggleFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()

        if range.length == 0 {
            let current = tv.typingAttributes[.font] as? NSFont ?? WriterText.bodyFont()
            var traits = current.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let font = NSFont(descriptor: current.fontDescriptor.withSymbolicTraits(traits), size: current.pointSize) {
                tv.typingAttributes[.font] = font
            }
            flush()
            return
        }

        let sample = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? WriterText.bodyFont()
        let add = !sample.fontDescriptor.symbolicTraits.contains(trait)

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = value as? NSFont ?? WriterText.bodyFont()
            var traits = font.fontDescriptor.symbolicTraits
            if add { traits.insert(trait) } else { traits.remove(trait) }
            if let newFont = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) {
                storage.addAttribute(.font, value: newFont, range: subrange)
            }
        }
        storage.endEditing()

        var sampleTraits = sample.fontDescriptor.symbolicTraits
        if add { sampleTraits.insert(trait) } else { sampleTraits.remove(trait) }
        if let font = NSFont(descriptor: sample.fontDescriptor.withSymbolicTraits(sampleTraits), size: sample.pointSize) {
            tv.typingAttributes[.font] = font
        }
        flush()
    }

    private func toggleDecoration(_ key: NSAttributedString.Key) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        let sample: Int
        if range.length == 0 {
            sample = tv.typingAttributes[key] as? Int ?? 0
        } else {
            sample = storage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0
        }
        let target = sample == NSUnderlineStyle.single.rawValue ? 0 : NSUnderlineStyle.single.rawValue
        if range.length == 0 {
            tv.typingAttributes[key] = target
        } else {
            storage.addAttribute(key, value: target, range: range)
        }
        flush()
    }

    func applyHeading(_ level: Int) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let paraRange = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
        let font = level > 0 ? WriterText.headingFont(level: level) : WriterText.bodyFont()
        let style: NSParagraphStyle = level > 0 ? WriterText.headingParagraphStyle() : WriterText.paragraphStyle(indent: 0)

        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: paraRange)
        storage.addAttribute(.paragraphStyle, value: style, range: paraRange)
        storage.removeAttribute(WriterText.quoteKey, range: paraRange)
        storage.removeAttribute(.underlineStyle, range: paraRange)
        storage.endEditing()

        tv.typingAttributes = [.font: font, .paragraphStyle: style]
        flush()
    }

    func toggleQuote() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let paraRange = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
        let isQuote = (storage.attribute(WriterText.quoteKey, at: paraRange.location, effectiveRange: nil) as? Bool) ?? false

        storage.beginEditing()
        if isQuote {
            storage.removeAttribute(WriterText.quoteKey, range: paraRange)
            storage.addAttribute(.paragraphStyle, value: WriterText.paragraphStyle(indent: 0), range: paraRange)
            storage.addAttribute(.font, value: WriterText.bodyFont(), range: paraRange)
        } else {
            storage.addAttribute(WriterText.quoteKey, value: true, range: paraRange)
            storage.addAttribute(.paragraphStyle, value: WriterText.paragraphStyle(indent: 20), range: paraRange)
            storage.addAttribute(.font, value: WriterText.bodyFont(), range: paraRange)
        }
        storage.endEditing()

        tv.typingAttributes = [
            .font: WriterText.bodyFont(),
            .paragraphStyle: isQuote ? WriterText.paragraphStyle(indent: 0) : WriterText.paragraphStyle(indent: 20)
        ]
        flush()
    }

    func splitOffset() -> Int {
        textView?.selectedRange().location ?? 0
    }

    func assertFocus() {
        textView?.bringToFront()
    }
}

// MARK: - Editor text view

final class BlockTextViewEditor: NSTextView {
    private var keyObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isEditable = true
        isSelectable = true
        isRichText = true
        allowsUndo = true
        textContainerInset = NSSize(width: 14, height: 16)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        minSize = NSSize(width: 0, height: 100)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        font = WriterText.bodyFont()
        isAutomaticQuoteSubstitutionEnabled = false
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }

    func bringToFront() {
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let observer = keyObserver {
            NotificationCenter.default.removeObserver(observer)
            keyObserver = nil
        }

        guard let window else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self)
        }

        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] note in
            guard let self, let window = note.object as? NSWindow else { return }
            let fr = window.firstResponder
            let isWindowOrHost = fr === window || fr === window.contentView
            if isWindowOrHost {
                self.bringToFront()
            }
        }
    }
}

// MARK: - Scroll view that forwards clicks into the text view

final class EditorScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let tv = documentView as? BlockTextViewEditor {
            tv.bringToFront()
        }
        super.mouseDown(with: event)
    }

    override func layout() {
        super.layout()
        guard let tv = documentView as? BlockTextViewEditor else { return }
        let targetWidth = max(contentView.bounds.width, 10)
        if abs(tv.frame.width - targetWidth) > 0.5 {
            tv.frame.size.width = targetWidth
        }
    }
}

// MARK: - SwiftUI representable

struct BlockTextViewRepresentable: NSViewRepresentable {
    var block: Block
    var store: ManuscriptStore
    var modelContext: ModelContext

    func makeCoordinator() -> BlockTextViewCoordinator {
        BlockTextViewCoordinator()
    }

    func makeNSView(context: Context) -> EditorScrollView {
        let scroll = EditorScrollView(frame: .zero)
        scroll.drawsBackground = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false

        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)

        let textView = BlockTextViewEditor(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            textContainer: container
        )
        textView.textStorage?.setAttributedString(WriterText.render(markdown: block.content))
        if textView.textStorage == nil {
            EditorDiag.log("Editor WARN makeNSView textStorage is nil after explicit container")
        }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = context.coordinator

        scroll.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.block = block
        context.coordinator.store = store
        context.coordinator.modelContext = modelContext

        EditorDiag.log("Editor makeNSView created textView")
        return scroll
    }

    func updateNSView(_ scrollView: EditorScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.block = block
        coordinator.store = store
        coordinator.modelContext = modelContext

        if let textView = coordinator.textView {
            let target = WriterText.render(markdown: block.content)
            if (textView.textStorage?.string ?? "") != target.string {
                textView.textStorage?.setAttributedString(target)
            }
        }
    }

    static func dismantleNSView(_ scrollView: EditorScrollView, coordinator: BlockTextViewCoordinator) {
        if coordinator.block != nil {
            coordinator.flush(saveNow: true)
        }
        coordinator.textView = nil
        BlockTextViewCoordinator.current = nil
    }
}