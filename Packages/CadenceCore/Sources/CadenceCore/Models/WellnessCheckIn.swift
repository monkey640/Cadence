import Foundation

/// A morning subjective wellness check-in — the highest-evidence, lowest-friction
/// readiness input and the one signal that can stand alone when no wearable is
/// present. Five short self-reports on a 1...5 scale, in a uniform
/// **higher-is-better** convention so the engine never has to special-case
/// direction:
///
/// - `sleepRating`   — 5 = slept great / fully rested, 1 = barely slept.
/// - `soreness`      — 5 = no soreness, 1 = very sore.
/// - `fatigue`       — 5 = fresh / full of energy, 1 = exhausted.
/// - `stress`        — 5 = calm / relaxed, 1 = very stressed.
/// - `mood`          — 5 = great mood, 1 = low / irritable.
///
/// The UI may ask these in their natural direction (e.g. "How sore are you?"
/// where 5 = very sore); the app is responsible for flipping such items into
/// this higher-is-better convention before constructing the value. Keeping the
/// model uniform keeps the engine and its tests simple and auditable.
///
/// Self-report is already personally anchored, so — unlike the physiological
/// signals — wellness needs **no rolling baseline** and is usable on day one.
public struct WellnessCheckIn: Equatable, Sendable {
    public let sleepRating: Int
    public let soreness: Int
    public let fatigue: Int
    public let stress: Int
    public let mood: Int

    public init(sleepRating: Int, soreness: Int, fatigue: Int, stress: Int, mood: Int) {
        self.sleepRating = sleepRating
        self.soreness = soreness
        self.fatigue = fatigue
        self.stress = stress
        self.mood = mood
    }

    /// Equal-weight mean of the five items, clamped to the valid 1...5 range so a
    /// malformed input can never push the derived sub-score out of bounds.
    ///
    /// NOTE: equal weighting is a **coach-review-draft** choice. Sports-science
    /// literature suggests fatigue and soreness may be more predictive than mood,
    /// but per-item weights are unvalidated and deliberately deferred.
    public var average: Double {
        let raw = Double(sleepRating + soreness + fatigue + stress + mood) / 5.0
        return Swift.min(5.0, Swift.max(1.0, raw))
    }
}
