import Foundation

/// Per-signal 0–100 contributions. `nil` means the signal was unavailable
/// (no reading, or not enough baseline) and was excluded from the composite.
public struct ComponentScores: Equatable, Sendable {
    public let hrv: Double?
    public let sleep: Double?
    public let sleepQuality: Double?
    public let rhr: Double?
    public let respiratoryRate: Double?
    public let wristTemperature: Double?
    public let trainingLoad: Double?
    // Phone-only signals.
    public let wellness: Double?
    public let fingerTap: Double?
    public let countermovementJump: Double?

    public init(hrv: Double?, sleep: Double?, sleepQuality: Double? = nil,
                rhr: Double?, respiratoryRate: Double? = nil, wristTemperature: Double? = nil,
                trainingLoad: Double?,
                wellness: Double? = nil, fingerTap: Double? = nil,
                countermovementJump: Double? = nil) {
        self.hrv = hrv
        self.sleep = sleep
        self.sleepQuality = sleepQuality
        self.rhr = rhr
        self.respiratoryRate = respiratoryRate
        self.wristTemperature = wristTemperature
        self.trainingLoad = trainingLoad
        self.wellness = wellness
        self.fingerTap = fingerTap
        self.countermovementJump = countermovementJump
    }
}

/// The full result of a readiness computation.
public struct ReadinessOutput: Equatable, Sendable {
    /// Composite 0–100.
    public let score: Double
    public let verdict: Verdict
    /// Volume scaler in [minMultiplier, maxMultiplier], applied to the planned session.
    public let volumeMultiplier: Double
    /// One-line, plain-English, positively-framed explanation.
    public let reason: String
    /// How much to trust today's call, given which inputs were present. Lets the
    /// UI temper its tone and nudge toward richer inputs without re-deriving it.
    public let confidence: ReadinessConfidence
    /// True when fewer than `minBaselineDays` of history exist for the anchor signals.
    public let isBaselining: Bool
    /// Days of baseline history the engine had to work with (already computed
    /// internally; surfaced so the UI can show "the app is learning you").
    public let baselineSampleCount: Int
    public let components: ComponentScores

    public init(
        score: Double,
        verdict: Verdict,
        volumeMultiplier: Double,
        reason: String,
        confidence: ReadinessConfidence = .moderate,
        isBaselining: Bool,
        baselineSampleCount: Int,
        components: ComponentScores
    ) {
        self.score = score
        self.verdict = verdict
        self.volumeMultiplier = volumeMultiplier
        self.reason = reason
        self.confidence = confidence
        self.isBaselining = isBaselining
        self.baselineSampleCount = baselineSampleCount
        self.components = components
    }
}
