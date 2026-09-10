import XCTest
@testable import AccessKeyboardCore

/// Learning must survive the keyboard extension being torn down and relaunched.
/// The live path stores bigrams in the shared App Group `UserDefaults`; these
/// tests use a throwaway suite to prove a fresh `PredictionMemory` reads back
/// what an earlier one recorded, and that recorded words rank higher.
final class PredictionMemoryTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.access.keyboard.memory.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRecordedBigramPersistsAcrossInstances() {
        let key = "test.wordBigrams"
        let first = PredictionMemory(defaults: defaults, storageKey: key)
        first.record(previous: "please", next: "help")
        first.record(previous: "please", next: "help")

        let reloaded = PredictionMemory(defaults: defaults, storageKey: key)
        XCTAssertEqual(reloaded.count(previous: "please", next: "help"), 2)
        XCTAssertEqual(reloaded.nextWords(after: "please").first?.word, "help")
    }

    func testLearnedWordOutranksDefaultsAfterReload() {
        let key = "test.wordBigrams"
        let first = PredictionMemory(defaults: defaults, storageKey: key)
        for _ in 0..<3 {
            first.record(previous: "please", next: "help")
        }

        let reloaded = PredictionMemory(defaults: defaults, storageKey: key)
        let words = PredictionProvider.suggestions(prefix: "", before: "Please ", memory: reloaded)
            .map { $0.insertion.lowercased() }
        XCTAssertEqual(words.first, "help", "a learned frequent word should lead the bar")
    }
}

/// Proves the live keyboard path (typing through `KeyboardEngine`) feeds the
/// learning store, not just direct `record` calls in a test.
@MainActor
final class KeyboardEngineLearningTests: XCTestCase {
    func testTypingWordsRecordsBigram() {
        let memory = PredictionMemory(table: [:])
        let document = FakeDocument(text: "")
        let engine = KeyboardEngine(memory: memory)
        engine.document = document
        engine.traits.autocapitalizationType = .none

        type("please", into: engine)
        engine.handle(.space)
        type("help", into: engine)
        engine.handle(.space)

        XCTAssertGreaterThanOrEqual(memory.count(previous: "please", next: "help"), 1)
    }

    func testAcceptingPredictionRecordsBigram() {
        let memory = PredictionMemory(table: [:])
        let document = FakeDocument(text: "please ")
        let engine = KeyboardEngine(memory: memory)
        engine.document = document
        engine.traits.autocapitalizationType = .none

        engine.applyPrediction(Prediction(displayText: "help", insertion: "help", isVerbatim: false))

        XCTAssertGreaterThanOrEqual(memory.count(previous: "please", next: "help"), 1)
    }

    private func type(_ text: String, into engine: KeyboardEngine) {
        for character in text {
            engine.handleCharacter(String(character))
        }
    }
}
