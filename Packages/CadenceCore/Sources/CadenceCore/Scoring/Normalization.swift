import Foundation

/// Pure normalization helpers shared by the scorers. Kept free of any
/// HealthKit / UI types so every mapping is trivially unit-testable.
public enum Normalization {

    public static func clamp(_ value: Double, min lo: Double, max hi: Double) -> Double {
        Swift.min(hi, Swift.max(lo, value))
    }

    /// Map a z-score to a 0–100 sub-score: neutral at z = 0, rising with z.
    /// `subscore = neutral + z · pointsPerSigma`, clamped to [0, 100].
    public static func subscore(fromZ z: Double, config: ReadinessConfig) -> Double {
        clamp(config.neutralScore + z * config.pointsPerSigma, min: 0, max: 100)
    }

    /// Same as `subscore(fromZ:)` but inverted — for signals where *lower is
    /// better* (resting heart rate, respiratory rate). A below-baseline value scores high.
    public static func invertedSubscore(fromZ z: Double, config: ReadinessConfig) -> Double {
        clamp(config.neutralScore - z * config.pointsPerSigma, min: 0, max: 100)
    }

    /// Symmetric deviation penalty — for signals where *being at baseline is good*
    /// and a deviation in EITHER direction is bad (wrist temperature). At baseline
    /// it scores neutral; the score falls as |z| grows.
    public static func deviationSubscore(fromZ z: Double, config: ReadinessConfig) -> Double {
        clamp(config.neutralScore - abs(z) * config.pointsPerSigma, min: 0, max: 100)
    }

    /// Training-load sub-score from an acute:chronic ratio.
    /// Monotonic and bounded: ratio ≤ 1 scores 100 (rested), and every unit of
    /// overreaching above 1.0 subtracts 150 points, so ratio 1.33 ≈ 50, ≥1.67 = 0.
    public static func loadSubscore(fromRatio ratio: Double) -> Double {
        clamp(100 - Swift.max(0, ratio - 1.0) * 150, min: 0, max: 100)
    }

    /// Map a subjective wellness average (1...5, higher = better) to a 0–100
    /// sub-score. Anchored and baseline-free so it works on day one, and
    /// asymmetric about the neutral rating: each level *below* neutral costs more
    /// than each level *above* gains (anti-overtraining bias). With the standard
    /// config (neutral 3 → 72, up 11.5, down 24): 5 → 95, 4 → 83.5, 3 → 72,
    /// 2 → 48, 1 → 24.
    public static func wellnessSubscore(fromAverage avg: Double, config: ReadinessConfig) -> Double {
        let delta = avg - config.wellnessNeutralRating
        let raw = delta >= 0
            ? config.neutralScore + delta * config.wellnessUpPointsPerLevel
            : config.neutralScore + delta * config.wellnessDownPointsPerLevel
        return clamp(raw, min: 0, max: 100)
    }

    /// Map a 0–100 composite to a volume multiplier via the approved linear curve:
    /// `multiplier = minMult + (score/100) · (maxMult − minMult)`.
    public static func multiplier(fromScore score: Double, config: ReadinessConfig) -> Double {
        let span = config.maxMultiplier - config.minMultiplier
        return config.minMultiplier + (clamp(score, min: 0, max: 100) / 100) * span
    }
}
