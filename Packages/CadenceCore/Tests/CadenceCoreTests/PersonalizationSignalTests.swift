import XCTest
@testable import CadenceCore

/// End-to-end: logged "faded late" markers + stress flags → mapper →
/// SessionObservation → engine, proving the fade signal and confounder exclusion.
final class PersonalizationSignalTests: XCTestCase {

    // 100m profile: late_race_deceleration is the fade-driven deficiency
    // (ADD that increases speed_endurance, an endurance quality).
    private func ranges() -> AdjustmentRanges {
        let global = GlobalAdjustmentRules(
            weeklyHighCNSSessionCap: 3, maxVelocityWeeklyFloorSessions: 1,
            reduce: EvidenceRuleJSON(minSessionsObserved: 1, maxChangePerWeekReps: nil),
            add: EvidenceRuleJSON(minSessionsObserved: 4, maxChangePerWeekReps: 1))
        let accel = AdjustableQuality(qualityRaw: "acceleration", defaultWeeklyReps: 5, minWeeklyReps: 4, maxWeeklyReps: 7, distanceBand: [10, 40], phases: ["all"], isSpeedFloorRaw: nil)
        let maxVel = AdjustableQuality(qualityRaw: "max_velocity", defaultWeeklyReps: 4, minWeeklyReps: 3, maxWeeklyReps: 6, distanceBand: [20, 30], phases: ["Specific Preparation"], isSpeedFloorRaw: true)
        let se = AdjustableQuality(qualityRaw: "speed_endurance", defaultWeeklyReps: 3, minWeeklyReps: 2, maxWeeklyReps: 4, distanceBand: [60, 120], phases: ["Specific Preparation"], isSpeedFloorRaw: nil)
        let lateRace = Deficiency(name: "late_race_deceleration", plainLanguage: "Fades late.",
            response: BoundedResponse(increase: IncreaseSpec(qualityRaw: "speed_endurance", byReps: 1, upToMax: 4),
                                      offset: OffsetSpec(reduceQualityRaw: "acceleration", byReps: 1, notBelowMin: true),
                                      reduce: nil, evidenceRaw: "ADD rules"))
        let profile = EventAdjustmentProfile(event: "100m", weeklyHighCNSBudget: 3, qualities: [accel, maxVel, se], deficiencies: [lateRace])
        return AdjustmentRanges(meta: RangesMeta(status: "COACH_REVIEW_DRAFT", requiresCoachSignoff: true), globalRules: global, profiles: [profile])
    }
    private var profile: EventAdjustmentProfile { ranges().profile(for: "100m")! }
    private func weekly() -> WeeklyVolume {
        WeeklyVolume(reps: [.acceleration: 5, .maxVelocity: 4, .speedEndurance: 3], maxVelocitySessions: 1, highCNSSessions: 3)
    }

    /// Build N sessions, each with a faded speed-endurance block, with optional flags.
    private func fadedSessions(_ count: Int, stress: Bool = false) -> [SessionObservation] {
        (0..<count).map { _ in
            DeficiencySignalMapper.observation(
                profile: profile, phaseName: "Specific Preparation",
                isLowReadiness: false, flaggedExternalStress: stress,
                completedPrescribedReps: true,
                fadedEnduranceQualities: [.speedEndurance])
        }
    }

    private func evaluate(_ obs: [SessionObservation]) -> PersonalizationResult {
        PersonalizationEngine(ranges: ranges()).evaluate(
            event: "100m", currentPhase: "Specific Preparation", weekly: weekly(),
            observations: obs, readinessTrend: .flat)
    }
    private func surfaces(_ r: PersonalizationResult) -> Bool {
        if case .proposals(let p) = r { return p.contains { $0.deficiency == "late_race_deceleration" } }
        return false
    }

    // MARK: - Mapper

    func testFadedEnduranceMapsToFadeDeficiency() {
        let o = DeficiencySignalMapper.observation(
            profile: profile, phaseName: "Specific Preparation", isLowReadiness: false,
            flaggedExternalStress: false, completedPrescribedReps: true,
            fadedEnduranceQualities: [.speedEndurance])
        XCTAssertTrue(o.observedPatterns.contains("late_race_deceleration"))
    }

    func testHeldPaceProducesNoPattern() {
        let o = DeficiencySignalMapper.observation(
            profile: profile, phaseName: "Specific Preparation", isLowReadiness: false,
            flaggedExternalStress: false, completedPrescribedReps: true,
            fadedEnduranceQualities: [])   // "held pace" → nothing faded
        XCTAssertTrue(o.observedPatterns.isEmpty)
    }

    // MARK: - Detection

    func testConsistentFadeSurfacesDeficiency() {
        XCTAssertTrue(surfaces(evaluate(fadedSessions(4))), "4 qualifying faded sessions should surface the fade deficiency")
    }

    func testSingleFadedRepDoesNotTrigger() {
        XCTAssertFalse(surfaces(evaluate(fadedSessions(1))), "one faded session must not trigger anything")
    }

    func testStressFlaggedSessionsExcludedFromDetection() {
        // All four faded, but all flagged for stress → all excluded → no detection.
        XCTAssertFalse(surfaces(evaluate(fadedSessions(4, stress: true))),
                       "stress-flagged sessions must be excluded like low-readiness days")
    }

    func testStressFlagsDropBelowQualifyingThreshold() {
        // 4 faded total, but 2 stress-flagged → only 2 qualifying → no ADD.
        let obs = fadedSessions(2, stress: true) + fadedSessions(2)
        XCTAssertFalse(surfaces(evaluate(obs)))
    }
}
