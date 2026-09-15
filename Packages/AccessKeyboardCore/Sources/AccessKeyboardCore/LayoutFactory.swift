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

    // MARK: - Frequency (left-docked Smartbox block + right-hand utility grid)

    /// Builds the frequency board as a single dense grid: a left-docked
    /// Smartbox/Grid letter block (`Space earduw / toilfyj / nsmpbxk / hcgvqz`
    /// + Shift) with a utility block of function keys and symbols filling the
    /// space to its RIGHT, instead of leaving that area empty (Mike's ask —
    /// the earlier mockup-v3 board wasted the whole right-hand side and needed a
    /// separate toolbar row underneath).
    ///
    /// The letters keep their exact positions and left-docking so glide/cursor
    /// and switch scanners still start top-left and scan the familiar block;
    /// `Space` stays the top-left cell and `Shift` stays at the end of the
    /// letter block. The function keys (backspace, return, 123, globe, hide)
    /// are grouped in the column immediately right of the letters — the next
    /// cells a left-to-right scan reaches — and common punctuation fills the
    /// remaining cells so every column of the board does useful work. Folding
    /// the old toolbar into this block also drops a whole row, reclaiming
    /// vertical space and making the keys taller. The layout is marked
    /// `leftDocked` so the view keeps square keys flush-left rather than
    /// stretching them across the width.
    private static func frequencyRows(
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        layoutClass: LayoutClass
    ) -> [KeyboardRow] {
        let compact = layoutClass == .compact
        let letterRows = LetterMaps.frequencyLetterRows()
        let rightCells = frequencyRightCells(
            rowCount: letterRows.count,
            columns: frequencyRightColumnCount(for: layoutClass),
            needsGlobe: needsGlobe,
            returnKeyType: returnKeyType,
            compact: compact
        )

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
            keys += rightCells[index]
            rows.append(KeyboardRow(keys: keys))
        }
        return rows
    }

    /// A labelled Space key sized like a letter cell, for the frequency grid's
    /// top-left position.
    private static func spaceCell() -> KeySpec {
        KeySpec(action: .space, display: .text("Space"), width: .unit(1), style: .space)
    }

    /// How many utility columns sit to the right of the frequency letter block.
    /// Wider size classes get one more so more of the extra width is used.
    private static func frequencyRightColumnCount(for layoutClass: LayoutClass) -> Int {
        switch layoutClass {
        case .compact: return 3
        case .iPad: return 3
        case .iPadPro: return 4
        }
    }

    /// The utility block that fills the space to the right of the letters: a
    /// `rowCount × columns` rectangle of function keys and symbols, returned one
    /// key array per letter row. Function keys are laid down the first column
    /// (nearest the letters, so a left-to-right scan reaches them first); any
    /// that overflow are tucked into the bottom-right corner, and every other
    /// cell is a common punctuation key so no cell is wasted.
    private static func frequencyRightCells(
        rowCount: Int,
        columns: Int,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        compact: Bool
    ) -> [[KeySpec]] {
        var functions: [KeySpec] = [
            backspace(compact: compact, width: .unit(1)),
            returnKey(returnKeyType, compact: compact, width: .unit(1)),
            modeKey("123", .numeric, width: .unit(1))
        ]
        if needsGlobe {
            functions.append(globe(width: .unit(1)))
        }
        if !compact {
            functions.append(dismissKey(width: .unit(1)))
        }

        let total = rowCount * columns
        var grid: [KeySpec?] = Array(repeating: nil, count: total)

        // First utility column holds up to `rowCount` function keys.
        let firstColumnCount = min(functions.count, rowCount)
        for row in 0..<firstColumnCount {
            grid[row * columns] = functions[row]
        }
        // Any remaining function keys fill from the bottom-right corner back.
        var tail = total - 1
        for index in rowCount..<functions.count {
            grid[tail] = functions[index]
            tail -= 1
        }
        // Punctuation fills every still-empty cell in reading order.
        var symbolIndex = 0
        for cell in 0..<total where grid[cell] == nil {
            let symbol = frequencySymbols[symbolIndex % frequencySymbols.count]
            grid[cell] = punctuation(symbol)
            symbolIndex += 1
        }

        return (0..<rowCount).map { row in
            Array(grid[(row * columns)..<((row + 1) * columns)].compactMap { $0 })
        }
    }

    /// Common punctuation used to fill the frequency board's right-hand cells,
    /// most-used first.
    private static let frequencySymbols = [
        ".", ",", "?", "!", "'", "\"", "-", "@", ":", ";", "&", "/", "(", ")"
    ]

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

    private static func dismissKey(width: KeyWidth = .unit(1.2)) -> KeySpec {
        KeySpec(action: .dismissKeyboard, display: .symbol("keyboard.chevron.compact.down"), width: width, style: .modifier)
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
