import UIKit

public enum KeyboardMode: Equatable {
    case alphabetic
    case numeric
    case symbols
}

public enum ShiftState: Equatable {
    case off
    case shifted
    case capsLock

    public var isUppercase: Bool {
        self != .off
    }
}

public enum KeyStyle: Equatable {
    case letter
    case modifier
    case primary
    case space
}

public enum KeyWidth: Equatable {
    case unit(CGFloat)
    case flexible
}

public enum KeyAction: Equatable {
    case character(String)
    case shift
    case capsLock
    case backspace
    case space
    case returnKey
    case tab
    case setMode(KeyboardMode)
    case nextKeyboard
    case dismissKeyboard
    case undo
    case redo
}

public enum KeyDisplay: Equatable {
    case text(String)
    case symbol(String)
    case blank
}

public struct KeySpec: Equatable {
    public var action: KeyAction
    public var display: KeyDisplay
    public var shiftedDisplay: KeyDisplay?
    public var width: KeyWidth
    public var style: KeyStyle
    public var secondary: String?

    public init(
        action: KeyAction,
        display: KeyDisplay,
        shiftedDisplay: KeyDisplay? = nil,
        width: KeyWidth = .unit(1),
        style: KeyStyle = .letter,
        secondary: String? = nil
    ) {
        self.action = action
        self.display = display
        self.shiftedDisplay = shiftedDisplay
        self.width = width
        self.style = style
        self.secondary = secondary
    }

    public static func letter(_ value: String, width: KeyWidth = .unit(1)) -> KeySpec {
        KeySpec(
            action: .character(value),
            display: .text(value),
            width: width,
            style: .letter
        )
    }

    public static func punctuation(_ value: String, shifted: String? = nil, width: KeyWidth = .unit(1)) -> KeySpec {
        KeySpec(
            action: .character(value),
            display: .text(value),
            shiftedDisplay: shifted.map { .text($0) },
            width: width,
            style: .letter
        )
    }
}

public struct KeyboardRow: Equatable {
    public var keys: [KeySpec]
    public var leadingInsetUnits: CGFloat

    public init(keys: [KeySpec], leadingInsetUnits: CGFloat = 0) {
        self.keys = keys
        self.leadingInsetUnits = leadingInsetUnits
    }
}

public struct KeyboardLayout: Equatable {
    public var rows: [KeyboardRow]
    public var layoutClass: LayoutClass

    public init(rows: [KeyboardRow], layoutClass: LayoutClass) {
        self.rows = rows
        self.layoutClass = layoutClass
    }
}

public enum LayoutClass: Equatable {
    case compact
    case iPad
    case iPadPro

    public var usesWordLabels: Bool {
        self != .compact
    }
}
