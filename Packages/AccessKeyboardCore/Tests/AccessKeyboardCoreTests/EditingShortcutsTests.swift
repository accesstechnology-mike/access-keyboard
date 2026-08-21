import XCTest
@testable import AccessKeyboardCore

final class EditingShortcutsTests: XCTestCase {
    func testDoubleSpaceConvertsAfterAWord() {
        XCTAssertTrue(EditingShortcuts.shouldConvertDoubleSpace("Hello "))
        XCTAssertTrue(EditingShortcuts.shouldConvertDoubleSpace("Hello) "))
        XCTAssertFalse(EditingShortcuts.shouldConvertDoubleSpace("Hello"))
        XCTAssertFalse(EditingShortcuts.shouldConvertDoubleSpace(" "))
        XCTAssertFalse(EditingShortcuts.shouldConvertDoubleSpace("Hello. "))
        XCTAssertFalse(EditingShortcuts.shouldConvertDoubleSpace("Hello! "))
        XCTAssertFalse(EditingShortcuts.shouldConvertDoubleSpace("Hello, "))
        XCTAssertFalse(EditingShortcuts.shouldConvertDoubleSpace("Hello  "))
        XCTAssertFalse(EditingShortcuts.shouldConvertDoubleSpace(""))
    }

    func testWordDeleteLength() {
        XCTAssertEqual(EditingShortcuts.wordDeleteLength(in: "hello world"), 5)
        XCTAssertEqual(EditingShortcuts.wordDeleteLength(in: "hello world "), 6)
        XCTAssertEqual(EditingShortcuts.wordDeleteLength(in: "hello "), 6)
        XCTAssertEqual(EditingShortcuts.wordDeleteLength(in: "hello\n"), 1)
        XCTAssertEqual(EditingShortcuts.wordDeleteLength(in: "hello\nworld"), 5)
        XCTAssertEqual(EditingShortcuts.wordDeleteLength(in: ""), 0)
        XCTAssertEqual(EditingShortcuts.wordDeleteLength(in: "   "), 3)
    }

    func testCursorMovesByCharacterAndLine() {
        XCTAssertEqual(
            EditingShortcuts.cursorOffset(before: "hello", after: " world", horizontal: -1, vertical: 0),
            -1
        )
        XCTAssertEqual(
            EditingShortcuts.cursorOffset(before: "hello", after: " world", horizontal: 2, vertical: 0),
            2
        )
        XCTAssertEqual(
            EditingShortcuts.cursorOffset(before: "he", after: "llo\nworld", horizontal: 0, vertical: 1),
            6
        )
        XCTAssertEqual(
            EditingShortcuts.cursorOffset(before: "hello\nwo", after: "rld", horizontal: 0, vertical: -1),
            -6
        )
        XCTAssertEqual(
            EditingShortcuts.cursorOffset(before: "hi", after: "", horizontal: 4, vertical: 0),
            0
        )
    }
}

@MainActor
final class KeyboardEditingTests: XCTestCase {
    func testDoubleSpaceInsertsAPeriod() {
        let document = FakeDocument(text: "Hello")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.traits.autocapitalizationType = .none

        engine.handle(.space)
        XCTAssertEqual(document.text, "Hello ")
        engine.handle(.space)
        XCTAssertEqual(document.text, "Hello. ")
    }

    func testDoubleSpaceDoesNotConvertAfterPunctuation() {
        let document = FakeDocument(text: "Hello.")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.traits.autocapitalizationType = .none

        engine.handle(.space)
        engine.handle(.space)
        XCTAssertEqual(document.text, "Hello.  ")
    }

    func testHoldDeleteRemovesAWord() {
        let document = FakeDocument(text: "hello world")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.traits.autocapitalizationType = .none

        engine.continueBackspace(byWord: true)
        XCTAssertEqual(document.text, "hello ")
        engine.continueBackspace(byWord: true)
        XCTAssertEqual(document.text, "")
    }

    func testTwoFingerCursorMovement() {
        let document = FakeDocument(text: "hello\nworld", cursor: 11)
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.traits.autocapitalizationType = .none

        engine.moveCursor(horizontal: -1, vertical: 0)
        XCTAssertEqual(document.cursor, 10)
        engine.moveCursor(horizontal: 0, vertical: -1)
        XCTAssertEqual(String(document.text.prefix(document.cursor)), "hell")
    }
}
