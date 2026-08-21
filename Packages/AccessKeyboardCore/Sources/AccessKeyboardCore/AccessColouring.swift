import UIKit

public enum AccessColouring {
    public static let vowelFill = rgb(0x7A, 0x3F, 0xB0)
    public static let consonantFill = rgb(0x2F, 0x8F, 0x3C)
    public static let numberFill = rgb(0xC2, 0x32, 0x2A)
    public static let punctuationFill = rgb(0xD4, 0xB8, 0x1C)
    public static let leftHandFill = rgb(0x4A, 0x2A, 0x6E)
    public static let rightHandFill = rgb(0xE8, 0x6A, 0x14)
    public static let highContrastYellow = rgb(0xFF, 0xE6, 0x00)

    public static func fill(
        colouring: KeyColouring,
        character: String,
        handedness: Handedness
    ) -> UIColor? {
        switch colouring {
        case .none:
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
        case .hands:
            guard let side = HandSplit.side(for: character) else { return nil }
            let fill = side == .left ? leftHandFill : rightHandFill
            return dimIfUnused(fill, side: side, handedness: handedness)
        }
    }

    public static func foreground(for fill: UIColor, colouring: KeyColouring) -> UIColor {
        if colouring == .hands {
            return .white
        }
        return BethColorMap.foreground(for: fill)
    }

    public static func dimIfUnused(
        _ fill: UIColor,
        side: HandSide,
        handedness: Handedness
    ) -> UIColor {
        switch handedness {
        case .standard:
            return fill
        case .left:
            return side == .right ? dimmed(fill) : fill
        case .right:
            return side == .left ? dimmed(fill) : fill
        }
    }

    public static func dimmed(_ fill: UIColor) -> UIColor {
        blend(fill, with: rgb(0x8A, 0x8A, 0x8A), fraction: 0.48)
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }

    private static func blend(_ fill: UIColor, with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        fill.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = fraction
        return UIColor(
            red: r1 * (1 - t) + r2 * t,
            green: g1 * (1 - t) + g2 * t,
            blue: b1 * (1 - t) + b2 * t,
            alpha: a1 * (1 - t) + a2 * t
        )
    }
}
