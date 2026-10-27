/// Pure, date-free selection of "today's" plan day. The app converts a calendar
/// date into (week, dayInWeek) and hands those here, so this stays trivially
/// testable and free of Foundation/Calendar.
public enum PlanScheduler {

    /// Parse a phase's `weeks` string ("1-3") into an inclusive range.
    public static func weekRange(_ string: String) -> ClosedRange<Int>? {
        let parts = string.split(separator: "-").map { String($0).filter { !$0.isWhitespace } }
        guard parts.count == 2, let lo = Int(parts[0]), let hi = Int(parts[1]), lo <= hi else { return nil }
        return lo...hi
    }

    /// The phase that contains a given 1-based week, if any.
    public static func phase(in template: PlanTemplate, week: Int) -> PlanPhase? {
        template.phases.first { weekRange($0.weeks)?.contains(week) ?? false }
    }

    /// The phase + day for a 1-based week and 1-based day-of-week, or nil if the
    /// week is past the plan's duration (→ caller shows "plan complete").
    public static func selectDay(in template: PlanTemplate, week: Int, dayInWeek: Int) -> (phase: PlanPhase, day: PlanDay)? {
        guard week >= 1, week <= template.durationWeeks else { return nil }
        for phase in template.phases {
            guard let range = weekRange(phase.weeks), range.contains(week) else { continue }
            if let day = phase.weeklyMicrocycle.first(where: { $0.day == dayInWeek }) {
                return (phase, day)
            }
        }
        return nil
    }
}

public extension PlanDay {
    /// Track-work blocks (those with a rep count) — the volume the readiness
    /// multiplier scales.
    var trackworkBlocks: [PlanBlock] { blocks.filter { $0.reps != nil } }

    /// Warm-up / strength / mobility / rest blocks — shown but never volume-scaled.
    var descriptiveBlocks: [PlanBlock] { blocks.filter { $0.reps == nil } }

    /// Map the track-work into a `PlannedSession` so the existing `SessionScaler`
    /// (and the readiness multiplier) apply unchanged: rep count → `sets`.
    func scalableSession() -> PlannedSession {
        PlannedSession(title: name, blocks: trackworkBlocks.map { block in
            TrainingBlock(
                name: block.scaledDisplayName,
                sets: block.reps ?? 1,
                distanceMeters: block.distanceM.map(Double.init),
                durationSeconds: nil)
        })
    }
}

public extension PlanBlock {
    /// "Accelerations — 30m" style label for the scaled track-work row.
    var scaledDisplayName: String {
        if let d = distanceM { return "\(name) — \(d)m" }
        return name
    }
}
