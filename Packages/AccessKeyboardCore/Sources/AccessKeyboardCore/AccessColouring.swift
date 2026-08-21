import UIKit

public enum AccessColouring {
    public static let vowelFill = rgb(0x7A, 0x3F, 0xB0)
    public static let consonantFill = rgb(0x2F, 0x8F, 0x3C)
    public static let numberFill = rgb(0xC2, 0x32, 0x2A)
    public static let punctuationFill = rgb(0xD4, 0xB8, 0x1C)
    public static let highContrastYellow = rgb(0xFF, 0xE6, 0x00)

    public static func fill(colour: ColourOption, character: String) -> UIColor? {
        switch colour {
        case .system, .highContrastWhite, .highContrastYellow:
            return nil
        case .beth:
            return BethColorMap.fill(for: character)
        case .vowels:
            switch KeyGlyphClass.classify(character) {
            case .vowel: return vowelFill
            case .consonant: return consonantFill
            case .number: return numberFill
            case .punctuation: return punctuationFill
            case .other: return nil
            }
        }
    }

    public static func foreground(for fill: UIColor) -> UIColor {
        BethColorMap.foreground(for: fill)
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}
