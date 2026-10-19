import XCTest
import UIKit
@testable import AccessKeyboardCore

final class KeyLetterSizingTests: XCTestCase {
    func testWideAndNarrowLettersShareOneSize() {
        let intended: CGFloat = 24
        let font = KeyLetterSizingFont(size: intended)
        let widest = KeyLetterSizing.wideLetters
            .map { KeyLetterSizing.letterWidth($0, font: font) }
            .max() ?? 0
        // Narrower than W, so a per-letter shrink would make W smaller than I.
        let available = widest * 0.8
        let size = KeyLetterSizing.uniformSize(intended: intended, availableWidth: available)

        XCTAssertLessThan(size, intended)
        let fitted = KeyLetterSizingFont(size: size)
        let fittedW = KeyLetterSizing.letterWidth("W", font: fitted)
        let fittedI = KeyLetterSizing.letterWidth("I", font: fitted)
        XCTAssertLessThanOrEqual(fittedW, available + 0.5)
        XCTAssertLessThan(fittedI, fittedW)
        XCTAssertEqual(
            KeyLetterSizing.uniformSize(intended: intended, availableWidth: available),
            size,
            accuracy: 0.01
        )
    }

    func testLettersKeepTheIntendedSizeWhenTheyAlreadyFit() {
        let intended: CGFloat = 24
        let font = KeyLetterSizingFont(size: intended)
        let widest = KeyLetterSizing.letterWidth("W", font: font)
        let size = KeyLetterSizing.uniformSize(intended: intended, availableWidth: widest + 8)
        XCTAssertEqual(size, intended, accuracy: 0.01)
    }

    private func KeyLetterSizingFont(size: CGFloat) -> UIFont {
        LiteracyFont.uiFont(ofSize: size) ?? .systemFont(ofSize: size, weight: .light)
    }
}
