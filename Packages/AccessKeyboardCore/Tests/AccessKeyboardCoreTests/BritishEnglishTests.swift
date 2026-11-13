import XCTest
@testable import AccessKeyboardCore

final class BritishEnglishTests: XCTestCase {
    func testUnambiguousSpellings() {
        XCTAssertEqual(BritishEnglish.prefer("color"), "colour")
        XCTAssertEqual(BritishEnglish.prefer("colors"), "colours")
        XCTAssertEqual(BritishEnglish.prefer("mom"), "mum")
        XCTAssertEqual(BritishEnglish.prefer("gray"), "grey")
        XCTAssertEqual(BritishEnglish.prefer("center"), "centre")
        XCTAssertEqual(BritishEnglish.prefer("centered"), "centred")
        XCTAssertEqual(BritishEnglish.prefer("centering"), "centring")
        XCTAssertEqual(BritishEnglish.prefer("organize"), "organise")
        XCTAssertEqual(BritishEnglish.prefer("organized"), "organised")
        XCTAssertEqual(BritishEnglish.prefer("organization"), "organisation")
        XCTAssertEqual(BritishEnglish.prefer("traveling"), "travelling")
        XCTAssertEqual(BritishEnglish.prefer("favorite"), "favourite")
        XCTAssertEqual(BritishEnglish.prefer("neighborhood"), "neighbourhood")
    }

    func testWordsThatAreNotSpellingVariantsStay() {
        for word in ["door", "floor", "error", "doctor", "actor", "size", "prize", "program", "practice", "license", "check", "the", "and", "honorary"] {
            XCTAssertEqual(BritishEnglish.prefer(word), word, word)
        }
    }

    func testFrequencyListUsesUKSpellings() {
        XCTAssertTrue(PredictionLexicon.contains("colour"))
        XCTAssertTrue(PredictionLexicon.contains("mum"))
        XCTAssertTrue(PredictionLexicon.contains("centre"))
        XCTAssertTrue(PredictionLexicon.contains("grey"))
        XCTAssertFalse(PredictionLexicon.contains("color"))
        XCTAssertFalse(PredictionLexicon.contains("mom"))
        XCTAssertFalse(PredictionLexicon.contains("center"))
    }

    func testPrefixOffersColourNotColor() {
        let words = PredictionProvider.suggestions(prefix: "colo", before: "colo").map { $0.insertion.lowercased() }
        XCTAssertTrue(words.contains("colour"), "\(words)")
        XCTAssertFalse(words.contains("color"), "\(words)")
    }

    func testCheckerLanguagePrefersEnglishUK() {
        XCTAssertEqual(
            PredictionLexicon.preferredCheckerLanguage(available: ["en_US", "en_GB", "fr_FR"], devicePreferred: ["en-US"]),
            "en_GB"
        )
        XCTAssertEqual(
            PredictionLexicon.preferredCheckerLanguage(available: ["en-GB"], devicePreferred: ["en-US"]),
            "en-GB"
        )
        XCTAssertEqual(
            PredictionLexicon.preferredCheckerLanguage(available: ["en_US"], devicePreferred: ["en-US"]),
            "en_US"
        )
        XCTAssertEqual(
            PredictionLexicon.preferredCheckerLanguage(available: [], devicePreferred: []),
            "en_GB"
        )
    }
}
