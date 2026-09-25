import Foundation

/// Build-time switches for App Store submission.
///
/// Change the constants in this file and ship a new build. They are not
/// runtime preferences. See README → Feature flags.
public enum FeatureFlags {
    /// When `true` (the default), the first Fix call waits for Allow.
    /// Set to `false` to send on Fix without that step.
    public static let fixConsentRequired = true
}
