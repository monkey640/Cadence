/// Pure glue between the personalization engine (which thinks in *weekly reps
/// per quality*) and the plan (which is *reps per block per day*).
///
///  - `baselineWeekly` sums the phase microcycle into the engine's `WeeklyVolume`.
///  - `adjustedReps` reflects an applied per-quality trade onto a single day's
///    block, landing the whole weekly delta exactly once — on the "designated
///    day" (the first microcycle day that trains that quality) — so applying a
///    +1/−1 weekly trade never multiplies across the week.
///
/// Readiness scaling still applies on top of this, daily, unchanged.
public enum PlanPersonalizer {

    /// The engine's current weekly state, derived from the plan phase.
    public static func baselineWeekly(for phase: PlanPhase) -> WeeklyVolume {
        var reps: [Quality: Int] = [:]
        var maxVelocityDays = 0
        var highCNSDays = 0
        for day in phase.weeklyMicrocycle {
            if day.load == .high { highCNSDays += 1 }
            var dayTrainsMaxVelocity = false
            for block in day.blocks {
                guard let quality = block.type?.quality, let reps0 = block.reps else { continue }
                reps[quality, default: 0] += reps0
                if quality == .maxVelocity { dayTrainsMaxVelocity = true }
            }
            if dayTrainsMaxVelocity { maxVelocityDays += 1 }
        }
        return WeeklyVolume(reps: reps, maxVelocitySessions: maxVelocityDays, highCNSSessions: highCNSDays)
    }

    /// First (lowest day number) microcycle day that trains `quality`.
    public static func designatedDay(for quality: Quality, in phase: PlanPhase) -> Int? {
        phase.weeklyMicrocycle.sorted { $0.day < $1.day }
            .first { $0.blocks.contains { $0.type?.quality == quality } }?.day
    }

    /// Rep count for a block after reflecting the applied weekly `deltas`.
    /// Unchanged unless this block's quality has a non-zero delta AND today is
    /// that quality's designated day. Never drops below 1 rep.
    public static func adjustedReps(for block: PlanBlock, dayInWeek: Int,
                                    phase: PlanPhase, deltas: [Quality: Int]) -> Int? {
        guard let reps = block.reps else { return nil }
        guard let quality = block.type?.quality,
              let delta = deltas[quality], delta != 0,
              designatedDay(for: quality, in: phase) == dayInWeek
        else { return reps }
        return Swift.max(1, reps + delta)
    }
}
