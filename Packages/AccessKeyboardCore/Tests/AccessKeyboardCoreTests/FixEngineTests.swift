import XCTest
@testable import AccessKeyboardCore

@MainActor
final class FixEngineTests: XCTestCase {
    func testFixReplacesTheWholeField() async {
        let document = FakeDocument(text: "I recieve the mesage")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        engine.fixClient = MockFixClient { text in
            XCTAssertEqual(text, "I recieve the mesage")
            return "I receive the message"
        }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "I receive the message")
        XCTAssertEqual(engine.fixStatus, .idle)
    }

    func testFixUndoRestoresTheOriginal() async {
        let document = FakeDocument(text: "teh schol")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        engine.fixClient = MockFixClient { _ in "the school" }

        engine.requestFix()
        await waitUntilIdle(engine)
        engine.handle(.undo)

        XCTAssertEqual(document.text, "teh schol")
    }

    func testFixSkipsSecureFields() async {
        let document = FakeDocument(text: "secret")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        engine.traits.isSecureTextEntry = true
        engine.fixClient = MockFixClient { _ in
            XCTFail("secure fields must not be sent")
            return "nope"
        }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "secret")
        XCTAssertEqual(engine.fixStatus, .failed)
    }

    func testFixRequiresNetwork() async {
        let document = FakeDocument(text: "teh")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = false
        engine.fixClient = MockFixClient { _ in "the" }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "teh")
        XCTAssertEqual(engine.fixStatus, .failed)
    }

    /// Apple Notes: the first line is the title. Fix in the keyboard extension
    /// must only touch the body paragraph, never delete back into the title.
    func testProxyFixOnlyReplacesTheCurrentParagraph() async {
        let document = FakeDocument(
            text: "Shopping\nI recieve the mesage",
            exposesEntireText: false
        )
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        engine.fixClient = MockFixClient { text in
            XCTAssertEqual(text, "I recieve the mesage")
            return "I receive the message"
        }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "Shopping\nI receive the message")
        XCTAssertEqual(engine.fixStatus, .idle)
    }

    func testProxyFixKeepsLaterParagraphsAndTrailingSpace() async {
        let document = FakeDocument(
            text: "Title\nteh cat \nNext line",
            cursor: "Title\nteh cat ".count,
            exposesEntireText: false
        )
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        // The proxy trims the reply, so the trailing space comes back missing.
        engine.fixClient = MockFixClient { _ in "the cat" }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "Title\nthe cat \nNext line")
    }

    func testProxyFixUndoRestoresOnlyTheParagraph() async {
        let document = FakeDocument(text: "Title\nteh schol", exposesEntireText: false)
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        engine.fixClient = MockFixClient { _ in "the school" }

        engine.requestFix()
        await waitUntilIdle(engine)
        engine.handle(.undo)

        XCTAssertEqual(document.text, "Title\nteh schol")
    }

    private func waitUntilIdle(_ engine: KeyboardEngine) async {
        let deadline = Date().addingTimeInterval(1)
        while engine.fixStatus == .running, Date() < deadline {
            await Task.yield()
        }
    }
}

private struct MockFixClient: FixClient {
    var handler: @Sendable (String) async throws -> String

    func fix(_ text: String) async throws -> String {
        try await handler(text)
    }
}
