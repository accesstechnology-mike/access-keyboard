import Foundation

struct WordTransition: Equatable {
    var word: String
    var count: Int
}

final class PredictionMemory {
    static let shared = PredictionMemory()

    private var table: [String: [String: Int]]
    private let defaults: UserDefaults?
    private let storageKey: String

    private let maxPreviousWords = 400
    private let maxNextWordsPerPrevious = 24

    init(defaults: UserDefaults? = .standard, storageKey: String = "access.keyboard.wordBigrams") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults?.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            table = decoded
        } else {
            table = [:]
        }
    }

    init(table: [String: [String: Int]]) {
        self.table = table
        defaults = nil
        storageKey = ""
    }

    func record(previous: String?, next: String) {
        let nextWord = normalize(next)
        guard isLearnable(nextWord) else { return }
        let previousWord = previous.flatMap { normalize($0) }.flatMap { isLearnable($0) ? $0 : nil } ?? ""
        var nextCounts = table[previousWord] ?? [:]
        nextCounts[nextWord, default: 0] += 1
        if nextCounts.count > maxNextWordsPerPrevious {
            let trimmed = Dictionary(uniqueKeysWithValues: nextCounts.sorted { $0.value > $1.value }.prefix(maxNextWordsPerPrevious).map { ($0.key, $0.value) })
            nextCounts = trimmed
        }
        table[previousWord] = nextCounts
        pruneIfNeeded()
        persist()
    }

    func nextWords(after previous: String?) -> [WordTransition] {
        let key = previous.flatMap { normalize($0) } ?? ""
        let counts = table[key] ?? [:]
        return counts
            .map { WordTransition(word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    func count(previous: String?, next: String) -> Int {
        let key = previous.flatMap { normalize($0) } ?? ""
        return table[key]?[normalize(next)] ?? 0
    }

    private func pruneIfNeeded() {
        guard table.count > maxPreviousWords else { return }
        let keep = table.sorted { lhs, rhs in
            lhs.value.values.reduce(0, +) > rhs.value.values.reduce(0, +)
        }.prefix(maxPreviousWords)
        table = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let defaults,
              let data = try? JSONEncoder().encode(table) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isLearnable(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(trimmed.count) else { return false }
        return trimmed.rangeOfCharacter(from: .letters) != nil
    }
}
