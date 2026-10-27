import Foundation

/// All tunable constants for the readiness algorithm in one place,
/// so the curve can be adjusted without touching the engine logic.
public struct ReadinessConfig: Sendable {

    // Signal weights. These are *relative* importances: the engine re-normalizes
    // over whichever signals are present on a given day, so their absolute sum is
    // immaterial and need not equal 1.0. (The original seven were tuned to sum to
    // 1.0; the phone-only additions below break that sum on purpose.)
    public let hrvWeight: Double
    public let sleepWeight: Double          // sleep DURATION
    public let sleepQualityWeight: Double   // deep + REM minutes
    public let rhrWeight: Double
    public let respiratoryRateWeight: Double
    public let wristTempWeight: Double
    public let loadWeight: Double

    // MARK: - Phone-only signal weights — DRAFT, COACH-REVIEW-PENDING
    //
    // ⚠️ UNVALIDATED. These three weights are first-pass placeholders, not tuned
    // numbers. `phoneSignalWeightsAreDraft` is true so the UI can surface a
    // "draft" notice. Order of magnitude reflects the evidence hierarchy:
    // subjective wellness is the strongest non-instrumented readiness predictor,
    // the jump is a moderate neuromuscular proxy, the finger-tap is weakest.
    public let wellnessWeight: Double       // DRAFT
    public let cmjWeight: Double            // DRAFT
    public let fingerTapWeight: Double      // DRAFT
    public let phoneSignalWeightsAreDraft: Bool

    /// Sub-score points awarded per standard deviation from baseline.
    /// 20 means a +2.5σ reading saturates at 100 and −2.5σ floors at 0.
    public let pointsPerSigma: Double

    /// The sub-score assigned at exactly baseline (z = 0). Centered at 72 (not 50)
    /// so a typical day reads as "normal/Push" and only below-baseline signals pull
    /// toward Hold/Back-off. Downside has more room (72 pts) than upside (28 pts),
    /// which is intentional: this is an anti-overtraining tool, not a hype meter.
    public let neutralScore: Double

    /// Days of history required before a signal is trusted for a confident verdict.
    public let minBaselineDays: Int

    /// Volume multiplier bounds. The floor is a brand guardrail: never zero.
    public let minMultiplier: Double
    public let maxMultiplier: Double

    /// Verdict thresholds, expressed on the multiplier (per the brief).
    public let pushMultiplierThreshold: Double   // ≥ this → push
    public let holdMultiplierThreshold: Double   // ≥ this (and < push) → hold; else back off

    /// Conservative cap applied while still building a baseline, when a core
    /// physiological signal is missing, or when available signals conflict —
    /// prevents a confident "push". This is the ceiling for a *moderate*-
    /// confidence day.
    public let conservativeMultiplierCap: Double

    /// Tighter cap for a *low*-confidence day: only the weak phone tests
    /// (finger-tap / jump) were provided, with no wearable and no check-in. Such
    /// a day can still pull readiness *down* (a red flag holds you back), but is
    /// never allowed to green-light a hard session.
    public let lowConfidenceMultiplierCap: Double

    /// Sub-score spread (max − min, in points) among the recovery signals above
    /// which the day is treated as "conflicting." A real divergence (≈1.5σ
    /// between two signals) demotes confidence and applies the conservative cap.
    /// Training load is excluded from this check — it sits high when rested by
    /// design, so it isn't a genuine conflict with the recovery signals.
    public let conflictDispersionThreshold: Double

    // MARK: - Subjective wellness mapping (1...5 average → sub-score)
    //
    // Anchored, baseline-free, and intentionally asymmetric: feeling worse than
    // neutral costs more sub-score per level than feeling better gains, matching
    // the engine's anti-overtraining bias. At the neutral rating the sub-score is
    // `neutralScore`; `5.0` → ~95, `1.0` → ~24 with the defaults below.
    public let wellnessNeutralRating: Double
    public let wellnessUpPointsPerLevel: Double     // DRAFT
    public let wellnessDownPointsPerLevel: Double    // DRAFT

    /// Sub-score used for training load when no load data is available.
    /// Deliberately below neutral-high so missing load can't inflate readiness.
    public let defaultLoadSubscore: Double

    /// A today-reading whose |z-score| exceeds this is treated as a sensor error
    /// and the signal is dropped (→ conservative cap, never a confident verdict).
    /// 5σ is astronomically rare for real physiology, so legitimate good/bad days
    /// (which sit within ±3σ) are unaffected.
    public let outlierZThreshold: Double

    public init(
        hrvWeight: Double = 0.35,
        sleepWeight: Double = 0.15,
        sleepQualityWeight: Double = 0.15,
        rhrWeight: Double = 0.12,
        respiratoryRateWeight: Double = 0.08,
        wristTempWeight: Double = 0.07,
        loadWeight: Double = 0.08,
        wellnessWeight: Double = 0.30,          // DRAFT
        cmjWeight: Double = 0.12,               // DRAFT
        fingerTapWeight: Double = 0.06,         // DRAFT
        phoneSignalWeightsAreDraft: Bool = true,
        pointsPerSigma: Double = 20,
        neutralScore: Double = 72,
        minBaselineDays: Int = 7,
        minMultiplier: Double = 0.5,
        maxMultiplier: Double = 1.0,
        pushMultiplierThreshold: Double = 0.83,
        holdMultiplierThreshold: Double = 0.70,
        conservativeMultiplierCap: Double = 0.80,
        lowConfidenceMultiplierCap: Double = 0.70,
        conflictDispersionThreshold: Double = 30,
        wellnessNeutralRating: Double = 3.0,
        wellnessUpPointsPerLevel: Double = 11.5,    // DRAFT
        wellnessDownPointsPerLevel: Double = 24.0,  // DRAFT
        defaultLoadSubscore: Double = 75,
        outlierZThreshold: Double = 5.0
    ) {
        self.hrvWeight = hrvWeight
        self.sleepWeight = sleepWeight
        self.sleepQualityWeight = sleepQualityWeight
        self.rhrWeight = rhrWeight
        self.respiratoryRateWeight = respiratoryRateWeight
        self.wristTempWeight = wristTempWeight
        self.loadWeight = loadWeight
        self.wellnessWeight = wellnessWeight
        self.cmjWeight = cmjWeight
        self.fingerTapWeight = fingerTapWeight
        self.phoneSignalWeightsAreDraft = phoneSignalWeightsAreDraft
        self.pointsPerSigma = pointsPerSigma
        self.neutralScore = neutralScore
        self.minBaselineDays = minBaselineDays
        self.minMultiplier = minMultiplier
        self.maxMultiplier = maxMultiplier
        self.pushMultiplierThreshold = pushMultiplierThreshold
        self.holdMultiplierThreshold = holdMultiplierThreshold
        self.conservativeMultiplierCap = conservativeMultiplierCap
        self.lowConfidenceMultiplierCap = lowConfidenceMultiplierCap
        self.conflictDispersionThreshold = conflictDispersionThreshold
        self.wellnessNeutralRating = wellnessNeutralRating
        self.wellnessUpPointsPerLevel = wellnessUpPointsPerLevel
        self.wellnessDownPointsPerLevel = wellnessDownPointsPerLevel
        self.defaultLoadSubscore = defaultLoadSubscore
        self.outlierZThreshold = outlierZThreshold
        // Weights are re-normalized over present signals, so they need not sum to
        // 1.0 — but every weight must be a positive, finite contribution.
        assert([hrvWeight, sleepWeight, sleepQualityWeight, rhrWeight,
                respiratoryRateWeight, wristTempWeight, loadWeight,
                wellnessWeight, cmjWeight, fingerTapWeight]
                .allSatisfy { $0 > 0 && $0.isFinite },
               "Every signal weight must be positive and finite")
    }

    public static let standard = ReadinessConfig()
}
