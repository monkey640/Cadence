import UIKit

/// One place for every haptic in the app, so intensity stays consistent:
/// slider steps and tap-test taps are light, set completion is medium,
/// the verdict stamp and a PR are heavy/success.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notify = UINotificationFeedbackGenerator()

    /// Slider steps, tap-test taps, small selections.
    static func tick() { light.impactOccurred() }
    /// Logging a set, advancing an exercise.
    static func set() { medium.impactOccurred() }
    /// The verdict stamping in; rest timer hitting zero.
    static func stamp() { heavy.impactOccurred() }
    /// A new PR.
    static func success() { notify.notificationOccurred(.success) }
}
