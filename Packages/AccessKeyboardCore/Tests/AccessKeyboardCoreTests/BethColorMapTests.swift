import XCTest
import UIKit
@testable import AccessKeyboardCore

final class BethColorMapTests: XCTestCase {
    func testEveryLetterHasAFill() {
        let missing = "abcdefghijklmnopqrstuvwxyz".filter { BethColorMap.fill(for: String($0)) == nil }
        XCTAssertTrue(missing.isEmpty, "missing fills for \(missing)")
    }

    func testCaseAndDiacriticFoldToTheSameFill() {
        let lower = color("e")
        XCTAssertEqual(lower, color("E"))
        XCTAssertEqual(lower, color("é"))
        XCTAssertEqual(lower, color("É"))
    }

    func testNonLettersHaveNoFill() {
        for value in ["1", ";", ".", " ", "", "@", "é1"] {
            if value == "é1" {
                XCTAssertNotNil(BethColorMap.fill(for: value), "leading letter should still map")
                continue
            }
            XCTAssertNil(BethColorMap.fill(for: value), value)
        }
    }

    func testDarkKeysUseLightText() {
        XCTAssertEqual(foreground("z"), .white)
        XCTAssertEqual(foreground("f"), .white)
        XCTAssertEqual(foreground("w"), .white)
    }

    func testLightKeysUseDarkText() {
        XCTAssertEqual(foreground("a"), .black)
        XCTAssertEqual(foreground("s"), .black)
        XCTAssertEqual(foreground("y"), .black)
    }

    func testPressedFillIsDarker() {
        let rest = color("a")
        let pressed = BethColorMap.pressedFill(for: rest)
        XCTAssertLessThan(luminance(pressed), luminance(rest))
    }

    func testAppearancePaintsLettersFromTheMap() {
        var appearance = KeyboardAppearance.system(for: .light)
        appearance.usesBethLetterColors = true
        let fill = appearance.fill(for: .letter, character: "A", pressed: false, highlightedModifier: false)
        XCTAssertEqual(fill, color("a"))
        XCTAssertEqual(
            appearance.foreground(for: .letter, character: "z"),
            .white
        )
    }

    func testAppearanceLeavesPunctuationOnSystemChrome() {
        var appearance = KeyboardAppearance.system(for: .light)
        appearance.usesBethLetterColors = true
        let fill = appearance.fill(for: .letter, character: ";", pressed: false, highlightedModifier: false)
        XCTAssertEqual(fill, appearance.letterFill)
    }

    private func color(_ letter: String) -> UIColor {
        guard let fill = BethColorMap.fill(for: letter) else {
            XCTFail("expected fill for \(letter)")
            return .clear
        }
        return fill
    }

    private func foreground(_ letter: String) -> UIColor {
        BethColorMap.foreground(for: color(letter))
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

private func XCTAssertEqual(_ lhs: UIColor, _ rhs: UIColor, file: StaticString = #filePath, line: UInt = #line) {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    lhs.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    rhs.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    XCTAssertEqual(r1, r2, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(g1, g2, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(b1, b2, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(a1, a2, accuracy: 0.001, file: file, line: line)
}
