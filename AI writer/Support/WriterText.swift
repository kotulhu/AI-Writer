import AppKit

/// Converts between Markdown (the stored source of truth) and the rich text
/// shown in the block editor.
enum WriterText {
    static let bodySize: CGFloat = 15
    static let quoteKey = NSAttributedString.Key("AIWriter.quote")

    // MARK: - Fonts

    static func bodyFont() -> NSFont {
        makeFont(size: bodySize, bold: false, italic: false)
    }

    static func headingFont(level: Int) -> NSFont {
        makeFont(size: headingSize(level: level), bold: true, italic: false)
    }

    static func codeFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func headingSize(level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 23
        case 3: return 19
        default: return 16
        }
    }

    static func makeFont(size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits(traits)
        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size)
    }

    static func headingLevel(of font: NSFont) -> Int {
        guard font.fontDescriptor.symbolicTraits.contains(.bold) else { return 0 }
        switch Double(font.pointSize) {
        case 27...29: return 1
        case 22...24: return 2
        case 18...20: return 3
        case 15...17: return 4
        default: return 0
        }
    }

    static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont(),
            .paragraphStyle: paragraphStyle(indent: 0)
        ]
    }

    static func paragraphStyle(indent: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 4
        if indent > 0 {
            style.headIndent = indent
            style.firstLineHeadIndent = indent
        }
        return style
    }

    static func headingParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 6
        style.paragraphSpacingBefore = 6
        return style
    }

    // MARK: - Render (Markdown -> NSAttributedString)

    static func render(markdown: String) -> NSAttributedString {
        guard !markdown.isEmpty else { return NSAttributedString() }
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")

        for (i, rawLine) in lines.enumerated() {
            var line = rawLine
            let style = detectLineStyle(&line)

            switch style {
            case .blank:
                if i < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont()]))
                }
            case let .heading(level), let .paragraph(level):
                let size = level > 0 ? headingSize(level: level) : bodySize
                let lineAttributed = parseInline(line, size: size, baseBold: level > 0, baseItalic: false)
                if lineAttributed.length > 0 {
                    lineAttributed.addAttribute(
                        .paragraphStyle,
                        value: level > 0 ? headingParagraphStyle() : paragraphStyle(indent: 0),
                        range: NSRange(location: 0, length: lineAttributed.length)
                    )
                }
                result.append(lineAttributed)
                if i < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont()]))
                }
            case .quote:
                let lineAttributed = parseInline(line, size: bodySize, baseBold: false, baseItalic: false)
                if lineAttributed.length > 0 {
                    lineAttributed.addAttribute(
                        .paragraphStyle,
                        value: paragraphStyle(indent: 20),
                        range: NSRange(location: 0, length: lineAttributed.length)
                    )
                    lineAttributed.addAttribute(quoteKey, value: true, range: NSRange(location: 0, length: lineAttributed.length))
                }
                result.append(lineAttributed)
                if i < lines.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont()]))
                }
            }
        }

        return result
    }

    private enum LineStyle {
        case blank
        case heading(Int)
        case paragraph(Int)
        case quote
    }

    private static func detectLineStyle(_ line: inout String) -> LineStyle {
        if line.isEmpty { return .blank }
        if line.hasPrefix("##### ") || line.hasPrefix("###### ") {
            return .paragraph(0)
        }
        if line.hasPrefix("#### ") {
            line.removeFirst(5)
            return .heading(4)
        }
        if line.hasPrefix("### ") {
            line.removeFirst(4)
            return .heading(3)
        }
        if line.hasPrefix("## ") {
            line.removeFirst(3)
            return .heading(2)
        }
        if line.hasPrefix("# ") {
            line.removeFirst(2)
            return .heading(1)
        }
        if line.hasPrefix("> ") {
            line.removeFirst(2)
            return .quote
        }
        return .paragraph(0)
    }

    // MARK: - Inline parser

    private static func parseInline(
        _ text: String,
        size: CGFloat,
        baseBold: Bool,
        baseItalic: Bool
    ) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let ns = text as NSString
        let n = ns.length
        var i = 0
        var plainStart = 0

        func flushPlain(_ end: Int) {
            guard end > plainStart else { return }
            let segment = ns.substring(with: NSRange(location: plainStart, length: end - plainStart))
            out.append(NSAttributedString(string: segment, attributes: [
                .font: makeFont(size: size, bold: baseBold, italic: baseItalic)
            ]))
        }

        while i < n {
            let c = ns.character(at: i)

            if i + 1 < n, ns.substring(with: NSRange(location: i, length: 2)) == "**" {
                if let close = ns.range(of: "**", options: [], range: NSRange(location: i + 2, length: n - i - 2)).location as Int? {
                    flushPlain(i)
                    let inner = ns.substring(with: NSRange(location: i + 2, length: close - (i + 2)))
                    out.append(parseInline(inner, size: size, baseBold: true, baseItalic: baseItalic))
                    i = close + 2
                    plainStart = i
                    continue
                }
            }

            if c == 42 || c == 95 { // * od _
                let marker = c == 42 ? "*" : "_"
                if let close = ns.range(of: marker, options: [], range: NSRange(location: i + 1, length: n - i - 1)).location as Int? {
                    flushPlain(i)
                    let inner = ns.substring(with: NSRange(location: i + 1, length: close - (i + 1)))
                    out.append(parseInline(inner, size: size, baseBold: baseBold, baseItalic: true))
                    i = close + 1
                    plainStart = i
                    continue
                }
            }

            if i + 1 < n, ns.substring(with: NSRange(location: i, length: 2)) == "~~" {
                if let close = ns.range(of: "~~", options: [], range: NSRange(location: i + 2, length: n - i - 2)).location as Int? {
                    flushPlain(i)
                    let innerString = ns.substring(with: NSRange(location: i + 2, length: close - (i + 2)))
                    let inner = parseInline(innerString, size: size, baseBold: baseBold, baseItalic: baseItalic)
                    if inner.length > 0 {
                        inner.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: inner.length))
                    }
                    out.append(inner)
                    i = close + 2
                    plainStart = i
                    continue
                }
            }

            if c == 96 { // `
                if let close = ns.range(of: "`", options: [], range: NSRange(location: i + 1, length: n - i - 1)).location as Int? {
                    flushPlain(i)
                    let inner = ns.substring(with: NSRange(location: i + 1, length: close - (i + 1)))
                    out.append(NSAttributedString(string: inner, attributes: [
                        .font: codeFont(size: size - 1)
                    ]))
                    i = close + 1
                    plainStart = i
                    continue
                }
            }

            if i + 3 < n, ns.substring(with: NSRange(location: i, length: 3)) == "<u>" {
                if let close = ns.range(of: "</u>", options: [], range: NSRange(location: i + 3, length: n - i - 3)).location as Int? {
                    flushPlain(i)
                    let innerString = ns.substring(with: NSRange(location: i + 3, length: close - (i + 3)))
                    let inner = parseInline(innerString, size: size, baseBold: baseBold, baseItalic: baseItalic)
                    if inner.length > 0 {
                        inner.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: inner.length))
                    }
                    out.append(inner)
                    i = close + 4
                    plainStart = i
                    continue
                }
            }

            i += 1
        }

        flushPlain(n)
        return out
    }

    // MARK: - Serialize (NSAttributedString -> Markdown)

    static func serialize(_ attributed: NSAttributedString) -> String {
        let text = attributed.string as NSString
        guard text.length > 0 else { return "" }

        var output = ""
        var location = 0

        while location < text.length {
            let paragraphRange = (text as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let range = paragraphRange
            let raw = text.substring(with: range)

            if raw.hasSuffix("\n") {
                let trimmed = String(raw.dropLast())

                if trimmed.isEmpty {
                    output += "\n"
                } else {
                    emitParagraph(attributed, text: trimmed, range: NSRange(location: range.location, length: (trimmed as NSString).length), into: &output)
                    output += "\n"
                }
            } else if raw.isEmpty {
                if attributed.length > 0 {
                    output += "\n"
                }
            } else {
                emitParagraph(attributed, text: raw, range: NSRange(location: range.location, length: raw.utf16.count), into: &output)
            }

            let advanced = range.location + range.length
            if advanced <= location {
                break
            }
            location = advanced
        }

        return output
    }

    private static func emitParagraph(
        _ attributed: NSAttributedString,
        text: String,
        range: NSRange,
        into output: inout String
    ) {
        let text = text as NSString

        let isQuote = (attributed.attribute(quoteKey, at: range.location, effectiveRange: nil) as? Bool) ?? false
        let probeFont = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? bodyFont()
        let level = headingLevel(of: probeFont)

        let baseBold = level > 0
        let baseItalic = false
        let baseIsCode = false

        if level > 0 {
            output += String(repeating: "#", count: level) + " "
        } else {
            if isQuote {
                output += "> "
            }
        }

        attributed.enumerateAttributes(in: range, options: []) { attributes, runRange, _ in
            let relative = NSRange(location: runRange.location - range.location, length: runRange.length)
            let runText = text.substring(with: relative)
            guard !runText.isEmpty else { return }

            let font = attributes[.font] as? NSFont ?? baseFont(level: level)
            let runBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            let runItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
            let runIsCode = font.fontName.contains("Mono")

            let isUnderline = (attributes[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
            let isStrike = (attributes[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue

            var closing = ""

            if isUnderline {
                output += "<u>"
                closing = "</u>" + closing
            }
            if runIsCode && !baseIsCode {
                output += "`"
                closing = "`" + closing
            }
            if runBold && !baseBold {
                output += "**"
                closing = "**" + closing
            }
            if runItalic && !baseItalic {
                output += "*"
                closing = "*" + closing
            }
            if isStrike {
                output += "~~"
                closing = "~~" + closing
            }

            output += runText
            output += closing
        }
    }

    private static func baseFont(level: Int) -> NSFont {
        level > 0 ? headingFont(level: level) : bodyFont()
    }
}