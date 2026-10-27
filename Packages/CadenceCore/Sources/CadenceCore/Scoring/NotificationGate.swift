import Foundation

/// Enforces the hard cap of **one morning notification per calendar day**,
/// regardless of how many times the background task fires (iOS may run it more
/// than once). Pure and isolated so the cap is unit-tested on its own.
public enum NotificationGate {
    public static func shouldDeliver(now: Date, lastDelivered: Date?, calendar: Calendar = .current) -> Bool {
        guard let lastDelivered else { return true }
        return !calendar.isDate(lastDelivered, inSameDayAs: now)
    }
}
