/// Plan-personalization engine. Pure and UI-free, mirroring `ReadinessEngine`.
/// Given recent (abstracted) session signals it proposes BOUNDED, confirmed-only
/// trades within the coach-approved envelope. Every safety rule in
/// `cadence_adjustment_ranges.json` is enforced here and proven by tests.
///
/// It never mutates anything: `evaluate` returns proposals for the UI to confirm;
/// `apply` is a separate pure step called only after explicit user confirmation.

public enum ReadinessTrend: Sendable { case up, flat, down }

/// Current weekly prescription state the engine reasons about.
public struct WeeklyVolume: Equatable, Sendable {
    public var reps: [Quality: Int]
    public var maxVelocitySessions: Int
    public var highCNSSessions: Int

    public init(reps: [Quality: Int], maxVelocitySessions: Int, highCNSSessions: Int) {
        self.reps = reps
        self.maxVelocitySessions = maxVelocitySessions
        self.highCNSSessions = highCNSSessions
    }
    public var totalHardReps: Int { reps.values.reduce(0, +) }
}

/// One logged session, abstracted for detection. The app maps raw logs
/// (splits/times/completion) → which deficiency signatures appeared and the
/// confounder flags; the engine applies the safety rules to these.
public struct SessionObservation: Sendable {
    public let phaseName: String
    public let isLowReadiness: Bool
    public let isOutlier: Bool
    public let isIllnessOrStress: Bool
    public let completedPrescribedReps: Bool
    public let observedPatterns: Set<String>   // deficiency names present this session

    public init(phaseName: String, isLowReadiness: Bool = false, isOutlier: Bool = false,
                isIllnessOrStress: Bool = false, completedPrescribedReps: Bool = true,
                observedPatterns: Set<String> = []) {
        self.phaseName = phaseName
        self.isLowReadiness = isLowReadiness
        self.isOutlier = isOutlier
        self.isIllnessOrStress = isIllnessOrStress
        self.completedPrescribedReps = completedPrescribedReps
        self.observedPatterns = observedPatterns
    }
    /// The three confounder exclusions from the JSON.
    public var isExcluded: Bool { isLowReadiness || isOutlier || isIllnessOrStress }
}

/// Numeric evidence knobs (tunable). Pattern consistency is numeric here because
/// the JSON expresses it as prose ("3 of the last 4").
public struct EvidenceConfig: Sendable {
    public var addMinSessions: Int
    public var addConsistencyK: Int
    public var addConsistencyN: Int
    public var addMaxRepsPerWeek: Int
    public var reduceMinSessions: Int

    public init(addMinSessions: Int, addConsistencyK: Int, addConsistencyN: Int,
                addMaxRepsPerWeek: Int, reduceMinSessions: Int) {
        self.addMinSessions = addMinSessions
        self.addConsistencyK = addConsistencyK
        self.addConsistencyN = addConsistencyN
        self.addMaxRepsPerWeek = addMaxRepsPerWeek
        self.reduceMinSessions = reduceMinSessions
    }
    /// Pull numbers from the JSON; consistency defaults to 3-of-4 (the prose value).
    public static func from(_ rules: GlobalAdjustmentRules) -> EvidenceConfig {
        EvidenceConfig(
            addMinSessions: rules.add.minSessionsObserved,
            addConsistencyK: 3, addConsistencyN: 4,
            addMaxRepsPerWeek: rules.add.maxChangePerWeekReps ?? 1,
            reduceMinSessions: rules.reduce.minSessionsObserved)
    }
}

public struct QualityChange: Equatable, Sendable {
    public let quality: Quality
    public let deltaReps: Int
    public let resultingReps: Int
}

public struct EvidenceSummary: Sendable {
    public let qualifyingSessions: Int
    public let patternInLastWindow: Int
}

public struct AdjustmentProposal: Sendable {
    public enum Kind: Sendable { case add, reduce }
    public let deficiency: String
    public let plainLanguage: String   // transparency string, verbatim from JSON
    public let kind: Kind
    public let changes: [QualityChange]
    /// INVARIANT: always <= 0 (trades only; total weekly hard volume never rises).
    public let netRepChange: Int
    public let evidence: EvidenceSummary
}

public enum PersonalizationResult: Sendable {
    case disabled(reason: String)   // no profile for event (e.g. 800m), or flag off upstream
    case noChange                   // nothing detected, or insufficient / blacked-out evidence
    case proposals([AdjustmentProposal])
}

// MARK: - Engine

public struct PersonalizationEngine: Sendable {
    public let ranges: AdjustmentRanges
    public let config: EvidenceConfig

    public init(ranges: AdjustmentRanges, config: EvidenceConfig? = nil) {
        self.ranges = ranges
        self.config = config ?? EvidenceConfig.from(ranges.globalRules)
    }

    public func evaluate(
        event: String,
        currentPhase: String,
        weekly: WeeklyVolume,
        observations: [SessionObservation],   // chronological, oldest → newest
        readinessTrend: ReadinessTrend
    ) -> PersonalizationResult {
        guard let profile = ranges.profile(for: event) else {
            return .disabled(reason: "No personalization profile for \(event).")
        }
        let detector = DeficiencyDetector(profile: profile, config: config)
        let planner = AdjustmentPlanner(profile: profile, global: ranges.globalRules, config: config)

        let detected = detector.detect(observations: observations, readinessTrend: readinessTrend)
        let proposals = detected.compactMap {
            planner.proposal(for: $0, weekly: weekly, currentPhase: currentPhase, readinessTrend: readinessTrend)
        }
        return proposals.isEmpty ? .noChange : .proposals(proposals)
    }

    /// Pure application of a confirmed proposal. Caller invokes only after the
    /// user explicitly confirms. Never changes session counts (rep trades only).
    public func apply(_ proposal: AdjustmentProposal, to weekly: WeeklyVolume) -> WeeklyVolume {
        var updated = weekly
        for change in proposal.changes {
            updated.reps[change.quality] = change.resultingReps
        }
        return updated
    }
}

// MARK: - Detection

struct DetectedDeficiency {
    let deficiency: Deficiency
    let evidence: EvidenceSummary
}

struct DeficiencyDetector {
    let profile: EventAdjustmentProfile
    let config: EvidenceConfig

    func detect(observations: [SessionObservation], readinessTrend: ReadinessTrend) -> [DetectedDeficiency] {
        let qualifying = observations.filter { !$0.isExcluded }   // confounder exclusion
        var detected: [DetectedDeficiency] = []

        for deficiency in profile.deficiencies {
            if deficiency.response.usesAddRules {
                // ADD: full evidence — enough qualifying sessions AND consistency in the last window.
                guard qualifying.count >= config.addMinSessions else { continue }
                let window = Array(qualifying.suffix(config.addConsistencyN))
                let present = window.filter { $0.observedPatterns.contains(deficiency.name) }.count
                guard present >= config.addConsistencyK else { continue }
                detected.append(DetectedDeficiency(
                    deficiency: deficiency,
                    evidence: EvidenceSummary(qualifyingSessions: qualifying.count, patternInLastWindow: present)))
            } else {
                // REDUCE: low evidence — declining readiness, repeated incompletes,
                // or the pattern seen at least the (small) REDUCE minimum.
                let incompletes = qualifying.suffix(3).filter { !$0.completedPrescribedReps }.count
                let patternCount = qualifying.filter { $0.observedPatterns.contains(deficiency.name) }.count
                let trigger = readinessTrend == .down
                    || incompletes >= 2
                    || patternCount >= config.reduceMinSessions
                if trigger {
                    detected.append(DetectedDeficiency(
                        deficiency: deficiency,
                        evidence: EvidenceSummary(qualifyingSessions: qualifying.count, patternInLastWindow: patternCount)))
                }
            }
        }
        return detected
    }
}

// MARK: - Bounded adjustment planning

struct AdjustmentPlanner {
    let profile: EventAdjustmentProfile
    let global: GlobalAdjustmentRules
    let config: EvidenceConfig

    func proposal(for detected: DetectedDeficiency, weekly: WeeklyVolume,
                  currentPhase: String, readinessTrend: ReadinessTrend) -> AdjustmentProposal? {
        let response = detected.deficiency.response
        return response.usesAddRules
            ? addProposal(detected, response, weekly: weekly, currentPhase: currentPhase, readinessTrend: readinessTrend)
            : reduceProposal(detected, response, weekly: weekly)
    }

    // ADD: a bounded +1/−1 trade. Blacked out during Competition/Taper or when
    // readiness is declining. Respects bands and the max-velocity floor.
    private func addProposal(_ detected: DetectedDeficiency, _ response: BoundedResponse,
                             weekly: WeeklyVolume, currentPhase: String, readinessTrend: ReadinessTrend) -> AdjustmentProposal? {
        if isCompetitionTaper(currentPhase) || readinessTrend == .down { return nil }   // blackout

        guard let inc = response.increase, let off = response.offset,
              let incQ = inc.quality, let offQ = off.quality,
              let incAQ = profile.adjustable(incQ), let offAQ = profile.adjustable(offQ) else { return nil }

        let step = min(inc.byReps, off.byReps, config.addMaxRepsPerWeek)   // never more than 1 rep/week
        guard step > 0 else { return nil }

        let curInc = weekly.reps[incQ] ?? incAQ.defaultWeeklyReps
        let curOff = weekly.reps[offQ] ?? offAQ.defaultWeeklyReps

        // Increase ceiling: the quality's max band AND the deficiency's up_to_max.
        let incCeiling = min(incAQ.maxWeeklyReps, inc.upToMax)
        guard curInc + step <= incCeiling else { return nil }

        // Offset floor: never below the quality's min; and never reduce the
        // speed-floor quality below its min (which keeps the >=1 max-velocity session).
        let offFloor = offAQ.minWeeklyReps
        guard curOff - step >= offFloor else { return nil }
        if offAQ.isSpeedFloor && (curOff - step) < global.maxVelocityWeeklyFloorSessions { return nil }

        let changes = [
            QualityChange(quality: incQ, deltaReps: step, resultingReps: curInc + step),
            QualityChange(quality: offQ, deltaReps: -step, resultingReps: curOff - step),
        ]
        return AdjustmentProposal(
            deficiency: detected.deficiency.name, plainLanguage: detected.deficiency.plainLanguage,
            kind: .add, changes: changes, netRepChange: 0, evidence: detected.evidence)
    }

    // REDUCE: trim one rep from the hardest NON-speed-floor quality (or SE2 first),
    // never below its min. Speed-floor qualities are never the reduce target, so
    // the max-velocity floor is structurally protected.
    private func reduceProposal(_ detected: DetectedDeficiency, _ response: BoundedResponse,
                                weekly: WeeklyVolume) -> AdjustmentProposal? {
        guard let target = chooseReduceTarget(response.reduce, weekly: weekly),
              let aq = profile.adjustable(target) else { return nil }
        let cur = weekly.reps[target] ?? aq.defaultWeeklyReps
        guard cur - 1 >= aq.minWeeklyReps else { return nil }   // never below min
        let changes = [QualityChange(quality: target, deltaReps: -1, resultingReps: cur - 1)]
        return AdjustmentProposal(
            deficiency: detected.deficiency.name, plainLanguage: detected.deficiency.plainLanguage,
            kind: .reduce, changes: changes, netRepChange: -1, evidence: detected.evidence)
    }

    private func chooseReduceTarget(_ spec: ReduceSpec?, weekly: WeeklyVolume) -> Quality? {
        // Candidates exclude speed-floor qualities → speed is never sacrificed to recover.
        let candidates = profile.qualities
            .filter { !$0.isSpeedFloor }
            .compactMap { $0.quality }
        if let spec, spec.qualityRaw.contains("special_endurance_2"), candidates.contains(.specialEndurance2) {
            return .specialEndurance2
        }
        // Otherwise trim the hardest (highest current reps) candidate.
        return candidates.max { (weekly.reps[$0] ?? 0) < (weekly.reps[$1] ?? 0) }
    }

    private func isCompetitionTaper(_ phase: String) -> Bool {
        phase.lowercased().contains("competition") || phase.lowercased().contains("taper")
    }
}
