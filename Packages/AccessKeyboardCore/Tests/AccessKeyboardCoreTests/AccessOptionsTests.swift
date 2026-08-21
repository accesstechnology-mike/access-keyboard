import XCTest
import UIKit
@testable import AccessKeyboardCore

final class AccessOptionsTests: XCTestCase {
    private var snapshot: PreferenceSnapshot!

    override func setUp() {
        super.setUp()
        snapshot = PreferenceSnapshot.capture()
    }

    override func tearDown() {
        snapshot.restore()
        snapshot = nil
        super.tearDown()
    }

    func testABCLetterOrderOnCompactBoard() {
        let layout = compact(.abc)
        XCTAssertEqual(layout.letterString(inRow: 0), "abcdefghij")
        XCTAssertEqual(layout.letterString(inRow: 1), "klmnopqrs")
        XCTAssertEqual(layout.letterString(inRow: 2), "tuvwxyz")
    }

    func testABCRightHandMirrorsRows() {
        let layout = compact(.abc, handedness: .right)
        XCTAssertEqual(layout.letterString(inRow: 0), "jihgfedcba")
        XCTAssertEqual(layout.letterString(inRow: 1), "srqponmlk")
        XCTAssertEqual(layout.letterString(inRow: 2), "zyxwvut")
    }

    func testQWERTYDoesNotMirrorForRightHand() {
        let layout = compact(.qwerty, handedness: .right)
        XCTAssertEqual(layout.letterString(inRow: 0), "qwertyuiop")
        XCTAssertEqual(layout.letterString(inRow: 1), "asdfghjkl")
        XCTAssertEqual(layout.letterString(inRow: 2), "zxcvbnm")
    }

    func testEARDUFrequencyOrderAndRightHandMirror() {
        XCTAssertEqual(
            LetterMaps.frequencyRows(handedness: .standard),
            ["eardu", "toilgv", "nsfyx.", "hcpkj,", "mbwqz?"]
        )
        XCTAssertEqual(
            LetterMaps.frequencyRows(handedness: .right),
            ["udrae", "vgliot", ".xyfsn", ",jkpch", "?zqwbm"]
        )

        let layout = compact(.frequency)
        XCTAssertEqual(layout.letterString(inRow: 0), "eardu")
        XCTAssertEqual(layout.letterString(inRow: 1), "toilgv")
        XCTAssertEqual(layout.letterString(inRow: 2), "nsfyx.")
        XCTAssertEqual(layout.letterString(inRow: 3), "hcpkj,")
        XCTAssertEqual(layout.letterString(inRow: 4), "mbwqz?")

        let mirrored = compact(.frequency, handedness: .right)
        XCTAssertEqual(mirrored.letterString(inRow: 0), "udrae")
        XCTAssertEqual(mirrored.letterString(inRow: 4), "?zqwbm")
    }

    func testQWERTYHandSplitMembership() {
        XCTAssertEqual(HandSplit.side(for: "e"), .left)
        XCTAssertEqual(HandSplit.side(for: "E"), .left)
        XCTAssertEqual(HandSplit.side(for: "i"), .right)
        XCTAssertEqual(HandSplit.side(for: "5"), .left)
        XCTAssertEqual(HandSplit.side(for: "6"), .right)
        XCTAssertEqual(HandSplit.side(for: ","), .right)
    }

    func testVowelAndConsonantClassification() {
        XCTAssertEqual(KeyGlyphClass.classify("a"), .vowel)
        XCTAssertEqual(KeyGlyphClass.classify("E"), .vowel)
        XCTAssertEqual(KeyGlyphClass.classify("é"), .vowel)
        XCTAssertEqual(KeyGlyphClass.classify("b"), .consonant)
        XCTAssertEqual(KeyGlyphClass.classify("y"), .consonant)
        XCTAssertEqual(KeyGlyphClass.classify("1"), .number)
        XCTAssertEqual(KeyGlyphClass.classify("."), .punctuation)
        XCTAssertEqual(KeyGlyphClass.classify(" "), .other)
    }

    func testHighContrastThemesWinOverBethAndVowels() {
        let appearance = KeyboardAppearance.resolved(
            contrast: .blackOnWhite,
            colouring: .vowels,
            handedness: .standard,
            usesLiteracyFont: false,
            style: .light
        )
        XCTAssertEqual(appearance.keyColouring, .none)
        XCTAssertFalse(appearance.usesBethLetterColors)
        XCTAssertEqual(
            appearance.fill(for: .letter, character: "a", pressed: false, highlightedModifier: false),
            appearance.letterFill
        )
        XCTAssertEqual(
            appearance.foreground(for: .letter, character: "a"),
            appearance.textColor
        )

        let bethOverridden = KeyboardAppearance.resolved(
            contrast: .yellowOnBlack,
            colouring: .beth,
            handedness: .standard,
            usesLiteracyFont: false,
            style: .dark
        )
        XCTAssertFalse(bethOverridden.usesBethLetterColors)
        XCTAssertEqual(
            bethOverridden.fill(for: .letter, character: "a", pressed: false, highlightedModifier: false),
            bethOverridden.letterFill
        )
        XCTAssertEqual(bethOverridden.textColor, AccessColouring.highContrastYellow)
    }

    func testVowelColouringPaintsLettersAndLeavesModifiers() {
        let appearance = KeyboardAppearance.resolved(
            contrast: .system,
            colouring: .vowels,
            handedness: .standard,
            usesLiteracyFont: false,
            style: .light
        )
        XCTAssertEqual(
            appearance.fill(for: .letter, character: "a", pressed: false, highlightedModifier: false),
            AccessColouring.vowelFill
        )
        XCTAssertEqual(
            appearance.fill(for: .letter, character: "t", pressed: false, highlightedModifier: false),
            AccessColouring.consonantFill
        )
        XCTAssertEqual(
            appearance.fill(for: .letter, character: "4", pressed: false, highlightedModifier: false),
            AccessColouring.numberFill
        )
        XCTAssertEqual(
            appearance.fill(for: .modifier, character: nil, pressed: false, highlightedModifier: false),
            appearance.modifierFill
        )
    }

    func testHandColouringDimsTheUnusedSide() {
        let left = KeyboardAppearance.resolved(
            contrast: .system,
            colouring: .hands,
            handedness: .left,
            usesLiteracyFont: false,
            style: .light
        )
        XCTAssertEqual(
            left.fill(for: .letter, character: "e", pressed: false, highlightedModifier: false),
            AccessColouring.leftHandFill
        )
        XCTAssertEqual(
            left.fill(for: .letter, character: "i", pressed: false, highlightedModifier: false),
            AccessColouring.dimmed(AccessColouring.rightHandFill)
        )
        XCTAssertEqual(left.foreground(for: .letter, character: "e"), .white)
    }

    func testPreferenceKeysRoundTripThroughTheAppGroupSuite() {
        KeyboardPreferences.letterLayout = .frequency
        KeyboardPreferences.handedness = .right
        KeyboardPreferences.keyColouring = .vowels
        KeyboardPreferences.contrastTheme = .whiteOnBlack
        KeyboardPreferences.literacyFontEnabled = true

        XCTAssertEqual(KeyboardPreferences.letterLayout, .frequency)
        XCTAssertEqual(KeyboardPreferences.handedness, .right)
        XCTAssertEqual(KeyboardPreferences.keyColouring, .vowels)
        XCTAssertEqual(KeyboardPreferences.contrastTheme, .whiteOnBlack)
        XCTAssertTrue(KeyboardPreferences.literacyFontEnabled)
        XCTAssertFalse(KeyboardPreferences.bethModeEnabled)

        KeyboardPreferences.suite.set(true, forKey: KeyboardPreferences.bethModeEnabledKey)
        KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.keyColouringKey)
        XCTAssertEqual(KeyboardPreferences.keyColouring, .beth)

        KeyboardPreferences.keyColouring = .beth
        XCTAssertTrue(KeyboardPreferences.bethModeEnabled)
        KeyboardPreferences.bethModeEnabled = false
        XCTAssertEqual(KeyboardPreferences.keyColouring, .none)
    }

    func testLiteracyFontIsBundled() {
        XCTAssertEqual(LiteracyFont.postScriptName, "Andika")
        XCTAssertNotNil(
            Bundle.module.url(forResource: LiteracyFont.resourceName, withExtension: LiteracyFont.resourceExtension),
            "Andika-Regular.ttf must ship in AccessKeyboardCore resources"
        )
    }

    private func compact(
        _ letterLayout: LetterLayout,
        handedness: Handedness = .standard
    ) -> KeyboardLayout {
        LayoutFactory.layout(
            mode: .alphabetic,
            shift: .off,
            layoutClass: .compact,
            needsInputModeSwitchKey: false,
            returnKeyType: .default,
            letterLayout: letterLayout,
            handedness: handedness
        )
    }
}

private struct PreferenceSnapshot {
    let letterLayout: LetterLayout
    let handedness: Handedness
    let keyColouringRaw: String?
    let contrastTheme: ContrastTheme
    let literacyFontEnabled: Bool
    let bethModeEnabled: Bool

    static func capture() -> PreferenceSnapshot {
        PreferenceSnapshot(
            letterLayout: KeyboardPreferences.letterLayout,
            handedness: KeyboardPreferences.handedness,
            keyColouringRaw: KeyboardPreferences.suite.string(forKey: KeyboardPreferences.keyColouringKey),
            contrastTheme: KeyboardPreferences.contrastTheme,
            literacyFontEnabled: KeyboardPreferences.literacyFontEnabled,
            bethModeEnabled: KeyboardPreferences.suite.bool(forKey: KeyboardPreferences.bethModeEnabledKey)
        )
    }

    func restore() {
        KeyboardPreferences.letterLayout = letterLayout
        KeyboardPreferences.handedness = handedness
        KeyboardPreferences.contrastTheme = contrastTheme
        KeyboardPreferences.literacyFontEnabled = literacyFontEnabled
        if let keyColouringRaw {
            KeyboardPreferences.suite.set(keyColouringRaw, forKey: KeyboardPreferences.keyColouringKey)
        } else {
            KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.keyColouringKey)
        }
        KeyboardPreferences.suite.set(bethModeEnabled, forKey: KeyboardPreferences.bethModeEnabledKey)
    }
}
