import XCTest
import UIKit
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

    func testURLFieldSuppressesAutocapitalization() {
        for keyboardType in [UIKeyboardType.URL, .webSearch, .emailAddress] {
            let document = FakeDocument(text: "")
            let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
            engine.document = document
            engine.traits = KeyboardTraits(
                autocapitalizationType: .sentences,
                keyboardType: keyboardType
            )
            engine.documentDidChange()
            XCTAssertEqual(engine.shift, .off, "URL field should not auto-shift at the start (\(keyboardType))")

            engine.handle(.character("x"))
            XCTAssertEqual(engine.shift, .off, "URL field should not auto-shift while typing (\(keyboardType))")

            engine.handle(.character("."))
            XCTAssertEqual(engine.shift, .off, "no capital after a period inside a URL (\(keyboardType))")
        }
    }

    func testURLTextContentTypeSuppressesAutocapitalization() {
        let document = FakeDocument(text: "")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.traits = KeyboardTraits(
            autocapitalizationType: .sentences,
            keyboardType: .default,
            textContentType: .URL
        )
        engine.documentDidChange()
        XCTAssertEqual(engine.shift, .off, "a .URL content-type field should not auto-shift")
    }

    func testSentenceFieldStillAutocapitalizes() {
        let document = FakeDocument(text: "")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.traits = KeyboardTraits(
            autocapitalizationType: .sentences,
            keyboardType: .default
        )
        engine.documentDidChange()
        XCTAssertEqual(engine.shift, .autoShifted, "a normal sentence field still capitalizes the first letter")
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
