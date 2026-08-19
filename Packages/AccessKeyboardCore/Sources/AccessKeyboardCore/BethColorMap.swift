import UIKit

/// Letter fills sampled from Beth Moulam’s TD Snap keyboard on a TD Pilot.
/// Values are median sRGB of saturated pixels in each key interior from the device photo.
public enum BethColorMap {
    public static func fill(for character: String) -> UIColor? {
        guard let letter = baseLetter(in: character) else { return nil }
        return fills[letter]
    }

    public static func foreground(for fill: UIColor) -> UIColor {
        contrast(fill, .white) >= contrast(fill, .black) ? .white : .black
    }

    public static func pressedFill(for fill: UIColor) -> UIColor {
        blend(fill, with: .black, fraction: 0.22)
    }

    public static func baseLetter(in character: String) -> Character? {
        let folded = character.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        guard let scalar = folded.unicodeScalars.first,
              CharacterSet.letters.contains(scalar),
              scalar.isASCII else {
            return nil
        }
        let letter = Character(scalar).lowercased()
        guard letter.count == 1, let ch = letter.first else { return nil }
        return ch
    }

    private static let fills: [Character: UIColor] = [
        "q": rgb(0x3C, 0x85, 0xC5),
        "w": rgb(0x0C, 0x46, 0xC1),
        "e": rgb(0xC1, 0x3E, 0x34),
        "r": rgb(0xB5, 0x3E, 0x34),
        "t": rgb(0xC1, 0x8C, 0x30),
        "y": rgb(0xD1, 0xCB, 0x35),
        "u": rgb(0x6F, 0x85, 0xAC),
        "i": rgb(0xD0, 0xCB, 0x51),
        "o": rgb(0xC5, 0x9C, 0x5A),
        "p": rgb(0x9E, 0x4A, 0x3C),
        "a": rgb(0x8D, 0xE1, 0x74),
        "s": rgb(0xE9, 0xE1, 0x28),
        "d": rgb(0xD6, 0x97, 0x29),
        "f": rgb(0x1B, 0x41, 0xB1),
        "g": rgb(0x55, 0x8B, 0x56),
        "h": rgb(0x7A, 0x9C, 0x6E),
        "j": rgb(0x66, 0x7F, 0xA7),
        "k": rgb(0x7A, 0x98, 0xA7),
        "l": rgb(0x84, 0x93, 0x9F),
        "z": rgb(0x00, 0x00, 0x00),
        "x": rgb(0xC8, 0x3F, 0x30),
        "c": rgb(0xB9, 0x3F, 0x31),
        "v": rgb(0xA8, 0x98, 0xC0),
        "b": rgb(0x6B, 0x8A, 0x90),
        "n": rgb(0x64, 0x7E, 0x5F),
        "m": rgb(0xC5, 0xB0, 0xB8)
    ]

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }

    private static func linear(_ component: CGFloat) -> CGFloat {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let l1 = luminance(a)
        let l2 = luminance(b)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func blend(_ fill: UIColor, with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
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
