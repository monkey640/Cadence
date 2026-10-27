/// Computes a one-time STARTING emphasis from the athlete's self-reported focus
/// at onboarding — a single bounded +1/−1 trade within the coach-approved bands,
/// never below a quality's min and never touching the speed-floor quality as the
/// offset. Total weekly load is unchanged (a trade, not an addition).
///
/// This is deliberately separate from the deficiency engine: it's a provisional
/// starting point, refined later by real logged sessions. Returns empty deltas
/// when the focus isn't adjustable for the event or there's no room within bands.
public enum OnboardingEmphasis {

    public static func startingTrade(profile: EventAdjustmentProfile, focus: Quality) -> [Quality: Int] {
        guard let focusQuality = profile.adjustable(focus),
              focusQuality.defaultWeeklyReps + 1 <= focusQuality.maxWeeklyReps else { return [:] }

        // Offset: a non-speed-floor quality (not the focus) that has room above its min.
        // Prefer the one with the most reps to spare.
        let offset = profile.qualities
            .filter { aq in
                guard let q = aq.quality else { return false }
                return q != focus && !aq.isSpeedFloor && aq.defaultWeeklyReps - 1 >= aq.minWeeklyReps
            }
            .max { $0.defaultWeeklyReps < $1.defaultWeeklyReps }

        guard let offset, let offsetQuality = offset.quality else { return [:] }
        return [focus: 1, offsetQuality: -1]
    }
}
