import Foundation
import SwiftData
import CadenceCore

/// Computes the check-in streak from persisted check-ins. Read-only: it never
/// inserts or deletes, so a sync/HealthKit error can't reset the streak. A day
/// counts toward the streak only once its morning check-in flow is *completed*
/// (`completedAt != nil`) — the flow persists that before any HealthKit work
/// (see CheckInFlowModel.completeCheckIn), so a wearable failure never costs the
/// day. Merely opening the app does not count (a bare `CheckIn` row may exist to
/// hold phone-only inputs, but an incomplete check-in is not a streak day).
///
/// **Streak freeze**: one automatic freeze per calendar month. A single missed
/// day is bridged silently (Today shows "Streak protected — freeze used")
/// instead of zeroing a long streak — the #1 rage-quit in this category.
@MainActor
enum StreakService {

    struct Streak {
        let days: Int
        /// True when a freeze is currently bridging a one-day gap in the run.
        let isProtected: Bool
    }

    static func currentStreak(context: ModelContext, today: Date = .now,
                              defaults: UserDefaults = .standard) -> Streak {
        guard let all = try? context.fetch(FetchDescriptor<CheckIn>()) else {
            return Streak(days: 0, isProtected: false)
        }
        let cal = Calendar.current
        // Only completed check-ins count — opening the app is not a check-in.
        var days = Set(all
            .filter { $0.completedAt != nil }
            .compactMap { cal.ordinality(of: .day, in: .era, for: $0.day) })
        let todayIndex = cal.ordinality(of: .day, in: .era, for: today) ?? 0

        // Previously-consumed freezes stay part of the run.
        let bridged = Set(defaults.array(forKey: Self.bridgedKey) as? [Int] ?? [])
        days.formUnion(bridged)

        var streak = StreakCalculator.currentStreak(checkInDays: days, today: todayIndex)

        // Try to bridge a fresh one-day gap just before the current run: the run
        // must resume on the far side, and that month's freeze must be unused.
        let anchor = days.contains(todayIndex) ? todayIndex : todayIndex - 1
        let gapDay = anchor - streak
        if streak > 0, !days.contains(gapDay), days.contains(gapDay - 1),
           freezeAvailable(forDayIndex: gapDay, bridged: bridged, today: today, todayIndex: todayIndex) {
            defaults.set(Array(bridged.union([gapDay])), forKey: Self.bridgedKey)
            days.insert(gapDay)
            streak = StreakCalculator.currentStreak(checkInDays: days, today: todayIndex)
        }

        let allBridged = Set(defaults.array(forKey: Self.bridgedKey) as? [Int] ?? [])
        let runDays: Set<Int> = streak > 0 ? Set((anchor - streak + 1)...anchor) : []
        return Streak(days: streak, isProtected: !runDays.isDisjoint(with: allBridged))
    }

    // MARK: - Freeze bookkeeping

    private static let bridgedKey = "streak.freeze.bridgedDays"

    /// One freeze per calendar month, judged by the month the *missed* day falls in.
    private static func freezeAvailable(forDayIndex gapDay: Int, bridged: Set<Int>,
                                        today: Date, todayIndex: Int) -> Bool {
        let cal = Calendar.current
        guard let gapDate = cal.date(byAdding: .day, value: gapDay - todayIndex,
                                     to: cal.startOfDay(for: today)) else { return false }
        let gapMonth = cal.dateComponents([.year, .month], from: gapDate)
        return !bridged.contains { index in
            guard let date = cal.date(byAdding: .day, value: index - todayIndex,
                                      to: cal.startOfDay(for: today)) else { return false }
            return cal.dateComponents([.year, .month], from: date) == gapMonth
        }
    }
}
