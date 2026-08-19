import Foundation

public extension Notification.Name {
    static let accessKeyboardPreferencesDidChange = Notification.Name("accessKeyboardPreferencesDidChange")
}

public enum KeyboardPreferences {
    public static let appGroupID = "group.6M3Z27M69P.app.access.keyboard"
    public static let bethModeEnabledKey = "bethModeEnabled"
    public static let extensionHasFullAccessKey = "extensionHasFullAccess"

    private static let darwinName = CFNotificationName("app.access.keyboard.preferencesDidChange" as CFString)

    public static var suite: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static var bethModeEnabled: Bool {
        get { suite.bool(forKey: bethModeEnabledKey) }
        set {
            suite.set(newValue, forKey: bethModeEnabledKey)
            notify()
        }
    }

    public static var extensionHasFullAccess: Bool {
        get { suite.bool(forKey: extensionHasFullAccessKey) }
        set { suite.set(newValue, forKey: extensionHasFullAccessKey) }
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
