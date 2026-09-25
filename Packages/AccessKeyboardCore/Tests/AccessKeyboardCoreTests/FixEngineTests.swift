import XCTest
@testable import AccessKeyboardCore

@MainActor
final class FixEngineTests: XCTestCase {
    func testFixReplacesTheWholeField() async {
        let (engine, document) = makeEngine(text: "I recieve the mesage")
        engine.fixClient = MockFixClient { text in
            XCTAssertEqual(text, "I recieve the mesage")
            return "I receive the message"
        }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "I receive the message")
        XCTAssertEqual(engine.fixStatus, .idle)
        XCTAssertEqual(engine.fixNotice, .none)
    }

    func testFixUndoRestoresTheOriginal() async {
        let (engine, document) = makeEngine(text: "teh schol")
        engine.fixClient = MockFixClient { _ in "the school" }

        engine.requestFix()
        await waitUntilIdle(engine)
        engine.handle(.undo)

        XCTAssertEqual(document.text, "teh schol")
    }

    func testFixSkipsSecureFields() async {
        let (engine, document) = makeEngine(text: "secret")
        engine.traits.isSecureTextEntry = true
        engine.fixClient = MockFixClient { _ in
            XCTFail("secure fields must not be sent")
            return "nope"
        }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "secret")
        XCTAssertEqual(engine.fixStatus, .idle)
        XCTAssertEqual(engine.fixNotice, .secureField)
    }

    func testFixRequiresFullAccessBeforeItSends() async {
        let (engine, document) = makeEngine(text: "teh", network: false)
        engine.fixClient = MockFixClient { _ in
            XCTFail("Fix must not send without Full Access")
            return "the"
        }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "teh")
        XCTAssertEqual(engine.fixStatus, .idle)
        XCTAssertEqual(engine.fixNotice, .fullAccess)
        XCTAssertFalse(engine.fixNotice.message.isEmpty)
    }

    func testTypingStillWorksWhenFixCannotRun() {
        let (engine, document) = makeEngine(text: "", network: false)
        engine.sharedPreferencesAvailable = false
        engine.fixClient = MockFixClient { _ in
            XCTFail("must not send")
            return ""
        }

        engine.handleCharacter("a")
        engine.requestFix()
        XCTAssertEqual(engine.fixNotice, .fullAccess)
        engine.handleCharacter("b")

        XCTAssertEqual(document.text, "ab")
        XCTAssertEqual(engine.fixNotice, .none)
        XCTAssertEqual(engine.fixStatus, .idle)
    }

    func testFixNetworkFailureLeavesTheFieldAndShowsAHint() async {
        let (engine, document) = makeEngine(text: "teh")
        engine.fixClient = MockFixClient { _ in
            throw FixError.requestFailed
        }

        engine.requestFix()
        await waitUntilIdle(engine)

        XCTAssertEqual(document.text, "teh")
        XCTAssertEqual(engine.fixStatus, .failed)
        XCTAssertEqual(engine.fixNotice, .offline)
        engine.handleCharacter("!")
        XCTAssertEqual(engine.fixNotice, .none)
        XCTAssertTrue(document.text.hasSuffix("!"))
    }

    func testFixAsksBeforeTheFirstSendAndCanBeDeclined() async {
        let document = FakeDocument(text: "teh")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        engine.traits.autocapitalizationType = .none
        engine.fixConsentRequired = true
        engine.subscriptionIsActive = { true }
        let box = ConsentBox()
        engine.fixConsentIsGranted = { box.granted }
        engine.recordFixConsent = { box.granted = $0 }
        engine.fixClient = MockFixClient { _ in
            box.sent += 1
            return "the"
        }

        engine.requestFix()
        XCTAssertEqual(engine.fixNotice, .consent)
        XCTAssertEqual(box.sent, 0)
        XCTAssertFalse(engine.fixNotice.message.isEmpty)
        XCTAssertEqual(document.text, "teh")

        engine.declineFixConsent()
        XCTAssertEqual(engine.fixNotice, .none)
        XCTAssertFalse(box.granted)
        XCTAssertEqual(box.sent, 0)

        engine.requestFix()
        XCTAssertEqual(engine.fixNotice, .consent)
        engine.allowFixConsentAndSend()
        await waitUntilIdle(engine)
        XCTAssertTrue(box.granted)
        XCTAssertEqual(box.sent, 1)
        XCTAssertEqual(document.text, "the")
        XCTAssertEqual(engine.fixNotice, .none)

        engine.requestFix()
        await waitUntilIdle(engine)
        XCTAssertEqual(box.sent, 2)
    }

    func testRevokingConsentAsksAgain() async {
        let document = FakeDocument(text: "teh")
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = true
        engine.traits.autocapitalizationType = .none
        engine.fixConsentRequired = true
        engine.subscriptionIsActive = { true }
        let box = ConsentBox()
        box.granted = true
        engine.fixConsentIsGranted = { box.granted }
        engine.recordFixConsent = { box.granted = $0 }
        engine.fixClient = MockFixClient { _ in
            box.sent += 1
            return "the"
        }

        engine.requestFix()
        await waitUntilIdle(engine)
        XCTAssertEqual(box.sent, 1)

        box.granted = false
        engine.requestFix()
        XCTAssertEqual(engine.fixNotice, .consent)
        XCTAssertEqual(box.sent, 1)
        XCTAssertEqual(document.text, "the")
    }

    func testFixRequiresASubscriptionBeforeItAsksForConsent() async {
        let (engine, document) = makeEngine(text: "teh")
        engine.fixConsentRequired = true
        engine.fixRequiresSubscription = true
        engine.sharedPreferencesAvailable = true
        engine.subscriptionIsActive = { false }
        engine.fixConsentIsGranted = { false }
        var sent = 0
        engine.fixClient = MockFixClient { _ in
            sent += 1
            return "the"
        }

        engine.requestFix()
        XCTAssertEqual(engine.fixNotice, .subscribe)
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(document.text, "teh")
        XCTAssertFalse(engine.fixNotice.message.isEmpty)

        engine.subscriptionIsActive = { true }
        engine.requestFix()
        XCTAssertEqual(engine.fixNotice, .consent)
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(document.text, "teh")
    }

    func testUnreadableEntitlementAsksForFullAccess() {
        let (engine, document) = makeEngine(text: "teh", network: false)
        engine.sharedPreferencesAvailable = false
        engine.subscriptionIsActive = {
            XCTFail("the extension must not treat a hidden App Group as a subscription decision")
            return false
        }
        engine.fixClient = MockFixClient { _ in
            XCTFail("must not send")
            return "the"
        }

        engine.requestFix()
        XCTAssertEqual(engine.fixNotice, .fullAccess)
        XCTAssertEqual(document.text, "teh")
    }

    func testWithoutSharedPreferencesTheBoardStaysQWERTY() {
        let previous = KeyboardPreferences.letterLayout
        defer { KeyboardPreferences.letterLayout = previous }
        KeyboardPreferences.letterLayout = .abc
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.sharedPreferencesAvailable = false
        let layout = engine.layout(for: CGSize(width: 390, height: 400), idiom: .phone)
        XCTAssertEqual(layout.letterString(inRow: 0), "qwertyuiop")
    }

    private func makeEngine(text: String, network: Bool = true) -> (KeyboardEngine, FakeDocument) {
        let document = FakeDocument(text: text)
        let engine = KeyboardEngine(memory: PredictionMemory(table: [:]))
        engine.document = document
        engine.networkAllowed = network
        engine.traits.autocapitalizationType = .none
        engine.fixConsentRequired = false
        engine.fixRequiresSubscription = true
        engine.sharedPreferencesAvailable = true
        engine.subscriptionIsActive = { true }
        return (engine, document)
    }

    private func waitUntilIdle(_ engine: KeyboardEngine) async {
        let deadline = Date().addingTimeInterval(1)
        while engine.fixStatus == .running, Date() < deadline {
            await Task.yield()
        }
    }
}

private final class ConsentBox: @unchecked Sendable {
    var granted = false
    var sent = 0
}

private struct MockFixClient: FixClient {
    var handler: @Sendable (String) async throws -> String

    func fix(_ text: String) async throws -> String {
        try await handler(text)
    }
}
