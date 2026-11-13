import Foundation

/// When the host app may ask StoreKit to show the system rating prompt.
///
/// StoreKit still decides whether a prompt appears (at most a few times a year).
/// This only chooses a moment: the person has opened the app more than once and
/// has typed a real amount, and this version has not asked yet.
public enum ReviewPrompt {
    public static let minimumLaunches = 3
    public static let minimumCharacters = 80

    public static let launchesKey = "reviewPrompt.launchCount"
    public static let charactersKey = "reviewPrompt.charactersTyped"
    public static let versionKey = "reviewPrompt.lastRequestedVersion"

    public static func recordLaunch(in defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: launchesKey) + 1, forKey: launchesKey)
    }

    public static func recordTypedCharacters(_ count: Int, in defaults: UserDefaults = .standard) {
        guard count > 0 else { return }
        defaults.set(defaults.integer(forKey: charactersKey) + count, forKey: charactersKey)
    }

    public static func shouldRequest(currentVersion: String, defaults: UserDefaults = .standard) -> Bool {
        let version = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return false }
        if defaults.string(forKey: versionKey) == version { return false }
        return defaults.integer(forKey: launchesKey) >= minimumLaunches
            && defaults.integer(forKey: charactersKey) >= minimumCharacters
    }

    public static func markRequested(currentVersion: String, defaults: UserDefaults = .standard) {
        let version = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return }
        defaults.set(version, forKey: versionKey)
    }
}
