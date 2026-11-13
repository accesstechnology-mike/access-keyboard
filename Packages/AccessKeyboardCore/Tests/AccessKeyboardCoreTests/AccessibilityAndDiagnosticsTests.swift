import XCTest
@testable import AccessKeyboardCore

final class AccessibilityAndDiagnosticsTests: XCTestCase {
    func testVoiceOverActivateInsertsTheLetterAndOffersAccents() {
        let button = makeButton(spec: .letter("a"))
        var released: String?
        button.onRelease = { spec in
            if case .character(let text) = spec.action {
                released = text
            }
        }
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertEqual(released, "a")
        XCTAssertEqual(button.accessibilityLabel, "a")
        let names = button.accessibilityCustomActions?.map(\.name) ?? []
        XCTAssertTrue(names.contains("à"), "accents should be VoiceOver actions, got \(names)")
    }

    func testVoiceOverActivateDeletesOnce() {
        let button = makeButton(spec: KeySpec(action: .backspace, display: .symbol("delete.left"), style: .modifier))
        var presses = 0
        var releases = 0
        button.onPress = { _ in presses += 1 }
        button.onRelease = { _ in releases += 1 }
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 0)
        XCTAssertEqual(button.accessibilityLabel, "Delete")
        XCTAssertNil(button.accessibilityCustomActions)
    }

    func testResidentMemoryReadsWithoutCrashing() {
        XCTAssertGreaterThanOrEqual(ResidentMemory.megabytes, -1)
        XCTAssertGreaterThan(ResidentMemory.keyboardWarningMegabytes, 0)
    }

    private func makeButton(spec: KeySpec) -> KeyButton {
        KeyButton(
            spec: spec,
            appearance: .system(for: .light),
            metrics: LayoutMetrics.metrics(for: .compact, bounds: CGSize(width: 390, height: 300), safeBottom: 0),
            shift: .off,
            isModifierHighlighted: false
        )
    }
}
