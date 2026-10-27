import Foundation

/// The readiness algorithm. No UI, no HealthKit, no persistence — give it a
/// `ReadinessInput`, get a `ReadinessOutput`. This is the testable heart of
/// the app and the thing that makes Cadence "genuine on-device processing."
public struct ReadinessEngine: Sendable {

    public let config: ReadinessConfig

    public init(config: ReadinessConfig = .standard) {
        self.config = config
    }

    /// One signal's contribution after availability is resolved.
    private struct Signal {
        let subscore: Double
        let weight: Double
    }

    /// How a signal's z-score maps to a sub-score.
    private enum Mode { case standard, inverted, deviation }

    public func evaluate(_ input: ReadinessInput) -> ReadinessOutput {
        // --- Core physiological signals (drive cold-start + the conservative cap)
        let hrv = signal(value: input.hrvSDNN, baseline: input.hrvBaseline,
                         weight: config.hrvWeight, mode: .standard)
        let sleep = signal(value: input.sleepSeconds, baseline: input.sleepBaseline,
                           weight: config.sleepWeight, mode: .standard)
        let rhr = signal(value: input.restingHR, baseline: input.rhrBaseline,
                         weight: config.rhrWeight, mode: .inverted)

        // --- Optional overnight signals (contribute when present; their absence
        // never trips the missing-core cap, so missing hardware isn't penalized).
        let sleepQuality = signal(value: input.sleepQualitySeconds, baseline: input.sleepQualityBaseline,
                                  weight: config.sleepQualityWeight, mode: .standard)
        let respiratory = signal(value: input.respiratoryRate, baseline: input.respiratoryRateBaseline,
                                 weight: config.respiratoryRateWeight, mode: .inverted)
        let wristTemp = signal(value: input.wristTemperature, baseline: input.wristTemperatureBaseline,
                               weight: config.wristTempWeight, mode: .deviation)

        // --- Phone-only signals (let the app work without a wearable) --------
        // Subjective wellness is anchored & baseline-free, so it's usable day one
        // and can stand alone as the primary signal.
        let wellnessSub = input.wellness.map {
            Normalization.wellnessSubscore(fromAverage: $0.average, config: config)
        }
        let wellness = wellnessSub.map { Signal(subscore: $0, weight: config.wellnessWeight) }
        // Finger-tap and jump are baseline-relative performance tests (higher is
        // better), so they reuse the z-scored path and drop out until they have a
        // personal baseline.
        let tap = signal(value: input.fingerTapCount, baseline: input.fingerTapBaseline,
                         weight: config.fingerTapWeight, mode: .standard)
        let cmj = signal(value: input.countermovementJumpCm, baseline: input.cmjBaseline,
                         weight: config.cmjWeight, mode: .standard)

        // Training load always contributes: real ratio if known, else a neutral default.
        let loadSub = input.loadRatio.map(Normalization.loadSubscore(fromRatio:))
            ?? config.defaultLoadSubscore
        let load = Signal(subscore: loadSub, weight: config.loadWeight)

        let core = [hrv, sleep, rhr].compactMap { $0 }
        // Every signal that produced a sub-score this morning, plus load.
        let recovery = [hrv, sleep, rhr, sleepQuality, respiratory, wristTemp,
                        wellness, tap, cmj].compactMap { $0 }
        let available = recovery + [load]

        // --- Confidence inputs ----------------------------------------------
        let wearablePresent = [hrv, sleep, rhr, sleepQuality, respiratory, wristTemp]
            .contains { $0 != nil }
        // Only the weak phone tests are present — no wearable, no check-in.
        let phoneTestOnly = !wearablePresent && wellness == nil && (tap != nil || cmj != nil)

        // --- Cold start --------------------------------------------------------
        // "Baselining" means we lack the history to score the metrics that need a
        // baseline AND have no baseline-free anchor (the wellness check-in) to fall
        // back on. So a phone-only teen doing a daily check-in is never stuck in a
        // perpetual "building baseline" state.
        let bestSampleCount = [
            input.hrvBaseline, input.sleepBaseline, input.rhrBaseline,
            input.sleepQualityBaseline, input.respiratoryRateBaseline,
            input.wristTemperatureBaseline, input.fingerTapBaseline, input.cmjBaseline,
        ].compactMap { $0?.sampleCount }.max() ?? 0
        let isBaselining = bestSampleCount < config.minBaselineDays && input.wellness == nil

        // --- Composite via re-normalized weights over available signals ------
        let totalWeight = available.reduce(0) { $0 + $1.weight }
        let composite: Double = totalWeight > 0
            ? available.reduce(0) { $0 + $1.subscore * $1.weight } / totalWeight
            : config.neutralScore

        // --- Conflict: do the recovery signals genuinely disagree? -----------
        // Load is excluded — it sits high when rested by design, so it isn't a
        // real conflict with the recovery picture.
        let recoverySubs = recovery.map(\.subscore)
        let conflict = recoverySubs.count >= 2
            && (recoverySubs.max()! - recoverySubs.min()!) > config.conflictDispersionThreshold

        // --- Multiplier, with a ladder of conservative caps ------------------
        var multiplier = Normalization.multiplier(fromScore: composite, config: config)
        let missingCoreSignal = core.count < 3
        // Moderate ceiling: cold-start, an incomplete wearable picture, or conflict.
        if isBaselining || missingCoreSignal || conflict {
            multiplier = min(multiplier, config.conservativeMultiplierCap)
        }
        // Tighter ceiling: only weak phone tests were available.
        if phoneTestOnly {
            multiplier = min(multiplier, config.lowConfidenceMultiplierCap)
        }
        multiplier = Normalization.clamp(multiplier, min: config.minMultiplier, max: config.maxMultiplier)

        // --- Confidence level (reporting) ------------------------------------
        let confidence: ReadinessConfidence
        if isBaselining || phoneTestOnly || recovery.isEmpty {
            confidence = .low
        } else if core.count == 3 && !conflict {
            confidence = .high
        } else {
            confidence = .moderate
        }

        let verdict = verdict(for: multiplier)
        // A push day means the whole session — so it scales to full volume, not
        // the 0.83–1.0 the curve happens to land on. Safe by construction: both
        // conservative caps (0.80 / 0.70) sit below the push threshold (0.83), so
        // a capped day is never a push and this can't lift a capped multiplier.
        if verdict == .push { multiplier = config.maxMultiplier }
        let components = ComponentScores(
            hrv: hrv?.subscore, sleep: sleep?.subscore, sleepQuality: sleepQuality?.subscore,
            rhr: rhr?.subscore, respiratoryRate: respiratory?.subscore,
            wristTemperature: wristTemp?.subscore, trainingLoad: load.subscore,
            wellness: wellness?.subscore, fingerTap: tap?.subscore,
            countermovementJump: cmj?.subscore)
        let reason = ReasonBuilder.reason(
            verdict: verdict, isBaselining: isBaselining,
            missingCoreSignal: missingCoreSignal, confidence: confidence,
            conflict: conflict, phoneTestOnly: phoneTestOnly,
            wearablePresent: wearablePresent, components: components)

        return ReadinessOutput(
            score: composite, verdict: verdict, volumeMultiplier: multiplier,
            reason: reason, confidence: confidence, isBaselining: isBaselining,
            baselineSampleCount: bestSampleCount, components: components)
    }

    // MARK: - Helpers

    private func signal(value: Double?, baseline: Baseline?, weight: Double, mode: Mode) -> Signal? {
        guard let value, let baseline, baseline.sampleCount >= config.minBaselineDays
        else { return nil }
        let z = baseline.zScore(for: value)
        // Outlier rejection: an implausibly far reading is almost certainly a
        // sensor error — drop it rather than let it clamp to a confident 0/100.
        guard abs(z) <= config.outlierZThreshold else { return nil }
        let sub: Double
        switch mode {
        case .standard:  sub = Normalization.subscore(fromZ: z, config: config)
        case .inverted:  sub = Normalization.invertedSubscore(fromZ: z, config: config)
        case .deviation: sub = Normalization.deviationSubscore(fromZ: z, config: config)
        }
        return Signal(subscore: sub, weight: weight)
    }

    private func verdict(for multiplier: Double) -> Verdict {
        if multiplier >= config.pushMultiplierThreshold { return .push }
        if multiplier >= config.holdMultiplierThreshold { return .hold }
        return .backOff
    }
}
