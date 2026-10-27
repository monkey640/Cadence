import Foundation

/// Everything the engine needs for one morning's verdict. All physiological
/// values are optional so missing-data and cold-start cases are first-class,
/// not special-cased at the call site.
public struct ReadinessInput: Sendable {
    public let date: Date

    /// Today's HRV (SDNN, milliseconds) and its rolling baseline.
    public let hrvSDNN: Double?
    public let hrvBaseline: Baseline?

    /// Last night's total *asleep* time (seconds) and its rolling baseline.
    public let sleepSeconds: Double?
    public let sleepBaseline: Baseline?

    /// Last night's deep + REM ("quality") sleep (seconds) and its rolling baseline.
    public let sleepQualitySeconds: Double?
    public let sleepQualityBaseline: Baseline?

    /// Today's resting heart rate (bpm) and its rolling baseline.
    public let restingHR: Double?
    public let rhrBaseline: Baseline?

    /// Overnight respiratory rate (breaths/min) and baseline. Lower = better (inverted).
    public let respiratoryRate: Double?
    public let respiratoryRateBaseline: Baseline?

    /// Sleeping wrist temperature (°C) and baseline. Deviation either way = worse.
    public let wristTemperature: Double?
    public let wristTemperatureBaseline: Baseline?

    /// Acute:chronic training-load ratio (7-day load ÷ 28-day average load).
    /// 1.0 = balanced; >1 = recent overreaching; nil = unknown.
    public let loadRatio: Double?

    // MARK: - Phone-only signals (no wearable required)
    //
    // These let Cadence work for teens without a watch, treating wearable data as
    // a premium layer rather than a gate. All optional, all degrade gracefully.

    /// Today's subjective wellness check-in. The highest-evidence phone input;
    /// usable on day one with no baseline, and able to anchor the verdict alone.
    public let wellness: WellnessCheckIn?

    /// CNS finger-tap test: total taps over 3×10s, scored against a short personal
    /// baseline (higher = fresher). A low-confidence central-fatigue flag.
    public let fingerTapCount: Double?
    public let fingerTapBaseline: Baseline?

    /// Phone-camera countermovement jump height (cm) vs a personal baseline
    /// (higher = better). A neuromuscular-fatigue signal.
    public let countermovementJumpCm: Double?
    public let cmjBaseline: Baseline?

    public init(
        date: Date,
        hrvSDNN: Double?,
        hrvBaseline: Baseline?,
        sleepSeconds: Double?,
        sleepBaseline: Baseline?,
        sleepQualitySeconds: Double? = nil,
        sleepQualityBaseline: Baseline? = nil,
        restingHR: Double?,
        rhrBaseline: Baseline?,
        respiratoryRate: Double? = nil,
        respiratoryRateBaseline: Baseline? = nil,
        wristTemperature: Double? = nil,
        wristTemperatureBaseline: Baseline? = nil,
        loadRatio: Double?,
        wellness: WellnessCheckIn? = nil,
        fingerTapCount: Double? = nil,
        fingerTapBaseline: Baseline? = nil,
        countermovementJumpCm: Double? = nil,
        cmjBaseline: Baseline? = nil
    ) {
        self.date = date
        self.hrvSDNN = hrvSDNN
        self.hrvBaseline = hrvBaseline
        self.sleepSeconds = sleepSeconds
        self.sleepBaseline = sleepBaseline
        self.sleepQualitySeconds = sleepQualitySeconds
        self.sleepQualityBaseline = sleepQualityBaseline
        self.restingHR = restingHR
        self.rhrBaseline = rhrBaseline
        self.respiratoryRate = respiratoryRate
        self.respiratoryRateBaseline = respiratoryRateBaseline
        self.wristTemperature = wristTemperature
        self.wristTemperatureBaseline = wristTemperatureBaseline
        self.loadRatio = loadRatio
        self.wellness = wellness
        self.fingerTapCount = fingerTapCount
        self.fingerTapBaseline = fingerTapBaseline
        self.countermovementJumpCm = countermovementJumpCm
        self.cmjBaseline = cmjBaseline
    }
}
