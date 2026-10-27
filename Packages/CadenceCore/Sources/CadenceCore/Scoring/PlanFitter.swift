/// Fits a phase microcycle to the athlete's declared training days per week.
/// Reduce-only and structure-preserving: rest days are untouched; if the athlete
/// trains fewer days than the plan schedules, the lowest-priority sessions (low/
/// tempo before high-CNS) are trimmed to rest — never added, never reshuffled.
///
/// This is initial *plan fit* from a self-reported onboarding answer — deliberately
/// NOT the deficiency engine, which acts only on observed multi-session evidence.
public enum PlanFitter {

    /// Microcycle day numbers that remain training days, given the athlete's
    /// weekly availability AND an optional cap on high-CNS days (experience level).
    /// Keeps high-CNS days first (up to `maxHighDays`), then fills with low days;
    /// trims the rest to recovery. Reduce-only.
    public static func keptTrainingDays(in microcycle: [PlanDay], trainingDays: Int,
                                        maxHighDays: Int = .max) -> Set<Int> {
        let budget = Swift.max(1, trainingDays)
        let highs = microcycle.filter { $0.load == .high }.sorted { $0.day < $1.day }
        let lows = microcycle.filter { $0.load == .low }.sorted { $0.day < $1.day }

        let keptHighCount = Swift.min(maxHighDays, highs.count, budget)
        let remaining = Swift.max(0, budget - keptHighCount)
        let keptLowCount = Swift.min(remaining, lows.count)

        return Set(highs.prefix(keptHighCount).map(\.day))
            .union(lows.prefix(keptLowCount).map(\.day))
    }

    /// True when this scheduled training day is trimmed to rest by the fit.
    public static func isTrimmedToRest(_ day: PlanDay, kept: Set<Int>) -> Bool {
        day.load != .rest && !kept.contains(day.day)
    }
}
