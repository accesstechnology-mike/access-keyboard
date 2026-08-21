import Foundation

public extension Notification.Name {
    static let accessKeyboardPreferencesDidChange = Notification.Name("accessKeyboardPreferencesDidChange")
}

public enum KeyboardPreferences {
    public static let appGroupID = "group.6M3Z27M69P.app.access.keyboard"
    public static let bethModeEnabledKey = "bethModeEnabled"
    public static let letterLayoutKey = "letterLayout"
    public static let colourOptionKey = "colourOption"
    public static let extensionHasFullAccessKey = "extensionHasFullAccess"

    static let legacyKeyColouringKey = "keyColouring"
    static let legacyContrastThemeKey = "contrastTheme"

    private static let darwinName = CFNotificationName("app.access.keyboard.preferencesDidChange" as CFString)

    public static var suite: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static var letterLayout: LetterLayout {
        get { value(LetterLayout.self, key: letterLayoutKey, default: .qwerty) }
        set { set(newValue.rawValue, forKey: letterLayoutKey) }
    }

    public static var colourOption: ColourOption {
        get {
            if let stored = suite.string(forKey: colourOptionKey),
               let value = ColourOption(rawValue: stored) {
                return value
            }
            return migratedColourOption()
        }
        set {
            suite.set(newValue.rawValue, forKey: colourOptionKey)
            suite.set(newValue == .beth, forKey: bethModeEnabledKey)
            notify()
        }
    }

    public static var bethModeEnabled: Bool {
        get { colourOption == .beth }
        set { colourOption = newValue ? .beth : .system }
    }

    public static var extensionHasFullAccess: Bool {
        get { suite.bool(forKey: extensionHasFullAccessKey) }
        set { suite.set(newValue, forKey: extensionHasFullAccessKey) }
    }

    public static func persistMigratedColourOptionIfNeeded() {
        guard suite.string(forKey: colourOptionKey) == nil else { return }
        colourOption = migratedColourOption()
    }

    public static func notify() {
        NotificationCenter.default.post(name: .accessKeyboardPreferencesDidChange, object: nil)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            darwinName,
            nil,
            nil,
            true
        )
    }

    public static func observe(_ handler: @escaping () -> Void) -> KeyboardPreferenceObservation {
        KeyboardPreferenceObservation(handler: handler)
    }

    static func migratedColourOption() -> ColourOption {
        if let contrast = suite.string(forKey: legacyContrastThemeKey) {
            switch contrast {
            case "whiteOnBlack":
                return .highContrastWhite
            case "yellowOnBlack":
                return .highContrastYellow
            case "blackOnWhite", "blackOnYellow":
                return .system
            default:
                break
            }
        }
        if let colouring = suite.string(forKey: legacyKeyColouringKey) {
            switch colouring {
            case "vowels":
                return .vowels
            case "beth":
                return .beth
            default:
                break
            }
        }
        if suite.bool(forKey: bethModeEnabledKey) {
            return .beth
        }
        return .system
    }

    private static func value<T: RawRepresentable>(
        _ type: T.Type,
        key: String,
        default defaultValue: T
    ) -> T where T.RawValue == String {
        guard let raw = suite.string(forKey: key), let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }

    private static func set(_ value: Any, forKey key: String) {
        suite.set(value, forKey: key)
        notify()
    }
}

public final class KeyboardPreferenceObservation {
    private let handler: () -> Void
    private var centerObserver: NSObjectProtocol?
    private let darwinName = CFNotificationName("app.access.keyboard.preferencesDidChange" as CFString)

    init(handler: @escaping () -> Void) {
        self.handler = handler
        centerObserver = NotificationCenter.default.addObserver(
            forName: .accessKeyboardPreferencesDidChange,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let observation = Unmanaged<KeyboardPreferenceObservation>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    observation.handler()
                }
            },
            darwinName.rawValue,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        if let centerObserver {
            NotificationCenter.default.removeObserver(centerObserver)
        }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            darwinName,
            nil
        )
    }
}
