import UIKit

public enum LayoutFactory {
    public static func layout(
        mode: KeyboardMode,
        shift: ShiftState,
        layoutClass: LayoutClass,
        needsInputModeSwitchKey: Bool,
        returnKeyType: UIReturnKeyType,
        letterLayout: LetterLayout = .qwerty
    ) -> KeyboardLayout {
        switch layoutClass {
        case .compact:
            return compactLayout(
                mode: mode,
                shift: shift,
                needsGlobe: needsInputModeSwitchKey,
                returnKeyType: returnKeyType,
                letterLayout: letterLayout
            )
        case .iPad:
            return iPadLayout(
                mode: mode,
                shift: shift,
                needsGlobe: needsInputModeSwitchKey,
                returnKeyType: returnKeyType,
                letterLayout: letterLayout
            )
        case .iPadPro:
            return iPadProLayout(
                mode: mode,
                shift: shift,
                needsGlobe: needsInputModeSwitchKey,
                returnKeyType: returnKeyType,
                letterLayout: letterLayout
            )
        }
    }

    // MARK: - Compact (floating / iPhone-width)

    private static func compactLayout(
        mode: KeyboardMode,
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        letterLayout: LetterLayout
    ) -> KeyboardLayout {
        let rows: [KeyboardRow]
        switch mode {
        case .alphabetic:
            if letterLayout == .frequency {
                rows = frequencyRows(
                    shift: shift,
                    needsGlobe: needsGlobe,
                    returnKeyType: returnKeyType,
                    layoutClass: .compact
                )
            } else {
                let map = LetterMaps.frameRows(for: letterLayout)
                rows = [
                    KeyboardRow(keys: letters(map.top, shift: shift)),
                    KeyboardRow(keys: letters(map.home, shift: shift)),
                    KeyboardRow(keys: compactBottomLetterRow(map.bottom, shift: shift)),
                    KeyboardRow(keys: compactToolbar(mode: .alphabetic, needsGlobe: needsGlobe, returnKeyType: returnKeyType))
                ]
            }
        case .numeric:
            rows = [
                KeyboardRow(keys: chars("1234567890")),
                KeyboardRow(keys: chars("-/:;()$&@\"")),
                KeyboardRow(keys: [modeKey("#+=", .symbols, width: .unit(1.4))] + chars(".,?!'") + [backspace(compact: true)]),
                KeyboardRow(keys: compactToolbar(mode: .numeric, needsGlobe: needsGlobe, returnKeyType: returnKeyType))
            ]
        case .symbols:
            rows = [
                KeyboardRow(keys: chars("[]{}#%^*+=")),
                KeyboardRow(keys: chars("_\\|~<>€£¥·")),
                KeyboardRow(keys: [modeKey("123", .numeric, width: .unit(1.4))] + chars(".,?!'") + [backspace(compact: true)]),
                KeyboardRow(keys: compactToolbar(mode: .symbols, needsGlobe: needsGlobe, returnKeyType: returnKeyType))
            ]
        }
        return stamped(rows: rows, mode: mode, letterLayout: letterLayout, layoutClass: .compact)
    }

    private static func compactBottomLetterRow(_ lettersString: String, shift: ShiftState) -> [KeySpec] {
        [shiftKey(compact: true, shift: shift)]
            + letters(lettersString, shift: shift)
            + [backspace(compact: true)]
    }

    private static func compactToolbar(mode: KeyboardMode, needsGlobe: Bool, returnKeyType: UIReturnKeyType) -> [KeySpec] {
        var keys: [KeySpec] = []
        if mode == .alphabetic {
            keys.append(modeKey("123", .numeric, width: .unit(1.5)))
        } else {
            keys.append(modeKey("ABC", .alphabetic, width: .unit(1.5)))
        }
        if needsGlobe {
            keys.append(globe(width: .unit(1.2)))
        }
        keys.append(space(width: .flexible))
        keys.append(returnKey(returnKeyType, compact: true, width: .unit(2.2)))
        return keys
    }

    // MARK: - iPad (11" / Air / portrait-class)

    private static func iPadLayout(
        mode: KeyboardMode,
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        letterLayout: LetterLayout
    ) -> KeyboardLayout {
        let rows: [KeyboardRow]
        switch mode {
        case .alphabetic:
            if letterLayout == .frequency {
                rows = frequencyRows(
                    shift: shift,
                    needsGlobe: needsGlobe,
                    returnKeyType: returnKeyType,
                    layoutClass: .iPad
                )
            } else {
                let map = LetterMaps.frameRows(for: letterLayout)
                rows = [
                    KeyboardRow(keys: letters(map.top, shift: shift) + [backspace(compact: false, width: .unit(1.5))]),
                    KeyboardRow(keys: letters(map.home, shift: shift) + [
                        punctuation(";", shifted: ":"),
                        punctuation("'", shifted: "\""),
                        returnKey(returnKeyType, compact: false, width: .unit(1.6))
                    ]),
                    KeyboardRow(keys: [
                        shiftKey(compact: false, shift: shift, width: .unit(1.4)),
                        punctuation("`", shifted: "~")
                    ] + letters(map.bottom, shift: shift) + [
                        punctuation(",", shifted: "<"),
                        punctuation(".", shifted: ">"),
                        punctuation("/", shifted: "?"),
                        shiftKey(compact: false, shift: shift, width: .unit(1.4))
                    ]),
                    KeyboardRow(keys: iPadToolbar(mode: .alphabetic, needsGlobe: needsGlobe, pro: false))
                ]
            }
        case .numeric:
            rows = [
                KeyboardRow(keys: chars("1234567890") + [backspace(compact: false, width: .unit(1.5))]),
                KeyboardRow(keys: chars("-/:;()$&@\"") + [returnKey(returnKeyType, compact: false, width: .unit(1.6))]),
                KeyboardRow(keys: [
                    modeKey("#+=", .symbols, width: .unit(1.6))
                ] + chars(".,?!'") + [
                    modeKey("#+=", .symbols, width: .unit(1.6))
                ]),
                KeyboardRow(keys: iPadToolbar(mode: .numeric, needsGlobe: needsGlobe, pro: false))
            ]
        case .symbols:
            rows = [
                KeyboardRow(keys: chars("[]{}#%^*+=") + [backspace(compact: false, width: .unit(1.5))]),
                KeyboardRow(keys: chars("_\\|~<>€£¥·") + [returnKey(returnKeyType, compact: false, width: .unit(1.6))]),
                KeyboardRow(keys: [
                    modeKey("123", .numeric, width: .unit(1.6))
                ] + chars(".,?!'") + [
                    modeKey("123", .numeric, width: .unit(1.6))
                ]),
                KeyboardRow(keys: iPadToolbar(mode: .symbols, needsGlobe: needsGlobe, pro: false))
            ]
        }
        return stamped(rows: rows, mode: mode, letterLayout: letterLayout, layoutClass: .iPad)
    }

    // MARK: - iPad Pro (12.9" / 13" and other wide boards)

    private static func iPadProLayout(
        mode: KeyboardMode,
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        letterLayout: LetterLayout
    ) -> KeyboardLayout {
        let rows: [KeyboardRow]
        switch mode {
        case .alphabetic:
            if letterLayout == .frequency {
                rows = frequencyRows(
                    shift: shift,
                    needsGlobe: needsGlobe,
                    returnKeyType: returnKeyType,
                    layoutClass: .iPadPro
                )
            } else {
                let map = LetterMaps.frameRows(for: letterLayout)
                rows = [
                    KeyboardRow(keys: numberRow(shift: shift) + [backspace(compact: false, width: .unit(1.8))]),
                    KeyboardRow(keys: [
                        tabKey()
                    ] + letters(map.top, shift: shift) + [
                        punctuation("[", shifted: "{"),
                        punctuation("]", shifted: "}"),
                        punctuation("\\", shifted: "|")
                    ]),
                    KeyboardRow(keys: [
                        capsLockKey(shift: shift)
                    ] + letters(map.home, shift: shift) + [
                        punctuation(";", shifted: ":"),
                        punctuation("'", shifted: "\""),
                        returnKey(returnKeyType, compact: false, width: .unit(1.7))
                    ]),
                    KeyboardRow(keys: [
                        shiftKey(compact: false, shift: shift, width: .unit(1.5)),
                        punctuation("`", shifted: "~")
                    ] + letters(map.bottom, shift: shift) + [
                        punctuation(",", shifted: "<"),
                        punctuation(".", shifted: ">"),
                        punctuation("/", shifted: "?"),
                        shiftKey(compact: false, shift: shift, width: .unit(1.8))
                    ]),
                    KeyboardRow(keys: iPadToolbar(mode: .alphabetic, needsGlobe: needsGlobe, pro: true))
                ]
            }
        case .numeric:
            rows = [
                KeyboardRow(keys: chars("1234567890-=") + [backspace(compact: false, width: .unit(1.8))]),
                KeyboardRow(keys: [
                    undoKey()
                ] + chars("-/:;()$&@\"") + [
                    returnKey(returnKeyType, compact: false, width: .unit(1.7))
                ]),
                KeyboardRow(keys: [
                    redoKey(),
                    modeKey("#+=", .symbols, width: .unit(1.4))
                ] + chars(".,?!'_|~") + [
                    modeKey("#+=", .symbols, width: .unit(1.8))
                ]),
                KeyboardRow(keys: [
                    modeKey("ABC", .alphabetic, width: .unit(1.5))
                ] + chars("€£¥%…") + [
                    modeKey("ABC", .alphabetic, width: .unit(1.8))
                ]),
                KeyboardRow(keys: iPadToolbar(mode: .numeric, needsGlobe: needsGlobe, pro: true))
            ]
        case .symbols:
            rows = [
                KeyboardRow(keys: chars("[]{}#%^*+=•") + [backspace(compact: false, width: .unit(1.8))]),
                KeyboardRow(keys: [
                    undoKey()
                ] + chars("_\\|~<>€£¥·") + [
                    returnKey(returnKeyType, compact: false, width: .unit(1.7))
                ]),
                KeyboardRow(keys: [
                    redoKey(),
                    modeKey("123", .numeric, width: .unit(1.4))
                ] + chars(".§¡¿–—«»") + [
                    modeKey("123", .numeric, width: .unit(1.8))
                ]),
                KeyboardRow(keys: [
                    modeKey("ABC", .alphabetic, width: .unit(1.5))
                ] + chars("°†‡※∞") + [
                    modeKey("ABC", .alphabetic, width: .unit(1.8))
                ]),
                KeyboardRow(keys: iPadToolbar(mode: .symbols, needsGlobe: needsGlobe, pro: true))
            ]
        }
        return stamped(rows: rows, mode: mode, letterLayout: letterLayout, layoutClass: .iPadPro)
    }

    // MARK: - Layout framing

    /// Wraps rows in a `KeyboardLayout`, marking the frequency board left-docked
    /// and stamping every other page with the alphabetic frame reference so key
    /// size stays constant across ABC / 123 / #+= (no jarring resize on switch).
    private static func stamped(
        rows: [KeyboardRow],
        mode: KeyboardMode,
        letterLayout: LetterLayout,
        layoutClass: LayoutClass
    ) -> KeyboardLayout {
        if mode == .alphabetic, letterLayout == .frequency {
            return KeyboardLayout(rows: rows, layoutClass: layoutClass, leftDocked: true)
        }
        let reference = frameReference(for: layoutClass)
        return KeyboardLayout(
            rows: rows,
            layoutClass: layoutClass,
            referenceUnitWeight: reference.weight,
            referenceKeyCount: reference.count
        )
    }

    /// The QWERTY alphabetic frame's widest-row weight and key count per class.
    /// Stamping this onto the numeric and symbols pages keeps their keys the
    /// same size and their number row aligned with the letter row. The values
    /// are verified against the live alphabetic layout by LayoutStabilityTests,
    /// which fails if the alphabetic frame ever drifts from these numbers.
    static func frameReference(for layoutClass: LayoutClass) -> (weight: CGFloat, count: Int) {
        switch layoutClass {
        case .compact: return (10, 10)
        case .iPad: return (13.8, 13)
        case .iPadPro: return (14.3, 13)
        }
    }

    // MARK: - Frequency (mockup v3: left-docked Smartbox block)

    /// Builds the frequency board to match approved mockup v3: a Smartbox/Grid
    /// letter order (`Space earduw / toilfyj / nsmpbxk / hcgvqz` + Shift) laid
    /// out as an equal-column block that is docked to the LEFT edge of the
    /// canvas rather than floated/centred. Left-docking keeps the scan origin at
    /// the top-left and leaves the right-hand area empty, which is what
    /// glide/cursor and switch scanners expect. `Space` is the first cell
    /// (top-left) and `Shift` is the last cell (bottom-right); the essential
    /// function keys (123, globe, backspace, return, hide) sit in one left-
    /// aligned row beneath the letter block. The owning layout is marked
    /// `leftDocked` so the view lays every row flush-left with square keys
    /// instead of stretching to fill the width.
    private static func frequencyRows(
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        layoutClass: LayoutClass
    ) -> [KeyboardRow] {
        let compact = layoutClass == .compact
        let letterRows = LetterMaps.frequencyLetterRows()

        var rows: [KeyboardRow] = []
        for (index, letterRow) in letterRows.enumerated() {
            var keys: [KeySpec] = []
            if index == 0 {
                keys.append(spaceCell())
            }
            keys += letters(letterRow, shift: shift)
            if index == letterRows.count - 1 {
                keys.append(shiftKey(compact: compact, shift: shift, width: .unit(1)))
            }
            rows.append(KeyboardRow(keys: keys))
        }
        rows.append(KeyboardRow(keys: frequencyToolbar(
            needsGlobe: needsGlobe,
            returnKeyType: returnKeyType,
            compact: compact
        )))
        return rows
    }

    /// A labelled Space key sized like a letter cell, for the frequency grid's
    /// top-left position in mockup v3.
    private static func spaceCell() -> KeySpec {
        KeySpec(action: .space, display: .text("Space"), width: .unit(1), style: .space)
    }

    private static func frequencyToolbar(
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        compact: Bool
    ) -> [KeySpec] {
        // Function keys only; Space lives in the letter grid now. No flexible
        // key, so the row stays left-docked in line with the block above.
        var keys: [KeySpec] = [modeKey("123", .numeric, width: .unit(1))]
        if needsGlobe {
            keys.append(globe(width: .unit(1)))
        }
        keys.append(backspace(compact: compact, width: .unit(1)))
        keys.append(returnKey(returnKeyType, compact: compact, width: .unit(1.4)))
        if !compact {
            keys.append(dismissKey())
        }
        return keys
    }

    private static func iPadToolbar(mode: KeyboardMode, needsGlobe: Bool, pro: Bool) -> [KeySpec] {
        var keys: [KeySpec] = []
        if mode == .alphabetic {
            keys.append(modeKey(".?123", .numeric, width: .unit(pro ? 1.4 : 1.5)))
        } else {
            keys.append(modeKey("ABC", .alphabetic, width: .unit(pro ? 1.4 : 1.5)))
        }
        if needsGlobe {
            keys.append(globe(width: .unit(1.1)))
        }
        if pro {
            keys.append(undoKey())
        }
        keys.append(space(width: .flexible))
        // The full stop already lives on the row above (the letter row's `,` `.`
        // `/` in alphabetic mode, or `.,?!'` in numeric/symbols), matching the
        // stock iPad keyboard. A second period beside the space bar was
        // redundant, so it is removed to leave a single clear affordance.
        if mode == .alphabetic {
            keys.append(modeKey(".?123", .numeric, width: .unit(1.4)))
        } else {
            keys.append(modeKey("ABC", .alphabetic, width: .unit(1.4)))
        }
        keys.append(dismissKey())
        return keys
    }

    // MARK: - Keys

    private static func letters(_ string: String, shift: ShiftState) -> [KeySpec] {
        string.map { ch in
            let raw = String(ch)
            let shown = shift.isUppercase ? raw.uppercased() : raw
            return KeySpec.letter(shown)
        }
    }

    private static func chars(_ string: String) -> [KeySpec] {
        string.map { KeySpec.letter(String($0)) }
    }

    private static func punctuation(_ value: String, shifted: String? = nil, width: KeyWidth = .unit(1)) -> KeySpec {
        KeySpec.punctuation(value, shifted: shifted, width: width)
    }

    private static func numberRow(shift: ShiftState) -> [KeySpec] {
        let pairs: [(String, String)] = [
            ("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"),
            ("6", "^"), ("7", "&"), ("8", "*"), ("9", "("), ("0", ")"),
            ("-", "_"), ("=", "+")
        ]
        return pairs.map { number, symbol in
            let showSymbol = shift.affectsSymbolKeys
            let shown = showSymbol ? symbol : number
            return KeySpec(
                action: .character(shown),
                display: .text(shown),
                style: .letter,
                secondary: showSymbol ? number : symbol
            )
        }
    }

    private static func shiftKey(compact: Bool, shift: ShiftState, width: KeyWidth = .unit(1.4)) -> KeySpec {
        let symbol: String
        switch shift {
        case .capsLock:
            symbol = "capslock.fill"
        case .shifted, .autoShifted:
            symbol = "shift.fill"
        case .off:
            symbol = "shift"
        }
        let display: KeyDisplay = compact ? .symbol(symbol) : .text("shift")
        return KeySpec(action: .shift, display: display, width: width, style: .modifier)
    }

    private static func capsLockKey(shift: ShiftState, width: KeyWidth = .unit(1.5), compact: Bool = false) -> KeySpec {
        // Active state is conveyed by the highlighted fill (see KeyboardView
        // isHighlightedModifier); the label stays constant. Narrow compact keys
        // show the glyph instead of the "caps lock" wordmark so it never clips.
        let display: KeyDisplay = compact ? .symbol("capslock") : .text("caps lock")
        return KeySpec(action: .capsLock, display: display, width: width, style: .modifier)
    }

    private static func backspace(compact: Bool, width: KeyWidth = .unit(1.4)) -> KeySpec {
        KeySpec(
            action: .backspace,
            display: compact ? .symbol("delete.left") : .text("delete"),
            width: width,
            style: .modifier
        )
    }

    private static func tabKey(width: KeyWidth = .unit(1.2)) -> KeySpec {
        KeySpec(action: .tab, display: .text("tab"), width: width, style: .modifier)
    }

    private static func globe(width: KeyWidth) -> KeySpec {
        KeySpec(action: .nextKeyboard, display: .symbol("globe"), width: width, style: .modifier)
    }

    private static func dismissKey() -> KeySpec {
        KeySpec(action: .dismissKeyboard, display: .symbol("keyboard.chevron.compact.down"), width: .unit(1.2), style: .modifier)
    }

    private static func undoKey() -> KeySpec {
        KeySpec(action: .undo, display: .symbol("arrow.uturn.backward"), width: .unit(1.1), style: .modifier)
    }

    private static func redoKey() -> KeySpec {
        KeySpec(action: .redo, display: .symbol("arrow.uturn.forward"), width: .unit(1.1), style: .modifier)
    }

    private static func space(width: KeyWidth) -> KeySpec {
        KeySpec(action: .space, display: .blank, width: width, style: .space)
    }

    private static func modeKey(_ title: String, _ mode: KeyboardMode, width: KeyWidth) -> KeySpec {
        KeySpec(action: .setMode(mode), display: .text(title), width: width, style: .modifier)
    }

    private static func returnKey(_ type: UIReturnKeyType, compact: Bool, width: KeyWidth) -> KeySpec {
        let title: String
        switch type {
        case .go: title = "go"
        case .google: title = "Google"
        case .join: title = "join"
        case .next: title = "next"
        case .route: title = "route"
        case .search: title = "search"
        case .send: title = "send"
        case .done: title = "done"
        case .emergencyCall: title = "emergency"
        case .continue: title = "continue"
        default: title = compact ? "return" : "return"
        }
        let isPrimary = [.go, .search, .send, .done, .join].contains(type)
        return KeySpec(
            action: .returnKey,
            display: .text(title),
            width: width,
            style: isPrimary && compact ? .primary : .modifier
        )
    }
}
