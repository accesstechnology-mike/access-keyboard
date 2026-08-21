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

public enum ColourOption: String, CaseIterable, Identifiable, Sendable {
    case system
    case vowels
    case beth
    case highContrastWhite
    case highContrastYellow

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .vowels: return "Coloured vowels"
        case .beth: return "Beth"
        case .highContrastWhite: return "Hi-contrast white"
        case .highContrastYellow: return "Hi-contrast yellow"
        }
    }

    public var isHighContrast: Bool {
        switch self {
        case .highContrastWhite, .highContrastYellow:
            return true
        case .system, .vowels, .beth:
            return false
        }
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

public enum LetterMaps {
    public static func frameRows(
        for layout: LetterLayout
    ) -> (top: String, home: String, bottom: String) {
        switch layout {
        case .qwerty:
            return ("qwertyuiop", "asdfghjkl", "zxcvbnm")
        case .abc:
            return ("abcdefghij", "klmnopqrs", "tuvwxyz")
        case .frequency:
            return ("eardu", "toilgv", "nsfyx")
        }
    }

    public static func frequencyRows() -> [String] {
        ["eardu", "toilgv", "nsfyx.", "hcpkj,", "mbwqz?"]
    }
}
