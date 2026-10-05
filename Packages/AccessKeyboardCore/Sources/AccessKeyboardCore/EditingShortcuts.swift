import Foundation

public enum EditingShortcuts {
    public static let noPeriodAfter: Set<Character> = [".", "!", "?", "…", ",", ";", ":"]

    /// Marks that attach to the previous word. When the keyboard itself just
    /// inserted the space before the cursor, that space moves to after the
    /// mark, so `word ,` becomes `word, `.
    public static let spaceHuggingPunctuation: Set<String> = [",", ".", "?", "!", ":", ";", "…"]

    /// Punctuation which, typed from the numbers or symbols page, returns to
    /// the letters page. Includes the hugging marks plus apostrophes and
    /// quotes, which live on the numbers page but should not swallow a space
    /// (a quote often starts the next word).
    public static let alphabeticReturnPunctuation: Set<String> = spaceHuggingPunctuation.union([
        "'", "’", "\"", "“", "”"
    ])

    public static func returnsToAlphabetic(_ text: String) -> Bool {
        alphabeticReturnPunctuation.contains(text)
    }

    /// The text to insert instead of `punctuation` when an automatic trailing
    /// space should hop over the mark. Nil when the space should stay put.
    public static func replacementByMovingAutomaticSpace(
        punctuation: String,
        before: String,
        spaceIsAutomatic: Bool
    ) -> String? {
        guard spaceIsAutomatic,
              spaceHuggingPunctuation.contains(punctuation),
              before.hasSuffix(" ") else { return nil }
        return punctuation + " "
    }

    public static func shouldConvertDoubleSpace(_ before: String) -> Bool {
        guard before.count >= 2, before.last == " " else { return false }
        let prior = before[before.index(before.endIndex, offsetBy: -2)]
        if prior.isWhitespace { return false }
        return !noPeriodAfter.contains(prior)
    }

    public static func wordDeleteLength(in before: String) -> Int {
        guard !before.isEmpty else { return 0 }
        if before.last == "\n" { return 1 }

        var index = before.endIndex
        while index > before.startIndex {
            let previous = before.index(before: index)
            let character = before[previous]
            if character == "\n" { break }
            if character.isWhitespace {
                index = previous
                continue
            }
            break
        }
        while index > before.startIndex {
            let previous = before.index(before: index)
            if before[previous].isWhitespace { break }
            index = previous
        }
        return before.distance(from: index, to: before.endIndex)
    }

    public static func cursorOffset(
        before: String,
        after: String,
        horizontal: Int,
        vertical: Int
    ) -> Int {
        let text = before + after
        var cursor = before.count
        if vertical != 0 {
            cursor = movedToLine(in: text, cursor: cursor, lines: vertical)
        }
        cursor = min(max(0, cursor + horizontal), text.count)
        return cursor - before.count
    }

    public static func column(in before: String) -> Int {
        if let newline = before.lastIndex(of: "\n") {
            return before.distance(from: before.index(after: newline), to: before.endIndex)
        }
        return before.count
    }

    private static func movedToLine(in text: String, cursor: Int, lines: Int) -> Int {
        let ranges = lineContentRanges(in: text)
        guard !ranges.isEmpty else { return cursor }
        let currentLine = lineIndex(of: cursor, in: text)
        let targetLine = min(max(0, currentLine + lines), ranges.count - 1)
        let column = Self.column(in: String(text.prefix(cursor)))
        let range = ranges[targetLine]
        let length = range.count
        return range.lowerBound + min(column, length)
    }

    private static func lineIndex(of cursor: Int, in text: String) -> Int {
        text.prefix(cursor).reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
    }

    private static func lineContentRanges(in text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        var index = 0
        for character in text {
            if character == "\n" {
                ranges.append(start..<index)
                start = index + 1
            }
            index += 1
        }
        ranges.append(start..<index)
        return ranges
    }
}
