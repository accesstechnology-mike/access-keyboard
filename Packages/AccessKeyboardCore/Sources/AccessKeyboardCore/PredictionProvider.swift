import NaturalLanguage
import UIKit

public struct Prediction: Equatable {
    public var displayText: String
    public var insertion: String
    public var isVerbatim: Bool

    public init(displayText: String, insertion: String, isVerbatim: Bool) {
        self.displayText = displayText
        self.insertion = insertion
        self.isVerbatim = isVerbatim
    }
}

enum PredictionProvider {
    static func suggestions(
        prefix: String,
        before: String?,
        memory: PredictionMemory = PredictionMemory(table: [:])
    ) -> [Prediction] {
        let word = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if word.isEmpty {
            return nextWordSuggestions(before: before, memory: memory)
        }

        let previous = previousWord(in: before, currentPrefix: word)
        var scored = frequencyMatches(prefix: word)

        let language = lexiconLanguage()
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let completions = checker.completions(forPartialWordRange: range, in: word, language: language) ?? []
        for (index, completion) in completions.enumerated() {
            let candidate = matchingCase(completion, prefix: word)
            let key = candidate.lowercased()
            guard key.hasPrefix(word.lowercased()), key != word.lowercased() else { continue }
            if scored.contains(where: { $0.word.lowercased() == key }) { continue }
            scored.append(ScoredWord(word: candidate, frequencyRank: 10_000 + index))
        }

        guard !scored.isEmpty else {
            return typoSuggestions(word: word, checker: checker, range: range, language: language)
        }

        scored = applyContext(scored, previousWord: previous)
        scored = applyLearned(scored, previousWord: previous, memory: memory)
        scored.sort { $0.score < $1.score }

        return scored.prefix(3).map { item in
            Prediction(displayText: item.word, insertion: item.word, isVerbatim: false)
        }
    }

    static func currentWordPrefix(in before: String?) -> String {
        guard let before, !before.isEmpty else { return "" }
        return lastToken(in: before) ?? ""
    }

    static func previousWord(in before: String?, currentPrefix: String) -> String? {
        guard var text = before, !text.isEmpty else { return nil }
        if !currentPrefix.isEmpty, text.hasSuffix(currentPrefix) {
            text.removeLast(currentPrefix.count)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastToken(in: text)
    }

    private struct ScoredWord {
        var word: String
        var frequencyRank: Int
        var score: Double {
            Double(frequencyRank)
        }
    }

    private static func nextWordSuggestions(before: String?, memory: PredictionMemory) -> [Prediction] {
        let previous = previousWord(in: before, currentPrefix: "")
        let casePrefix = capitalizationHint(before: before)
        var scored: [ScoredWord] = []
        var seen = Set<String>()

        for transition in memory.nextWords(after: previous) {
            seen.insert(transition.word)
            scored.append(
                ScoredWord(
                    word: matchingCase(transition.word, prefix: casePrefix),
                    frequencyRank: -transition.count * 2_000
                )
            )
        }

        for (word, rank) in rankedWords.prefix(120) {
            guard seen.insert(word).inserted else { continue }
            if let previous, word == previous.lowercased() { continue }
            scored.append(
                ScoredWord(
                    word: matchingCase(word, prefix: casePrefix),
                    frequencyRank: rank + 800
                )
            )
        }

        scored = applyContext(scored, previousWord: previous)
        scored.sort { $0.score < $1.score }
        return scored.prefix(3).map { item in
            Prediction(displayText: item.word, insertion: item.word, isVerbatim: false)
        }
    }

    private static func frequencyMatches(prefix: String) -> [ScoredWord] {
        let needle = prefix.lowercased()
        var matches: [ScoredWord] = []
        matches.reserveCapacity(32)
        for (word, rank) in wordRanks {
            guard word.hasPrefix(needle), word != needle else { continue }
            matches.append(ScoredWord(word: matchingCase(word, prefix: prefix), frequencyRank: rank))
        }
        matches.sort { $0.frequencyRank < $1.frequencyRank }
        if matches.count > 24 {
            matches = Array(matches.prefix(24))
        }
        return matches
    }

    private static func applyContext(_ candidates: [ScoredWord], previousWord: String?) -> [ScoredWord] {
        guard let previous = previousWord?.lowercased(), previous.count > 1,
              let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return candidates
        }

        return candidates.map { item in
            var next = item
            let distance = embedding.distance(between: previous, and: item.word.lowercased())
            let clamped = distance.isFinite ? min(max(distance, 0), 2) : 2
            next.frequencyRank = item.frequencyRank + Int((clamped * 40).rounded())
            return next
        }
    }

    private static func applyLearned(
        _ candidates: [ScoredWord],
        previousWord: String?,
        memory: PredictionMemory
    ) -> [ScoredWord] {
        candidates.map { item in
            var next = item
            let count = memory.count(previous: previousWord, next: item.word)
            next.frequencyRank -= count * 500
            return next
        }
    }

    private static func typoSuggestions(
        word: String,
        checker: UITextChecker,
        range: NSRange,
        language: String
    ) -> [Prediction] {
        let guesses = checker.guesses(forWordRange: range, in: word, language: language) ?? []
        var result: [Prediction] = [
            Prediction(displayText: "“\(word)”", insertion: word, isVerbatim: true)
        ]
        var seen = Set([word.lowercased()])
        for guess in guesses where result.count < 3 {
            let value = matchingCase(guess, prefix: word)
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(Prediction(displayText: value, insertion: value, isVerbatim: false))
        }
        return result
    }

    private static func lastToken(in text: String) -> String? {
        let allowed = CharacterSet.letters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "'’"))
        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            let scalarOK = text[previous].unicodeScalars.allSatisfy { allowed.contains($0) }
            if scalarOK {
                index = previous
            } else {
                break
            }
        }
        let token = String(text[index...])
        return token.isEmpty ? nil : token
    }

    private static func capitalizationHint(before: String?) -> String {
        guard let before, !before.isEmpty else { return "A" }
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "A" }
        if let last = trimmed.last, [".", "!", "?", "\n"].contains(last) {
            return "A"
        }
        return "a"
    }

    private static func matchingCase(_ suggestion: String, prefix: String) -> String {
        guard let first = prefix.first else { return suggestion }
        if prefix.count > 1, prefix == prefix.uppercased() {
            return suggestion.uppercased()
        }
        if first.isUppercase {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
        }
        return suggestion
    }

    private static func lexiconLanguage() -> String {
        let available = UITextChecker.availableLanguages
        let availableSet = Set(available)
        for preferred in Locale.preferredLanguages {
            let identifier = preferred.replacingOccurrences(of: "-", with: "_")
            if availableSet.contains(identifier) {
                return identifier
            }
            let prefix = String(identifier.prefix(while: { $0 != "_" && $0 != "-" }))
            if let match = available.first(where: { $0.hasPrefix(prefix) }) {
                return match
            }
        }
        return available.first ?? "en"
    }

    private static let wordRanks: [String: Int] = {
        guard let url = Bundle.module.url(forResource: "google-10000-english-usa", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var ranks: [String: Int] = [:]
        ranks.reserveCapacity(10_000)
        for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !word.isEmpty, ranks[word] == nil else { continue }
            ranks[word] = index
        }
        return ranks
    }()

    private static let rankedWords: [(String, Int)] = {
        wordRanks.sorted { $0.value < $1.value }.map { ($0.key, $0.value) }
    }()
}
