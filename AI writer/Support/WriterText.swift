import AppKit

enum WriterFormatAction {
    case bold
    case italic
    case strike
    case code
    case heading(Int)
    case bullet
    case ordered
    case quote
    case rule
}

enum WriterText {
    static let bodyFont: NSFont = {
        let descriptor = NSFont.systemFont(ofSize: 15).fontDescriptor.withDesign(.serif)
        return descriptor.flatMap { NSFont(descriptor: $0, size: 15) } ?? .systemFont(ofSize: 15)
    }()

    static let codeFont = NSFont(name: "Menlo", size: 13)
        ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static func headingFont(_ level: Int) -> NSFont {
        let size: CGFloat = [1: 24, 2: 20, 3: 17][level] ?? 15
        let weight: NSFont.Weight = level == 3 ? .semibold : .bold
        let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif)
        return descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? .boldSystemFont(ofSize: size)
    }

    private static func fontTraitMask(_ symbolicTraits: NSFontDescriptor.SymbolicTraits) -> NSFontTraitMask {
        var mask: NSFontTraitMask = []
        if symbolicTraits.contains(.bold) { mask.insert(.boldFontMask) }
        if symbolicTraits.contains(.italic) { mask.insert(.italicFontMask) }
        return mask
    }

    private static let headingKey = NSAttributedString.Key("writerHeading")
    private static let quoteKey = NSAttributedString.Key("writerQuote")
    private static let ruleKey = NSAttributedString.Key("writerRule")

    private static let inlineRegex = try! NSRegularExpression(
        pattern: """
        \\*\\*\\*(.+?)\\*\\*\\*|\\*\\*(.+?)\\*\\*|(?<![*])\\*([^*\\n]+?)\\*(?!\\*)|~~(.+?)~~|`([^`\\n]+)`
        """,
        options: []
    )

    // MARK: - Markdown → Attributed

    static func attributed(from markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            output.append(paragraph(fromLine: line))
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
            }
        }
        return output
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .paragraphStyle: plainParagraphStyle(),
            .foregroundColor: NSColor.textColor,
        ]
    }

    private static func plainParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 6
        style.lineSpacing = 2
        return style
    }

    private static func headingParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 12
        style.paragraphSpacing = 6
        return style
    }

    private static func quoteParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = 16
        style.paragraphSpacing = 6
        return style
    }

    private static func listParagraphStyle(markerFormat: NSTextList.MarkerFormat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let list = NSTextList(markerFormat: markerFormat, options: 0)
        style.textLists = [list]
        style.headIndent = 22
        style.paragraphSpacing = 4
        return style
    }

    private static func ruleParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacingBefore = 14
        style.paragraphSpacing = 14
        return style
    }

    private enum LineKind {
        case normal
        case rule
        case heading(Int)
        case quote
        case bullet
        case ordered
    }

    private static func classify(_ line: String) -> (kind: LineKind, contentStart: String.Index) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "***" || trimmed == "---" || trimmed == "___" {
            return (.rule, line.startIndex)
        }
        if line.hasPrefix("### ") {
            return (.heading(3), line.index(line.startIndex, offsetBy: 4))
        }
        if line.hasPrefix("## ") {
            return (.heading(2), line.index(line.startIndex, offsetBy: 3))
        }
        if line.hasPrefix("# ") {
            return (.heading(1), line.index(line.startIndex, offsetBy: 2))
        }
        if line.hasPrefix(">") {
            var start = line.index(after: line.startIndex)
            if start < line.endIndex, line[start] == " " {
                start = line.index(after: start)
            }
            return (.quote, start)
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return (.bullet, line.index(line.startIndex, offsetBy: 2))
        }
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }
        let digitCount = line.distance(from: line.startIndex, to: index)
        if digitCount > 0, digitCount < 5,
           index < line.endIndex,
           line[index] == "." || line[index] == ")",
           let afterMarker = line.index(index, offsetBy: 1, limitedBy: line.endIndex),
           afterMarker < line.endIndex,
           line[afterMarker] == " ",
           let contentStart = line.index(afterMarker, offsetBy: 1, limitedBy: line.endIndex)
        {
            return (.ordered, contentStart)
        }
        return (.normal, line.startIndex)
    }

    private static func paragraph(fromLine line: String) -> NSAttributedString {
        let (kind, contentStart) = classify(line)
        let body = String(line[contentStart...])

        switch kind {
        case .rule:
            var attrs = baseAttributes()
            attrs[.paragraphStyle] = ruleParagraphStyle()
            attrs[ruleKey] = true
            attrs[.foregroundColor] = NSColor.secondaryLabelColor
            return NSAttributedString(string: "⸻", attributes: attrs)
        case .heading(let level):
            var attrs = baseAttributes()
            attrs[.font] = headingFont(level)
            attrs[.paragraphStyle] = headingParagraphStyle()
            attrs[headingKey] = level
            let result = NSMutableAttributedString(string: body, attributes: attrs)
            decorateInline(result)
            return result
        case .quote:
            var attrs = baseAttributes()
            attrs[.paragraphStyle] = quoteParagraphStyle()
            attrs[quoteKey] = true
            attrs[.foregroundColor] = NSColor.secondaryLabelColor
            let result = NSMutableAttributedString(string: body, attributes: attrs)
            decorateInline(result)
            return result
        case .bullet:
            var attrs = baseAttributes()
            attrs[.paragraphStyle] = listParagraphStyle(markerFormat: .disc)
            let result = NSMutableAttributedString(string: body, attributes: attrs)
            decorateInline(result)
            return result
        case .ordered:
            var attrs = baseAttributes()
            attrs[.paragraphStyle] = listParagraphStyle(markerFormat: .decimal)
            let result = NSMutableAttributedString(string: body, attributes: attrs)
            decorateInline(result)
            return result
        case .normal:
            if body.isEmpty {
                return NSAttributedString(string: "", attributes: baseAttributes())
            }
            let result = NSMutableAttributedString(string: body, attributes: baseAttributes())
            decorateInline(result)
            return result
        }
    }

    private static func decorateInline(_ target: NSMutableAttributedString) {
        let source = target.copy() as! NSAttributedString
        target.mutableString.setString("")
        let nsSource = source.string as NSString
        let matches = inlineRegex.matches(
            in: source.string,
            range: NSRange(location: 0, length: nsSource.length)
        )
        var cursor = 0
        for match in matches {
            guard match.range.location >= cursor else { continue }
            appendRange(of: source, into: target, range: NSRange(location: cursor, length: match.range.location - cursor))
            if let group = [1, 2, 3, 4, 5].first(where: { match.range(at: $0).location != NSNotFound }) {
                let styled = NSMutableAttributedString(attributedString: source.attributedSubstring(from: match.range(at: group)))
                applyInlineStyle(group, to: styled)
                target.append(styled)
            }
            cursor = match.range.upperBound
        }
        appendRange(of: source, into: target, range: NSRange(location: cursor, length: nsSource.length - cursor))
    }

    private static func appendRange(of source: NSAttributedString, into target: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        target.append(source.attributedSubstring(from: range))
    }

    private static func applyInlineStyle(_ group: Int, to styled: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: (styled.string as NSString).length)
        switch group {
        case 1:
            addTrait(.bold, to: styled, range: full)
            addTrait(.italic, to: styled, range: full)
        case 2:
            addTrait(.bold, to: styled, range: full)
        case 3:
            addTrait(.italic, to: styled, range: full)
        case 4:
            styled.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: full)
        case 5:
            styled.addAttribute(.font, value: codeFont, range: full)
            styled.addAttribute(.backgroundColor, value: NSColor.quaternarySystemFill, range: full)
        default:
            break
        }
    }

    private static func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, to styled: NSMutableAttributedString, range: NSRange) {
        let manager = NSFontManager.shared
        styled.enumerateAttribute(.font, in: range) { value, subRange, _ in
            guard let font = value as? NSFont else { return }
            let converted = manager.convert(font, toHaveTrait: fontTraitMask(trait))
            styled.addAttribute(.font, value: converted, range: subRange)
        }
    }

    // MARK: - Attributed → Markdown

    static func markdown(from attributed: NSAttributedString) -> String {
        let ns = attributed.string as NSString
        guard ns.length > 0 else { return "" }

        var lines: [String] = []
        var orderedRunActive = false
        var orderedCounter = 0
        var lineStart = 0

        func flush(through end: Int) {
            defer { lineStart = end + 1 }
            guard end >= lineStart else {
                lines.append("")
                return
            }
            let sampleLocation = min(lineStart, max(ns.length - 1, 0))
            let attrs = attributed.attributes(at: sampleLocation, effectiveRange: nil)
            let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle

            if (attrs[ruleKey] as? Bool) == true {
                lines.append("***")
                orderedRunActive = false
                return
            }

            var prefix = ""
            var suppressBoldItalic = false
            if let level = attrs[headingKey] as? Int, (1...3).contains(level) {
                prefix += String(repeating: "#", count: level) + " "
                suppressBoldItalic = true
                orderedRunActive = false
            } else if (attrs[quoteKey] as? Bool) == true {
                prefix += "> "
                suppressBoldItalic = true
                orderedRunActive = false
            } else if let list = paragraphStyle?.textLists.first {
                if isDecimal(list) {
                    if !orderedRunActive {
                        orderedCounter = 0
                        orderedRunActive = true
                    }
                    orderedCounter += 1
                    prefix += "\(orderedCounter). "
                } else {
                    prefix += "- "
                    orderedRunActive = false
                }
            } else {
                orderedRunActive = false
            }

            lines.append(
                prefix + inlineMarkdown(
                    in: NSRange(location: lineStart, length: end - lineStart),
                    of: attributed,
                    suppressBoldItalic: suppressBoldItalic
                )
            )
        }

        for index in 0..<ns.length where ns.character(at: index) == unichar(10) {
            flush(through: index)
        }
        flush(through: ns.length)
        return lines.joined(separator: "\n")
    }

    private static func isDecimal(_ list: NSTextList) -> Bool {
        if #available(macOS 14.0, *) {
            return list.markerFormat == .decimal
        }
        return String(describing: list.markerFormat).contains("decimal")
    }

    private struct RunFlags: Equatable {
        var bold = false
        var italic = false
        var strike = false
        var code = false
    }

    private static func inlineMarkdown(
        in range: NSRange,
        of attributed: NSAttributedString,
        suppressBoldItalic: Bool
    ) -> String {
        guard range.length > 0 else { return "" }
        var segments: [(String, RunFlags)] = []

        attributed.enumerateAttributes(in: range) { attrs, subRange, _ in
            var flags = RunFlags()
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                flags.bold = !suppressBoldItalic && traits.contains(.bold)
                flags.italic = !suppressBoldItalic && traits.contains(.italic)
                let family = (font.familyName ?? "").lowercased()
                flags.code = family.contains("menlo") || family.contains("mono")
            }
            if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 {
                flags.strike = true
            }
            let text = attributed.attributedSubstring(from: subRange).string
            if let last = segments.last, last.1 == flags {
                segments[segments.count - 1].0 += text
            } else {
                segments.append((text, flags))
            }
        }

        var output = ""
        for (text, flags) in segments {
            var piece = text
            if flags.code { piece = "`\(piece)`" }
            if flags.strike { piece = "~~\(piece)~~" }
            switch (flags.bold, flags.italic) {
            case (true, true): piece = "***\(piece)***"
            case (true, false): piece = "**\(piece)**"
            case (false, true): piece = "*\(piece)*"
            default: break
            }
            output += piece
        }
        return output
    }

    // MARK: - Formatting operations

    static func apply(_ action: WriterFormatAction, to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let length = (textView.string as NSString).length
        let selected = textView.selectedRanges
            .compactMap { $0 as? NSValue }
            .map(\.rangeValue)
            .filter { $0.location <= length && NSMaxRange($0) <= length }

        switch action {
        case .bold: toggleInlineTrait(.bold, ranges: selected, storage: storage)
        case .italic: toggleInlineTrait(.italic, ranges: selected, storage: storage)
        case .strike: toggleStrike(ranges: selected, storage: storage)
        case .code: toggleCode(ranges: selected, storage: storage)
        case .heading(let level): toggleHeading(level, ranges: selected, storage: storage)
        case .bullet: toggleList(.disc, ranges: selected, storage: storage)
        case .ordered: toggleList(.decimal, ranges: selected, storage: storage)
        case .quote: toggleQuote(ranges: selected, storage: storage)
        case .rule: insertRule(at: selected.first?.location ?? length, storage: storage, textView: textView)
        }

        syncTypingAttributes(textView)
    }

    private static func syncTypingAttributes(_ textView: NSTextView) {
        let location = min(textView.selectedRange().location, max((textView.string as NSString).length - 1, 0))
        if location >= 0 {
            textView.typingAttributes = textView.attributedString().attributes(
                at: location,
                effectiveRange: nil
            )
        }
    }

    private static func paragraphRanges(around ranges: [NSRange], in storage: NSTextStorage) -> [NSRange] {
        let text = storage.string as NSString
        var collected: [NSRange] = []
        for range in ranges {
            var start = range.location
            while start > 0, text.character(at: start - 1) != unichar(10) { start -= 1 }
            var end = NSMaxRange(range) - 1
            while end < text.length - 1, text.character(at: end) != unichar(10) { end += 1 }
            let paragraph = NSRange(location: start, length: end - start + 1)
            if !collected.contains(paragraph) {
                collected.append(paragraph)
            }
        }
        return collected
    }

    private static func rangeHasTrait(_ trait: NSFontDescriptor.SymbolicTraits, range: NSRange, storage: NSTextStorage) -> Bool {
        guard range.length > 0 else {
            if let font = storage.attribute(.font, at: min(range.location, max(storage.length - 1, 0)), effectiveRange: nil) as? NSFont {
                return font.fontDescriptor.symbolicTraits.contains(trait)
            }
            return false
        }
        var allHave = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            guard let font = value as? NSFont, font.fontDescriptor.symbolicTraits.contains(trait) else {
                allHave = false
                stop.pointee = true
                return
            }
        }
        return allHave
    }

    private static func toggleInlineTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        ranges: [NSRange],
        storage: NSTextStorage
    ) {
        let manager = NSFontManager.shared
        for range in ranges {
            let adding = !rangeHasTrait(trait, range: range, storage: storage)
            let effective = range.length > 0
                ? range
                : NSRange(location: min(range.location, max(storage.length - 1, 0)), length: 1)
            storage.enumerateAttribute(.font, in: effective) { value, subRange, _ in
                guard let font = value as? NSFont else { return }
                let converted = adding
                    ? manager.convert(font, toHaveTrait: fontTraitMask(trait))
                    : manager.convert(font, toNotHaveTrait: fontTraitMask(trait))
                storage.addAttribute(.font, value: converted, range: subRange)
            }
        }
    }

    private static func toggleStrike(ranges: [NSRange], storage: NSTextStorage) {
        for range in ranges {
            let probe = range.length > 0 ? range : NSRange(location: min(range.location, max(storage.length - 1, 0)), length: 1)
            let current = storage.attribute(.strikethroughStyle, at: probe.location, effectiveRange: nil) as? Int ?? 0
            let next: Int = current != 0 ? 0 : NSUnderlineStyle.single.rawValue
            let effective = range.length > 0 ? range : probe
            storage.addAttribute(.strikethroughStyle, value: next, range: effective)
        }
    }

    private static func isCodeFont(_ font: NSFont?) -> Bool {
        guard let family = font?.familyName?.lowercased() else { return false }
        return family.contains("menlo") || family.contains("mono")
    }

    private static func toggleCode(ranges: [NSRange], storage: NSTextStorage) {
        for range in ranges {
            let probe = range.length > 0 ? range : NSRange(location: min(range.location, max(storage.length - 1, 0)), length: 1)
            let turningOn = !isCodeFont(storage.attribute(.font, at: probe.location, effectiveRange: nil) as? NSFont)
            let effective = range.length > 0 ? range : probe
            storage.enumerateAttribute(.font, in: effective) { value, subRange, _ in
                guard let font = value as? NSFont else { return }
                if turningOn {
                    storage.addAttributes([
                        .font: codeFont,
                        .backgroundColor: NSColor.quaternarySystemFill,
                    ], range: subRange)
                } else {
                    let restored = NSFontManager.shared.convert(bodyFont, toHaveTrait: fontTraitMask(font.fontDescriptor.symbolicTraits.intersection([.bold, .italic])))
                    storage.addAttributes([
                        .font: restored,
                        .backgroundColor: NSColor.clear,
                    ], range: subRange)
                }
            }
        }
    }

    private static func toggleHeading(_ level: Int, ranges: [NSRange], storage: NSTextStorage) {
        for paragraph in paragraphRanges(around: ranges, in: storage) {
            let current = storage.attribute(headingKey, at: paragraph.location, effectiveRange: nil) as? Int
            if current == level {
                storage.removeAttribute(headingKey, range: paragraph)
                storage.addAttribute(.font, value: bodyFont, range: paragraph)
                storage.addAttribute(.paragraphStyle, value: plainParagraphStyle(), range: paragraph)
            } else {
                storage.addAttribute(headingKey, value: level, range: paragraph)
                storage.addAttribute(.font, value: headingFont(level), range: paragraph)
                storage.addAttribute(.paragraphStyle, value: headingParagraphStyle(), range: paragraph)
            }
        }
    }

    private static func toggleList(_ marker: NSTextList.MarkerFormat, ranges: [NSRange], storage: NSTextStorage) {
        for paragraph in paragraphRanges(around: ranges, in: storage) {
            let style = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let existing = style?.textLists.first
            let sameKind = existing.map { isDecimal($0) == (marker == .decimal) } ?? false
            if sameKind {
                let reset = plainParagraphStyle()
                storage.addAttribute(.paragraphStyle, value: reset, range: paragraph)
            } else {
                storage.addAttribute(.paragraphStyle, value: listParagraphStyle(markerFormat: marker), range: paragraph)
            }
        }
    }

    private static func toggleQuote(ranges: [NSRange], storage: NSTextStorage) {
        for paragraph in paragraphRanges(around: ranges, in: storage) {
            let isQuote = (storage.attribute(quoteKey, at: paragraph.location, effectiveRange: nil) as? Bool) == true
            if isQuote {
                storage.removeAttribute(quoteKey, range: paragraph)
                storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: paragraph)
                storage.addAttribute(.paragraphStyle, value: plainParagraphStyle(), range: paragraph)
                removeTrait(.italic, paragraph: paragraph, storage: storage)
            } else {
                storage.addAttribute(quoteKey, value: true, range: paragraph)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: paragraph)
                storage.addAttribute(.paragraphStyle, value: quoteParagraphStyle(), range: paragraph)
                addItalic(paragraph: paragraph, storage: storage)
            }
        }
    }

    private static func addItalic(paragraph: NSRange, storage: NSTextStorage) {
        let manager = NSFontManager.shared
        storage.enumerateAttribute(.font, in: paragraph) { value, subRange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: manager.convert(font, toHaveTrait: .italicFontMask), range: subRange)
        }
    }

    private static func removeTrait(_ trait: NSFontDescriptor.SymbolicTraits, paragraph: NSRange, storage: NSTextStorage) {
        let manager = NSFontManager.shared
        storage.enumerateAttribute(.font, in: paragraph) { value, subRange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: manager.convert(font, toNotHaveTrait: fontTraitMask(trait)), range: subRange)
        }
    }

    private static func insertRule(at location: Int, storage: NSTextStorage, textView: NSTextView) {
        let safeLocation = min(max(location, 0), storage.length)
        var insertion = NSMutableAttributedString(string: "\n", attributes: baseAttributes())
        insertion.append(ruleParagraph())
        insertion.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
        storage.insert(insertion, at: safeLocation)
        let newPosition = min(safeLocation + insertion.length, (textView.string as NSString).length)
        textView.setSelectedRanges(
            [NSValue(range: NSRange(location: newPosition, length: 0))],
            affinity: .downstream,
            stillSelecting: false
        )
    }

    private static func ruleParagraph() -> NSAttributedString {
        var attrs = baseAttributes()
        attrs[.paragraphStyle] = ruleParagraphStyle()
        attrs[ruleKey] = true
        attrs[.foregroundColor] = NSColor.secondaryLabelColor
        return NSAttributedString(string: "⸻", attributes: attrs)
    }
}
