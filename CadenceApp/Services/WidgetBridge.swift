import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
import CadenceCore

/// Publishes today's volume/score/verdict to the shared app-group defaults the Home
/// Screen widget reads, and pokes WidgetKit to redraw. Every call is safe when
/// the app group isn't configured yet (the widget target is a manual Xcode
/// step — see CadenceWidgets/README.md); it just no-ops.
enum WidgetBridge {
    static let appGroupID = "group.net.adnanahmad.Cadence"

    enum Key {
        static let day = "widget.day"                 // yyyy-MM-dd the payload is for
        static let score = "widget.score"
        /// Today's volume as a percentage of plan — the number the widget leads
        /// with, matching Today and the check-in reveal.
        static let volume = "widget.volume"
        static let verdict = "widget.verdict"
        static let checkedIn = "widget.checkedIn"
    }

    /// Called after a readiness result lands (check-in flow / Today repair path).
    static func publish(score: Double, verdict: Verdict, multiplier: Double, on date: Date = .now) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(dayString(date), forKey: Key.day)
        defaults.set(score, forKey: Key.score)
        defaults.set((multiplier * 100).rounded(), forKey: Key.volume)
        defaults.set(verdict.rawValue, forKey: Key.verdict)
        defaults.set(true, forKey: Key.checkedIn)
        reload()
    }

    /// Called when a new day starts without a check-in yet, so the widget flips
    /// back to the "Check in" prompt instead of showing yesterday's score.
    static func publishAwaitingCheckIn(on date: Date = .now) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if defaults.string(forKey: Key.day) != dayString(date) {
            defaults.set(dayString(date), forKey: Key.day)
            defaults.set(false, forKey: Key.checkedIn)
            reload()
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
