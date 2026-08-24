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
}
