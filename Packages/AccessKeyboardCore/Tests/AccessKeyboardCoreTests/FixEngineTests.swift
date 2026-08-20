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

    func testFixFailsOnEmptyField() async {
        let document = FakeDocument(text: "   ")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        engine.fixClient = MockFixClient { _ in
            XCTFail("empty fields must not be sent")
            return "nope"
        }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "   ")
        XCTAssertEqual(engine.fixStatus, .failed)
    }

    func testFixReplacesThroughDocumentProxy() async {
        let document = ProxyLikeDocument(text: "I recieve the mesage")
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

    private func waitUntilIdle(_ engine: KeyboardEngine) async {
        let deadline = Date().addingTimeInterval(2)
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

@MainActor
private final class FakeDocument: KeyboardDocument {
    var text: String
    var cursor: Int

    init(text: String) {
        self.text = text
        self.cursor = text.count
    }

    func insertText(_ text: String) {
        let index = self.text.index(self.text.startIndex, offsetBy: cursor)
        self.text.insert(contentsOf: text, at: index)
        cursor += text.count
    }

    func deleteBackward() {
        guard cursor > 0 else { return }
        let index = text.index(text.startIndex, offsetBy: cursor - 1)
        text.remove(at: index)
        cursor -= 1
    }

    var documentContextBeforeInput: String? { String(text.prefix(cursor)) }
    var documentContextAfterInput: String? { String(text.dropFirst(cursor)) }
    var selectedText: String? { nil }
    var entireText: String? { text }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursor = min(max(0, cursor + offset), text.count)
    }

    func replaceEntireText(_ text: String) -> Bool {
        self.text = text
        cursor = text.count
        return true
    }
}

@MainActor
private final class ProxyLikeDocument: KeyboardDocument {
    var text: String
    var cursor: Int

    init(text: String) {
        self.text = text
        self.cursor = text.count
    }

    func insertText(_ text: String) {
        let index = self.text.index(self.text.startIndex, offsetBy: cursor)
        self.text.insert(contentsOf: text, at: index)
        cursor += text.count
    }

    func deleteBackward() {
        guard cursor > 0 else { return }
        let index = text.index(text.startIndex, offsetBy: cursor - 1)
        text.remove(at: index)
        cursor -= 1
    }

    var documentContextBeforeInput: String? { String(text.prefix(cursor)) }
    var documentContextAfterInput: String? { String(text.dropFirst(cursor)) }
    var selectedText: String? { nil }
    var entireText: String? { nil }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursor = min(max(0, cursor + offset), text.count)
    }

    func replaceEntireText(_ text: String) -> Bool {
        false
    }
}
