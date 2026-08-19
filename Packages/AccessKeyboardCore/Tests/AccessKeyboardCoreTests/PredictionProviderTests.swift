import XCTest
@testable import AccessKeyboardCore

final class PredictionProviderTests: XCTestCase {
    func testPleaseHeIncludesHelp() {
        let words = insertions(prefix: "he", before: "Please he")
        print("Please he -> \(words)")
        XCTAssertTrue(words.contains("help"), "expected help in \(words)")
    }

    func testHelIncludesHelp() {
        let words = insertions(prefix: "hel", before: "Please hel")
        print("Please hel -> \(words)")
        XCTAssertTrue(words.contains("help"), "expected help in \(words)")
        XCTAssertFalse(words.contains("hey"), "hey should not crowd out help for hel: \(words)")
    }

    func testHeIsNotHeyFirst() {
        let words = insertions(prefix: "he", before: "Please he")
        print("Please he first: \(words.first ?? "nil")")
        XCTAssertNotEqual(words.first, "hey")
        XCTAssertFalse(words.contains("he's") && !words.contains("help"), "got \(words)")
    }

    func testEmptyPrefixPredictsNextWord() {
        let words = insertions(prefix: "", before: "Please ")
        print("Please _ -> \(words)")
        XCTAssertEqual(words.count, 3, "next-word bar should not be blank")
    }

    func testLearnedBigramRanksFirst() {
        let memory = PredictionMemory(table: [:])
        memory.record(previous: "please", next: "help")
        let words = PredictionProvider.suggestions(prefix: "", before: "Please ", memory: memory)
            .map { $0.insertion.lowercased() }
        print("learned Please _ -> \(words)")
        XCTAssertEqual(words.first, "help")
    }

    private func insertions(prefix: String, before: String) -> [String] {
        PredictionProvider.suggestions(prefix: prefix, before: before).map { $0.insertion.lowercased() }
    }
}
