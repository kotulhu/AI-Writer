import Foundation

extension String {
    var wordCount: Int {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var singleLine: String {
        replacingOccurrences(of: "\n", with: " ")
    }

    func truncated(to limit: Int) -> String {
        if count <= limit { return self }
        return prefix(limit) + "…"
    }

    func sentenceRange(containing range: NSRange) -> NSRange {
        let source = self as NSString
        let length = source.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }

        var terminators = Set<unichar>()
        for scalar in ".!?…\n".unicodeScalars {
            terminators.insert(unichar(scalar.value))
        }

        func isTerminator(_ index: Int) -> Bool {
            index >= 0 && index < length && terminators.contains(source.character(at: index))
        }

        var start = min(max(range.location, 0), length - 1)
        while start > 0, !isTerminator(start - 1) {
            start -= 1
        }
        if start > 0 { start += 1 }

        var end = min(NSMaxRange(range), length)
        while end < length, !isTerminator(end) {
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }
}
