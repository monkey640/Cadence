import Foundation

/// How much trust to place in a given day's readiness verdict, based on *which*
/// inputs were available — not how good or bad they were. Surfaced alongside the
/// 0–100 score so the UI can temper how assertively it presents the call and
/// nudge teens toward richer inputs.
///
/// - `high`     — a full wearable picture (HRV + sleep + resting HR all present).
/// - `moderate` — a partial wearable read, or a stand-alone subjective check-in.
///                Trustworthy enough to act on, but the engine caps volume.
/// - `low`      — only low-confidence phone tests (finger-tap / jump) were given,
///                or the engine is still cold-starting. Treated very cautiously.
public enum ReadinessConfidence: String, Equatable, Sendable, CaseIterable {
    case high
    case moderate
    case low

    public var displayName: String {
        switch self {
        case .high:     return "High confidence"
        case .moderate: return "Moderate confidence"
        case .low:      return "Low confidence"
        }
    }
}
