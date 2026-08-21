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

    func testQWERTYKeepsStandardOrder() {
        let layout = compact(.qwerty)
        XCTAssertEqual(layout.letterString(inRow: 0), "qwertyuiop")
        XCTAssertEqual(layout.letterString(inRow: 1), "asdfghjkl")
        XCTAssertEqual(layout.letterString(inRow: 2), "zxcvbnm")
    }

    func testEARDUFrequencyOrder() {
        XCTAssertEqual(
            LetterMaps.frequencyRows(),
            ["eardu", "toilgv", "nsfyx.", "hcpkj,", "mbwqz?"]
        )

        let layout = compact(.frequency)
        XCTAssertEqual(layout.letterString(inRow: 0), "eardu")
        XCTAssertEqual(layout.letterString(inRow: 1), "toilgv")
        XCTAssertEqual(layout.letterString(inRow: 2), "nsfyx.")
        XCTAssertEqual(layout.letterString(inRow: 3), "hcpkj,")
        XCTAssertEqual(layout.letterString(inRow: 4), "mbwqz?")
    }

    func testShiftedLetterKeycapsAreUppercase() {
        let layout = LayoutFactory.layout(
            mode: .alphabetic,
            shift: .shifted,
            layoutClass: .compact,
            needsInputModeSwitchKey: false,
            returnKeyType: .default,
            letterLayout: .qwerty
        )
        let q = layout.rows[0].keys.first { spec in
            if case .character(let text) = spec.action { return text.lowercased() == "q" }
            return false
        }
        XCTAssertEqual(q?.action, .character("Q"))
        if case .text(let value) = q?.display {
            XCTAssertEqual(value, "Q")
        } else {
            XCTFail("Q key should display text")
        }

        let caps = LayoutFactory.layout(
            mode: .alphabetic,
            shift: .capsLock,
            layoutClass: .compact,
            needsInputModeSwitchKey: false,
            returnKeyType: .default,
            letterLayout: .abc
        )
        XCTAssertEqual(caps.rows[0].keys.first?.action, .character("A"))
    }

    func testColourOptionsAreTheSimplifiedSet() {
        XCTAssertEqual(
            ColourOption.allCases.map(\.title),
            [
                "System",
                "Coloured vowels",
                "Beth",
                "Hi-contrast white",
                "Hi-contrast yellow"
            ]
        )
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

    func testHighContrastOptionsDoNotPaintLetters() {
        let white = KeyboardAppearance.resolved(colour: .highContrastWhite, style: .dark)
        XCTAssertFalse(white.usesBethLetterColors)
        XCTAssertEqual(white.textColor, .white)
        XCTAssertEqual(
            white.fill(for: .letter, character: "a", pressed: false, highlightedModifier: false),
            white.letterFill
        )
        XCTAssertEqual(white.foreground(for: .letter, character: "a"), white.textColor)

        let yellow = KeyboardAppearance.resolved(colour: .highContrastYellow, style: .dark)
        XCTAssertFalse(yellow.usesBethLetterColors)
        XCTAssertEqual(yellow.textColor, AccessColouring.highContrastYellow)
        XCTAssertEqual(
            yellow.fill(for: .letter, character: "a", pressed: false, highlightedModifier: false),
            yellow.letterFill
        )
    }

    func testVowelColouringPaintsLettersAndLeavesModifiers() {
        let appearance = KeyboardAppearance.resolved(colour: .vowels, style: .light)
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

    func testBethColouringUsesBethMap() {
        let appearance = KeyboardAppearance.resolved(colour: .beth, style: .light)
        XCTAssertTrue(appearance.usesBethLetterColors)
        XCTAssertEqual(
            appearance.fill(for: .letter, character: "a", pressed: false, highlightedModifier: false),
            BethColorMap.fill(for: "a")
        )
    }

    func testPreferenceKeysRoundTripThroughTheAppGroupSuite() {
        KeyboardPreferences.letterLayout = .frequency
        KeyboardPreferences.colourOption = .vowels

        XCTAssertEqual(KeyboardPreferences.letterLayout, .frequency)
        XCTAssertEqual(KeyboardPreferences.colourOption, .vowels)
        XCTAssertFalse(KeyboardPreferences.bethModeEnabled)

        KeyboardPreferences.colourOption = .beth
        XCTAssertTrue(KeyboardPreferences.bethModeEnabled)
        KeyboardPreferences.bethModeEnabled = false
        XCTAssertEqual(KeyboardPreferences.colourOption, .system)
    }

    func testLegacyContrastAndColouringMigrateIntoColourOption() {
        KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.colourOptionKey)
        KeyboardPreferences.suite.set("whiteOnBlack", forKey: KeyboardPreferences.legacyContrastThemeKey)
        KeyboardPreferences.suite.set("vowels", forKey: KeyboardPreferences.legacyKeyColouringKey)
        XCTAssertEqual(KeyboardPreferences.colourOption, .highContrastWhite)

        KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.colourOptionKey)
        KeyboardPreferences.suite.set("system", forKey: KeyboardPreferences.legacyContrastThemeKey)
        KeyboardPreferences.suite.set("vowels", forKey: KeyboardPreferences.legacyKeyColouringKey)
        XCTAssertEqual(KeyboardPreferences.colourOption, .vowels)

        KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.colourOptionKey)
        KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.legacyContrastThemeKey)
        KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.legacyKeyColouringKey)
        KeyboardPreferences.suite.set(true, forKey: KeyboardPreferences.bethModeEnabledKey)
        XCTAssertEqual(KeyboardPreferences.colourOption, .beth)

        KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.colourOptionKey)
        KeyboardPreferences.suite.set("blackOnYellow", forKey: KeyboardPreferences.legacyContrastThemeKey)
        KeyboardPreferences.persistMigratedColourOptionIfNeeded()
        XCTAssertEqual(KeyboardPreferences.colourOption, .system)
    }

    func testLiteracyFontIsBundled() {
        XCTAssertEqual(LiteracyFont.postScriptName, "Andika")
        XCTAssertNotNil(
            Bundle.module.url(forResource: LiteracyFont.resourceName, withExtension: LiteracyFont.resourceExtension),
            "Andika-Regular.ttf must ship in AccessKeyboardCore resources"
        )
    }

    func testEyeGazeKeyHeights() {
        let iPad = LayoutMetrics.metrics(
            for: .iPad,
            bounds: CGSize(width: 834, height: 1194),
            safeBottom: 0
        )
        XCTAssertEqual(iPad.keyHeight, 80)

        let iPadLandscape = LayoutMetrics.metrics(
            for: .iPad,
            bounds: CGSize(width: 1194, height: 834),
            safeBottom: 0
        )
        XCTAssertEqual(iPadLandscape.keyHeight, 72)

        let pro = LayoutMetrics.metrics(
            for: .iPadPro,
            bounds: CGSize(width: 1024, height: 1366),
            safeBottom: 0
        )
        XCTAssertEqual(pro.keyHeight, 78)

        let compact = LayoutMetrics.metrics(
            for: .compact,
            bounds: CGSize(width: 320, height: 400),
            safeBottom: 0
        )
        XCTAssertEqual(compact.keyHeight, 52)
    }

    private func compact(_ letterLayout: LetterLayout) -> KeyboardLayout {
        LayoutFactory.layout(
            mode: .alphabetic,
            shift: .off,
            layoutClass: .compact,
            needsInputModeSwitchKey: false,
            returnKeyType: .default,
            letterLayout: letterLayout
        )
    }
}

private struct PreferenceSnapshot {
    let letterLayout: LetterLayout
    let colourOptionRaw: String?
    let keyColouringRaw: String?
    let contrastThemeRaw: String?
    let bethModeEnabled: Bool

    static func capture() -> PreferenceSnapshot {
        PreferenceSnapshot(
            letterLayout: KeyboardPreferences.letterLayout,
            colourOptionRaw: KeyboardPreferences.suite.string(forKey: KeyboardPreferences.colourOptionKey),
            keyColouringRaw: KeyboardPreferences.suite.string(forKey: KeyboardPreferences.legacyKeyColouringKey),
            contrastThemeRaw: KeyboardPreferences.suite.string(forKey: KeyboardPreferences.legacyContrastThemeKey),
            bethModeEnabled: KeyboardPreferences.suite.bool(forKey: KeyboardPreferences.bethModeEnabledKey)
        )
    }

    func restore() {
        KeyboardPreferences.letterLayout = letterLayout
        if let colourOptionRaw {
            KeyboardPreferences.suite.set(colourOptionRaw, forKey: KeyboardPreferences.colourOptionKey)
        } else {
            KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.colourOptionKey)
        }
        if let keyColouringRaw {
            KeyboardPreferences.suite.set(keyColouringRaw, forKey: KeyboardPreferences.legacyKeyColouringKey)
        } else {
            KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.legacyKeyColouringKey)
        }
        if let contrastThemeRaw {
            KeyboardPreferences.suite.set(contrastThemeRaw, forKey: KeyboardPreferences.legacyContrastThemeKey)
        } else {
            KeyboardPreferences.suite.removeObject(forKey: KeyboardPreferences.legacyContrastThemeKey)
        }
        KeyboardPreferences.suite.set(bethModeEnabled, forKey: KeyboardPreferences.bethModeEnabledKey)
    }
}
