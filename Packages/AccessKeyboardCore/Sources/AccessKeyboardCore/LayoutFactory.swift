import UIKit

public enum LayoutFactory {
    public static func layout(
        mode: KeyboardMode,
        shift: ShiftState,
        layoutClass: LayoutClass,
        needsInputModeSwitchKey: Bool,
        returnKeyType: UIReturnKeyType,
        letterLayout: LetterLayout = .qwerty,
        handedness: Handedness = .standard
    ) -> KeyboardLayout {
        switch layoutClass {
        case .compact:
            return compactLayout(
                mode: mode,
                shift: shift,
                needsGlobe: needsInputModeSwitchKey,
                returnKeyType: returnKeyType,
                letterLayout: letterLayout,
                handedness: handedness
            )
        case .iPad:
            return iPadLayout(
                mode: mode,
                shift: shift,
                needsGlobe: needsInputModeSwitchKey,
                returnKeyType: returnKeyType,
                letterLayout: letterLayout,
                handedness: handedness
            )
        case .iPadPro:
            return iPadProLayout(
                mode: mode,
                shift: shift,
                needsGlobe: needsInputModeSwitchKey,
                returnKeyType: returnKeyType,
                letterLayout: letterLayout,
                handedness: handedness
            )
        }
    }

    // MARK: - Compact (floating / iPhone-width)

    private static func compactLayout(
        mode: KeyboardMode,
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        letterLayout: LetterLayout,
        handedness: Handedness
    ) -> KeyboardLayout {
        let rows: [KeyboardRow]
        switch mode {
        case .alphabetic:
            if letterLayout == .frequency {
                rows = compactFrequencyRows(
                    shift: shift,
                    needsGlobe: needsGlobe,
                    returnKeyType: returnKeyType,
                    handedness: handedness
                )
            } else {
                let map = LetterMaps.frameRows(for: letterLayout, handedness: handedness)
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
        return KeyboardLayout(rows: rows, layoutClass: .compact)
    }

    private static func compactBottomLetterRow(_ lettersString: String, shift: ShiftState) -> [KeySpec] {
        [shiftKey(compact: true, shift: shift)]
            + letters(lettersString, shift: shift)
            + [backspace(compact: true)]
    }

    private static func compactFrequencyRows(
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        handedness: Handedness
    ) -> [KeyboardRow] {
        let freq = LetterMaps.frequencyRows(handedness: handedness)
        var rows = freq.dropLast().map { KeyboardRow(keys: letters($0, shift: shift)) }
        if let last = freq.last {
            rows.append(
                KeyboardRow(keys: [shiftKey(compact: true, shift: shift)] + letters(last, shift: shift) + [backspace(compact: true)])
            )
        }
        rows.append(KeyboardRow(keys: compactToolbar(mode: .alphabetic, needsGlobe: needsGlobe, returnKeyType: returnKeyType)))
        return rows
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
        letterLayout: LetterLayout,
        handedness: Handedness
    ) -> KeyboardLayout {
        let rows: [KeyboardRow]
        switch mode {
        case .alphabetic:
            if letterLayout == .frequency {
                rows = iPadFrequencyRows(
                    shift: shift,
                    needsGlobe: needsGlobe,
                    returnKeyType: returnKeyType,
                    handedness: handedness,
                    pro: false
                )
            } else {
                let map = LetterMaps.frameRows(for: letterLayout, handedness: handedness)
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
        return KeyboardLayout(rows: rows, layoutClass: .iPad)
    }

    // MARK: - iPad Pro (12.9" / 13" and other wide boards)

    private static func iPadProLayout(
        mode: KeyboardMode,
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        letterLayout: LetterLayout,
        handedness: Handedness
    ) -> KeyboardLayout {
        let rows: [KeyboardRow]
        switch mode {
        case .alphabetic:
            if letterLayout == .frequency {
                rows = iPadFrequencyRows(
                    shift: shift,
                    needsGlobe: needsGlobe,
                    returnKeyType: returnKeyType,
                    handedness: handedness,
                    pro: true
                )
            } else {
                let map = LetterMaps.frameRows(for: letterLayout, handedness: handedness)
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
                ] + chars("§¡¿–—«»") + [
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
        return KeyboardLayout(rows: rows, layoutClass: .iPadPro)
    }

    private static func iPadFrequencyRows(
        shift: ShiftState,
        needsGlobe: Bool,
        returnKeyType: UIReturnKeyType,
        handedness: Handedness,
        pro: Bool
    ) -> [KeyboardRow] {
        let freq = LetterMaps.frequencyRows(handedness: handedness)
        var rows: [KeyboardRow] = []
        if pro {
            rows.append(KeyboardRow(keys: [tabKey()] + letters(freq[0], shift: shift) + [backspace(compact: false, width: .unit(1.8))]))
        } else {
            rows.append(KeyboardRow(keys: letters(freq[0], shift: shift) + [backspace(compact: false, width: .unit(1.5))]))
        }
        rows.append(KeyboardRow(keys: letters(freq[1], shift: shift) + [returnKey(returnKeyType, compact: false, width: .unit(pro ? 1.7 : 1.6))]))
        if pro {
            rows.append(KeyboardRow(keys: [capsLockKey(shift: shift)] + letters(freq[2], shift: shift)))
            rows.append(KeyboardRow(keys: [shiftKey(compact: false, shift: shift, width: .unit(1.5))] + letters(freq[3], shift: shift)))
        } else {
            rows.append(KeyboardRow(keys: [shiftKey(compact: false, shift: shift, width: .unit(1.4))] + letters(freq[2], shift: shift)))
            rows.append(KeyboardRow(keys: letters(freq[3], shift: shift)))
        }
        rows.append(KeyboardRow(keys: letters(freq[4], shift: shift)))
        rows.append(KeyboardRow(keys: iPadToolbar(mode: .alphabetic, needsGlobe: needsGlobe, pro: pro)))
        return rows
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
        keys.append(punctuation(".", width: .unit(1.1)))
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
            let shown = shift.isUppercase ? symbol : number
            return KeySpec(
                action: .character(shown),
                display: .text(shown),
                style: .letter,
                secondary: shift.isUppercase ? number : symbol
            )
        }
    }

    private static func shiftKey(compact: Bool, shift: ShiftState, width: KeyWidth = .unit(1.4)) -> KeySpec {
        let symbol = shift == .capsLock ? "capslock.fill" : (shift == .shifted ? "shift.fill" : "shift")
        let display: KeyDisplay = compact ? .symbol(symbol) : .text("shift")
        return KeySpec(action: .shift, display: display, width: width, style: .modifier)
    }

    private static func capsLockKey(shift: ShiftState) -> KeySpec {
        let display: KeyDisplay = shift == .capsLock ? .text("caps lock") : .text("caps lock")
        return KeySpec(action: .capsLock, display: display, width: .unit(1.5), style: .modifier)
    }

    private static func backspace(compact: Bool, width: KeyWidth = .unit(1.4)) -> KeySpec {
        KeySpec(
            action: .backspace,
            display: compact ? .symbol("delete.left") : .text("delete"),
            width: width,
            style: .modifier
        )
    }

    private static func tabKey() -> KeySpec {
        KeySpec(action: .tab, display: .text("tab"), width: .unit(1.2), style: .modifier)
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
