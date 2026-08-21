import Foundation

public enum LetterLayout: String, CaseIterable, Identifiable, Sendable {
    case qwerty
    case abc
    case frequency

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .qwerty: return "QWERTY"
        case .abc: return "ABC"
        case .frequency: return "Frequency (EARDU)"
        }
    }
}

public enum Handedness: String, CaseIterable, Identifiable, Sendable {
    case standard
    case left
    case right

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

public enum KeyColouring: String, CaseIterable, Identifiable, Sendable {
    case none
    case vowels
    case hands
    case beth

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: return "None"
        case .vowels: return "Coloured vowels"
        case .hands: return "Hands"
        case .beth: return "Beth"
        }
    }
}

public enum ContrastTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case blackOnWhite
    case whiteOnBlack
    case yellowOnBlack
    case blackOnYellow

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .blackOnWhite: return "Black on white"
        case .whiteOnBlack: return "White on black"
        case .yellowOnBlack: return "Yellow on black"
        case .blackOnYellow: return "Black on yellow"
        }
    }

    public var overridesColouring: Bool {
        self != .system
    }
}

public enum KeyGlyphClass: Equatable, Sendable {
    case vowel
    case consonant
    case number
    case punctuation
    case other

    public static func classify(_ character: String) -> KeyGlyphClass {
        guard let scalar = character.unicodeScalars.first else { return .other }
        if CharacterSet.decimalDigits.contains(scalar) {
            return .number
        }
        if let letter = BethColorMap.baseLetter(in: character) {
            return Self.vowels.contains(letter) ? .vowel : .consonant
        }
        if CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar) {
            return .punctuation
        }
        return .other
    }

    public static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
}

public enum HandSide: Equatable, Sendable {
    case left
    case right
}

public enum HandSplit {
    public static func side(for character: String) -> HandSide? {
        let folded = character.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        guard let raw = folded.first else { return nil }
        if leftCharacters.contains(raw) { return .left }
        if rightCharacters.contains(raw) { return .right }
        return nil
    }

    private static let leftCharacters = Set("qwertasdfgzxcvb12345!@#$%")
    private static let rightCharacters = Set("yuiophjklnm67890^&*(),.<>-=_+")
}

public enum LetterMaps {
    public static func frameRows(
        for layout: LetterLayout,
        handedness: Handedness
    ) -> (top: String, home: String, bottom: String) {
        let rows: (String, String, String)
        switch layout {
        case .qwerty:
            rows = ("qwertyuiop", "asdfghjkl", "zxcvbnm")
        case .abc:
            rows = ("abcdefghij", "klmnopqrs", "tuvwxyz")
        case .frequency:
            rows = ("eardu", "toilgv", "nsfyx")
        }
        return mirrored(rows, handedness == .right && layout != .qwerty)
    }

    public static func frequencyRows(handedness: Handedness) -> [String] {
        let rows = ["eardu", "toilgv", "nsfyx.", "hcpkj,", "mbwqz?"]
        guard handedness == .right else { return rows }
        return rows.map { String($0.reversed()) }
    }

    private static func mirrored(
        _ rows: (String, String, String),
        _ mirror: Bool
    ) -> (String, String, String) {
        guard mirror else { return rows }
        return (String(rows.0.reversed()), String(rows.1.reversed()), String(rows.2.reversed()))
    }
}
