import UIKit

public struct KeyboardAppearance {
    public var backgroundColor: UIColor
    public var letterFill: UIColor
    public var modifierFill: UIColor
    public var primaryFill: UIColor
    public var letterPressedFill: UIColor
    public var modifierPressedFill: UIColor
    public var textColor: UIColor
    public var modifierTextColor: UIColor
    public var primaryTextColor: UIColor
    public var secondaryTextColor: UIColor
    public var shadowColor: UIColor
    public var calloutFill: UIColor
    public var colour: ColourOption
    public var usesBethLetterColors: Bool

    public init(
        backgroundColor: UIColor,
        letterFill: UIColor,
        modifierFill: UIColor,
        primaryFill: UIColor,
        letterPressedFill: UIColor,
        modifierPressedFill: UIColor,
        textColor: UIColor,
        modifierTextColor: UIColor,
        primaryTextColor: UIColor,
        secondaryTextColor: UIColor,
        shadowColor: UIColor,
        calloutFill: UIColor,
        colour: ColourOption = .system,
        usesBethLetterColors: Bool = false
    ) {
        self.backgroundColor = backgroundColor
        self.letterFill = letterFill
        self.modifierFill = modifierFill
        self.primaryFill = primaryFill
        self.letterPressedFill = letterPressedFill
        self.modifierPressedFill = modifierPressedFill
        self.textColor = textColor
        self.modifierTextColor = modifierTextColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.shadowColor = shadowColor
        self.calloutFill = calloutFill
        self.colour = colour
        self.usesBethLetterColors = usesBethLetterColors
    }

    public static func resolved(
        colour: ColourOption,
        style: UIUserInterfaceStyle
    ) -> KeyboardAppearance {
        var appearance: KeyboardAppearance
        switch colour {
        case .system, .vowels, .beth:
            appearance = system(for: style)
        case .highContrastWhite:
            appearance = highContrast(
                background: .black,
                keyFill: UIColor(white: 0.12, alpha: 1),
                modifierFill: .black,
                text: .white,
                primaryFill: .white,
                primaryText: .black
            )
        case .highContrastYellow:
            appearance = highContrast(
                background: .black,
                keyFill: UIColor(white: 0.08, alpha: 1),
                modifierFill: .black,
                text: AccessColouring.highContrastYellow,
                primaryFill: AccessColouring.highContrastYellow,
                primaryText: .black
            )
        }
        appearance.colour = colour
        appearance.usesBethLetterColors = colour == .beth
        return appearance
    }

    public static func system(for style: UIUserInterfaceStyle) -> KeyboardAppearance {
        switch style {
        case .dark:
            return KeyboardAppearance(
                backgroundColor: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1),
                letterFill: UIColor(red: 0.45, green: 0.45, blue: 0.46, alpha: 1),
                modifierFill: UIColor(red: 0.28, green: 0.28, blue: 0.29, alpha: 1),
                primaryFill: UIColor.systemBlue,
                letterPressedFill: UIColor(red: 0.28, green: 0.28, blue: 0.29, alpha: 1),
                modifierPressedFill: UIColor(red: 0.45, green: 0.45, blue: 0.46, alpha: 1),
                textColor: .white,
                modifierTextColor: UIColor(white: 0.92, alpha: 1),
                primaryTextColor: .white,
                secondaryTextColor: UIColor(white: 0.72, alpha: 1),
                shadowColor: UIColor.black.withAlphaComponent(0.55),
                calloutFill: UIColor(red: 0.45, green: 0.45, blue: 0.46, alpha: 1)
            )
        default:
            return KeyboardAppearance(
                backgroundColor: UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1),
                letterFill: .white,
                modifierFill: UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1),
                primaryFill: UIColor.systemBlue,
                letterPressedFill: UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1),
                modifierPressedFill: .white,
                textColor: .black,
                modifierTextColor: UIColor(white: 0.12, alpha: 1),
                primaryTextColor: .white,
                secondaryTextColor: UIColor(white: 0.38, alpha: 1),
                shadowColor: UIColor.black.withAlphaComponent(0.28),
                calloutFill: .white
            )
        }
    }

    public func fill(
        for style: KeyStyle,
        character: String? = nil,
        pressed: Bool,
        highlightedModifier: Bool
    ) -> UIColor {
        if highlightedModifier, !pressed {
            switch style {
            case .letter, .space:
                break
            case .modifier, .primary:
                return letterFill
            }
        }
        if let overlay = decorativeFill(for: style, character: character) {
            return pressed ? BethColorMap.pressedFill(for: overlay) : overlay
        }
        switch style {
        case .letter, .space:
            return pressed ? letterPressedFill : letterFill
        case .modifier:
            return pressed ? modifierPressedFill : modifierFill
        case .primary:
            return pressed ? letterFill : primaryFill
        }
    }

    public func foreground(for style: KeyStyle, character: String? = nil) -> UIColor {
        if let overlay = decorativeFill(for: style, character: character) {
            return AccessColouring.foreground(for: overlay)
        }
        switch style {
        case .letter, .space: return textColor
        case .modifier: return modifierTextColor
        case .primary: return primaryTextColor
        }
    }

    private func decorativeFill(for style: KeyStyle, character: String?) -> UIColor? {
        guard style == .letter, let character else { return nil }
        return AccessColouring.fill(colour: colour, character: character)
    }

    private static func highContrast(
        background: UIColor,
        keyFill: UIColor,
        modifierFill: UIColor,
        text: UIColor,
        primaryFill: UIColor,
        primaryText: UIColor
    ) -> KeyboardAppearance {
        KeyboardAppearance(
            backgroundColor: background,
            letterFill: keyFill,
            modifierFill: modifierFill,
            primaryFill: primaryFill,
            letterPressedFill: modifierFill,
            modifierPressedFill: keyFill,
            textColor: text,
            modifierTextColor: text,
            primaryTextColor: primaryText,
            secondaryTextColor: text.withAlphaComponent(0.75),
            shadowColor: UIColor.black.withAlphaComponent(0.45),
            calloutFill: keyFill
        )
    }
}
