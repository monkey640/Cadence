import Foundation
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Live Activity contract for the rest timer — the countdown on the Lock
/// Screen / Dynamic Island so the athlete never unlocks mid-workout.
///
/// NOTE: the rendering UI lives in the widget extension (see CadenceWidgets/).
/// This file must be a member of BOTH the app target and the widget target.
#if canImport(ActivityKit)
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When this rest began. With `endDate` it lets the system draw the
        /// draining lane bar itself, so it keeps moving while the app sleeps.
        var startDate: Date
        /// The moment rest ends — the system renders the countdown from this.
        var endDate: Date
        var blockName: String
        var setsDone: Int
        var setsTotal: Int
    }

    var sessionTitle: String
    /// The session's verdict (`Verdict.rawValue`), for the accent colour —
    /// fixed for the life of the activity, so it lives in the attributes.
    var verdictRaw: String
}

/// Starts/updates/ends the rest-timer Live Activity, and the rest-end alert
/// that goes with it. Every call is safe when Live Activities or notifications
/// are unavailable or denied — the in-app timer is the source of truth and works
/// regardless.
///
/// The alert is a local notification scheduled for the moment rest ends. It has
/// to be: once the phone is locked iOS suspends the app within seconds, so the
/// in-app sound and haptic never fire — and a phone in a pocket is exactly when
/// the athlete needs telling. In the foreground the app has no notification
/// delegate, so the system doesn't present it and the in-app cue plays alone.
///
/// Only the activity's `id` (Sendable) is stored; `Activity` itself is not
/// Sendable under Swift 6, so update/end re-fetch it from ActivityKit's
/// registry inside the task instead of sending a main-actor reference across.
@MainActor
final class RestTimerActivityController {
    private var activityID: String?
    private static let alertID = "cadence.restEnd"

    /// Asks for notification permission once, at the start of a session — the
    /// moment the reason is obvious. A no-op once the athlete has answered.
    func prepareAlerts() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func start(sessionTitle: String, verdictRaw: String, state: RestTimerAttributes.ContentState) {
        end()
        scheduleAlert(for: state)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Stale exactly when rest ends: the Lock Screen flips to "Go" on its own
        // even if the app is suspended and never gets to call `end()`.
        activityID = (try? Activity.request(
            attributes: RestTimerAttributes(sessionTitle: sessionTitle, verdictRaw: verdictRaw),
            content: .init(state: state, staleDate: state.endDate)))?.id
    }

    func update(state: RestTimerAttributes.ContentState) {
        scheduleAlert(for: state)   // same id, so this replaces the pending one
        guard let id = activityID else { return }
        Task {
            for activity in Activity<RestTimerAttributes>.activities where activity.id == id {
                await activity.update(.init(state: state, staleDate: state.endDate))
            }
        }
    }

    func end() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.alertID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.alertID])
        guard let id = activityID else { return }
        activityID = nil
        Task {
            for activity in Activity<RestTimerAttributes>.activities where activity.id == id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func scheduleAlert(for state: RestTimerAttributes.ContentState) {
        let seconds = state.endDate.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = "Set \(state.setsDone + 1) of \(state.setsTotal) · \(state.blockName)"
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(
            identifier: Self.alertID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}
#else
/// Non-iOS fallback so the model compiles everywhere.
@MainActor
final class RestTimerActivityController {
    func prepareAlerts() {}
    func end() {}
}
#endif
