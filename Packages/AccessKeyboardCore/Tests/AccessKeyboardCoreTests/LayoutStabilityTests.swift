import XCTest
import UIKit
@testable import AccessKeyboardCore

/// Guards the layout math that keeps the keyboard visually stable: key widths
/// and row structure must not change when only the shift/case state changes, and
/// autocapitalization must not flip the symbol/number keys.
final class LayoutStabilityTests: XCTestCase {
    private let classes: [LayoutClass] = [.compact, .iPad, .iPadPro]
    private let modes: [KeyboardMode] = [.alphabetic, .numeric, .symbols]
    private let letterLayouts: [LetterLayout] = [.qwerty, .abc, .frequency]
    private let shifts: [ShiftState] = [.off, .shifted, .autoShifted, .capsLock]

    // MARK: - Shift never reflows the board (items 6/7)

    func testShiftDoesNotChangeKeyCountsOrWidths() {
        for layoutClass in classes {
            for mode in modes {
                for letterLayout in letterLayouts {
                    let baseline = layout(mode: mode, shift: .off, layoutClass: layoutClass, letterLayout: letterLayout)
                    for shift in shifts where shift != .off {
                        let candidate = layout(mode: mode, shift: shift, layoutClass: layoutClass, letterLayout: letterLayout)
                        let context = "class=\(layoutClass) mode=\(mode) letters=\(letterLayout) shift=\(shift)"

                        XCTAssertEqual(candidate.rows.count, baseline.rows.count, "row count changed: \(context)")

                        for (index, row) in candidate.rows.enumerated() {
                            let base = baseline.rows[index]
                            XCTAssertEqual(
                                row.keys.count, base.keys.count,
                                "row \(index) key count changed: \(context)"
                            )
                            XCTAssertEqual(
                                rowWeight(row), rowWeight(base), accuracy: 0.0001,
                                "row \(index) total width weight changed: \(context)"
                            )
                            XCTAssertEqual(
                                row.keys.map { $0.width }, base.keys.map { $0.width },
                                "row \(index) per-key widths changed: \(context)"
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Autocapitalization must not flip symbols (item 7)

    func testAutoShiftKeepsIPadProNumberRowNumeric() {
        let unshifted = firstRowDisplays(shift: .off)
        let autoShifted = firstRowDisplays(shift: .autoShifted)
        let manualShift = firstRowDisplays(shift: .shifted)
        let capsLock = firstRowDisplays(shift: .capsLock)

        XCTAssertEqual(Array(unshifted.prefix(10)), ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        XCTAssertEqual(autoShifted, unshifted, "autocapitalization must not turn the number row into symbols")
        XCTAssertEqual(Array(manualShift.prefix(10)), ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")"])
        XCTAssertEqual(capsLock, manualShift, "manual shift/caps lock still exposes the top-row symbols")
    }

    private func firstRowDisplays(shift: ShiftState) -> [String] {
        let layout = layout(mode: .alphabetic, shift: shift, layoutClass: .iPadPro, letterLayout: .qwerty)
        return layout.rows[0].keys.compactMap { spec in
            if case .text(let value) = spec.display { return value }
            return nil
        }
    }

    func testAutoShiftStillCapitalizesLetters() {
        for shift in [ShiftState.shifted, .autoShifted, .capsLock] {
            let layout = layout(mode: .alphabetic, shift: shift, layoutClass: .compact, letterLayout: .qwerty)
            XCTAssertEqual(layout.rows[0].keys.first?.action, .character("Q"), "shift=\(shift) should uppercase letters")
        }
        let lower = layout(mode: .alphabetic, shift: .off, layoutClass: .compact, letterLayout: .qwerty)
        XCTAssertEqual(lower.rows[0].keys.first?.action, .character("q"))
    }

    // MARK: - ShiftState semantics

    func testShiftStateSymbolAndCaseFlags() {
        XCTAssertFalse(ShiftState.off.isUppercase)
        XCTAssertTrue(ShiftState.shifted.isUppercase)
        XCTAssertTrue(ShiftState.autoShifted.isUppercase)
        XCTAssertTrue(ShiftState.capsLock.isUppercase)

        XCTAssertFalse(ShiftState.off.affectsSymbolKeys)
        XCTAssertTrue(ShiftState.shifted.affectsSymbolKeys)
        XCTAssertFalse(ShiftState.autoShifted.affectsSymbolKeys, "autocapitalization must not affect symbol keys")
        XCTAssertTrue(ShiftState.capsLock.affectsSymbolKeys)
    }

    // MARK: - Safe-area bottom inset is reserved (item 2)

    func testBottomInsetReservesHomeIndicatorSafeArea() {
        let compactBase = LayoutMetrics.metrics(for: .compact, bounds: CGSize(width: 390, height: 300), safeBottom: 0)
        let compactSafe = LayoutMetrics.metrics(for: .compact, bounds: CGSize(width: 390, height: 300), safeBottom: 34)
        XCTAssertEqual(compactBase.bottomInset, 6)
        XCTAssertEqual(compactSafe.bottomInset, 34)
        XCTAssertEqual(compactSafe.preferredHeight - compactBase.preferredHeight, 28, accuracy: 0.0001)

        let padBase = LayoutMetrics.metrics(for: .iPad, bounds: CGSize(width: 834, height: 1194), safeBottom: 0)
        let padSafe = LayoutMetrics.metrics(for: .iPad, bounds: CGSize(width: 834, height: 1194), safeBottom: 20)
        XCTAssertEqual(padBase.bottomInset, 10)
        XCTAssertEqual(padSafe.bottomInset, 20)
        XCTAssertEqual(padSafe.preferredHeight - padBase.preferredHeight, 10, accuracy: 0.0001)

        let proSafe = LayoutMetrics.metrics(for: .iPadPro, bounds: CGSize(width: 1024, height: 1366), safeBottom: 24)
        XCTAssertEqual(proSafe.bottomInset, 24)
    }

    // MARK: - Helpers

    private func layout(
        mode: KeyboardMode,
        shift: ShiftState,
        layoutClass: LayoutClass,
        letterLayout: LetterLayout
    ) -> KeyboardLayout {
        LayoutFactory.layout(
            mode: mode,
            shift: shift,
            layoutClass: layoutClass,
            needsInputModeSwitchKey: true,
            returnKeyType: .default,
            letterLayout: letterLayout
        )
    }

    private func rowWeight(_ row: KeyboardRow) -> CGFloat {
        row.keys.reduce(0) { $0 + weight(of: $1.width) }
    }

    private func weight(of width: KeyWidth) -> CGFloat {
        switch width {
        case .unit(let value): return value
        case .flexible: return 4.5
        }
    }
}
