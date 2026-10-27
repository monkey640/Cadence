import XCTest
@testable import CadenceCore

final class PersonalizationEngineTests: XCTestCase {

    // MARK: - Fixtures (a 100m profile mirroring cadence_adjustment_ranges.json)

    private func ranges(reduceTargetsMaxVelocity: Bool = false) -> AdjustmentRanges {
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
        let weakTop = Deficiency(name: "weak_top_speed", plainLanguage: "Top speed lags.",
            response: BoundedResponse(increase: IncreaseSpec(qualityRaw: "max_velocity", byReps: 1, upToMax: 6),
                                      offset: OffsetSpec(reduceQualityRaw: "speed_endurance", byReps: 1, notBelowMin: true),
                                      reduce: nil, evidenceRaw: "ADD rules"))
        // Variant used only to exercise the max-velocity floor guard directly.
        let speedTradeTest = Deficiency(name: "floor_probe", plainLanguage: "probe",
            response: BoundedResponse(increase: IncreaseSpec(qualityRaw: "acceleration", byReps: 1, upToMax: 7),
                                      offset: OffsetSpec(reduceQualityRaw: "max_velocity", byReps: 1, notBelowMin: true),
                                      reduce: nil, evidenceRaw: "ADD rules"))
        let chronic = Deficiency(name: "chronic_underrecovery", plainLanguage: "Under-recovered.",
            response: BoundedResponse(increase: nil, offset: nil,
                                      reduce: ReduceSpec(qualityRaw: "any_high_cns", by: "trim hardest"),
                                      evidenceRaw: "REDUCE rules"))

        var defs = [lateRace, weakTop, chronic]
        if reduceTargetsMaxVelocity { defs = [speedTradeTest] }

        let profile = EventAdjustmentProfile(event: "100m", weeklyHighCNSBudget: 3,
                                             qualities: [accel, maxVel, se], deficiencies: defs)
        return AdjustmentRanges(meta: RangesMeta(status: "COACH_REVIEW_DRAFT", requiresCoachSignoff: true),
                                globalRules: global, profiles: [profile])
    }

    private func defaultWeekly() -> WeeklyVolume {
        WeeklyVolume(reps: [.acceleration: 5, .maxVelocity: 4, .speedEndurance: 3],
                     maxVelocitySessions: 1, highCNSSessions: 3)
    }

    private func sessions(_ count: Int, pattern: String, lowReadiness: Bool = false,
                          outlier: Bool = false, illness: Bool = false, completed: Bool = true) -> [SessionObservation] {
        (0..<count).map { _ in
            SessionObservation(phaseName: "Specific Preparation", isLowReadiness: lowReadiness,
                               isOutlier: outlier, isIllnessOrStress: illness,
                               completedPrescribedReps: completed, observedPatterns: [pattern])
        }
    }

    private func proposals(_ result: PersonalizationResult) -> [AdjustmentProposal] {
        if case .proposals(let p) = result { return p }
        return []
    }
    private func isNoChange(_ result: PersonalizationResult) -> Bool {
        if case .noChange = result { return true }; return false
    }
    private func engine() -> PersonalizationEngine { PersonalizationEngine(ranges: ranges()) }

    // MARK: - Tests

    func testAddRequiresMinimumQualifyingSessions() {
        let three = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                      observations: sessions(3, pattern: "late_race_deceleration"), readinessTrend: .flat)
        XCTAssertTrue(isNoChange(three), "3 qualifying sessions must not trigger ADD")

        let four = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                     observations: sessions(4, pattern: "late_race_deceleration"), readinessTrend: .flat)
        XCTAssertTrue(proposals(four).contains { $0.deficiency == "late_race_deceleration" })
    }

    func testAddBlockedByInconsistentPattern() {
        let mixed = sessions(2, pattern: "none") + sessions(2, pattern: "late_race_deceleration")  // present in only 2 of last 4
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                  observations: mixed, readinessTrend: .flat)
        XCTAssertTrue(isNoChange(r))
    }

    func testLowReadinessSessionsExcluded() {
        let obs = sessions(2, pattern: "late_race_deceleration", lowReadiness: true)
            + sessions(2, pattern: "late_race_deceleration")   // only 2 qualifying
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                  observations: obs, readinessTrend: .flat)
        XCTAssertTrue(isNoChange(r), "excluded low-readiness sessions must not count toward ADD evidence")
    }

    func testOutlierAndIllnessSessionsExcluded() {
        let obs = sessions(2, pattern: "late_race_deceleration", outlier: true)
            + sessions(2, pattern: "late_race_deceleration", illness: true)   // 0 qualifying
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                  observations: obs, readinessTrend: .flat)
        XCTAssertTrue(isNoChange(r))
    }

    func testSingleSessionNeverTriggersAdd() {
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                  observations: sessions(1, pattern: "late_race_deceleration"), readinessTrend: .flat)
        XCTAssertTrue(isNoChange(r))
    }

    func testReduceFiresOnLowEvidence() {
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                  observations: [], readinessTrend: .down)   // declining readiness alone
        let p = proposals(r)
        XCTAssertTrue(p.contains { $0.deficiency == "chronic_underrecovery" && $0.kind == .reduce })
    }

    func testNeverExceedsQualityMaxBand() {
        var weekly = defaultWeekly(); weekly.reps[.speedEndurance] = 4   // already at max
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: weekly,
                                  observations: sessions(4, pattern: "late_race_deceleration"), readinessTrend: .flat)
        XCTAssertFalse(proposals(r).contains { $0.deficiency == "late_race_deceleration" }, "must not push speed_endurance above its max band")
    }

    func testOffsetNeverBelowQualityMin() {
        var weekly = defaultWeekly(); weekly.reps[.speedEndurance] = 2   // offset already at min
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: weekly,
                                  observations: sessions(4, pattern: "weak_top_speed"), readinessTrend: .flat)
        XCTAssertFalse(proposals(r).contains { $0.deficiency == "weak_top_speed" }, "offset must not go below its min band")
    }

    func testNeverExceedsWeeklyHighCNSCapAndSessionsUnchanged() {
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                  observations: sessions(4, pattern: "late_race_deceleration"), readinessTrend: .flat)
        let proposal = proposals(r).first { $0.deficiency == "late_race_deceleration" }!
        let after = engine().apply(proposal, to: defaultWeekly())
        XCTAssertEqual(after.highCNSSessions, 3)
        XCTAssertLessThanOrEqual(after.highCNSSessions, 3)
        XCTAssertEqual(after.maxVelocitySessions, 1)
    }

    func testTradesOnly_totalNeverIncreases() {
        let add = proposals(engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                            observations: sessions(4, pattern: "late_race_deceleration"), readinessTrend: .flat))
        for p in add { XCTAssertLessThanOrEqual(p.netRepChange, 0) }
        XCTAssertEqual(add.first { $0.deficiency == "late_race_deceleration" }?.netRepChange, 0, "ADD is a +1/−1 trade")

        let reduce = proposals(engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                               observations: [], readinessTrend: .down))
        for p in reduce { XCTAssertLessThanOrEqual(p.netRepChange, 0) }
    }

    func testMaxVelocityFloorAlwaysHolds() {
        // A response whose offset reduces max-velocity, with max-velocity already at min.
        var weekly = defaultWeekly(); weekly.reps[.maxVelocity] = 3   // at min / floor
        let eng = PersonalizationEngine(ranges: ranges(reduceTargetsMaxVelocity: true))
        let r = eng.evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: weekly,
                             observations: sessions(4, pattern: "floor_probe"), readinessTrend: .flat)
        XCTAssertTrue(isNoChange(r), "max-velocity must never be reduced below its floor")
    }

    func testBlackoutDuringCompetitionTaper() {
        let r = engine().evaluate(event: "100m", currentPhase: "Competition / Taper", weekly: defaultWeekly(),
                                  observations: sessions(4, pattern: "late_race_deceleration"), readinessTrend: .flat)
        XCTAssertFalse(proposals(r).contains { $0.kind == .add }, "no ADD during Competition/Taper")
    }

    func testBlackoutWhenReadinessDeclining() {
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                  observations: sessions(4, pattern: "late_race_deceleration"), readinessTrend: .down)
        XCTAssertFalse(proposals(r).contains { $0.kind == .add }, "no ADD while readiness baseline is declining")
    }

    func testUnsupportedEventDisabled() {
        let r = engine().evaluate(event: "800m", currentPhase: "Specific Preparation", weekly: defaultWeekly(),
                                  observations: sessions(4, pattern: "late_race_deceleration"), readinessTrend: .flat)
        if case .disabled = r {} else { XCTFail("events without a profile must be disabled") }
    }

    func testEvaluateDoesNotMutateAndApplyIsSeparate() {
        let before = defaultWeekly()
        let r = engine().evaluate(event: "100m", currentPhase: "Specific Preparation", weekly: before,
                                  observations: sessions(4, pattern: "late_race_deceleration"), readinessTrend: .flat)
        XCTAssertEqual(before, defaultWeekly(), "evaluate must not mutate the input volume")
        let proposal = proposals(r).first { $0.deficiency == "late_race_deceleration" }!
        let after = engine().apply(proposal, to: before)
        XCTAssertNotEqual(after, before, "apply (post-confirmation) produces the changed volume")
    }

    func testRangeNumbersAreData() {
        // Same 2-session evidence: no ADD under default config, ADD once the
        // minimum is lowered — proving the thresholds are tunable data.
        let obs = sessions(2, pattern: "late_race_deceleration")
        XCTAssertTrue(isNoChange(engine().evaluate(event: "100m", currentPhase: "Specific Preparation",
            weekly: defaultWeekly(), observations: obs, readinessTrend: .flat)))

        let loose = PersonalizationEngine(ranges: ranges(),
            config: EvidenceConfig(addMinSessions: 2, addConsistencyK: 2, addConsistencyN: 2, addMaxRepsPerWeek: 1, reduceMinSessions: 1))
        XCTAssertTrue(proposals(loose.evaluate(event: "100m", currentPhase: "Specific Preparation",
            weekly: defaultWeekly(), observations: obs, readinessTrend: .flat))
            .contains { $0.deficiency == "late_race_deceleration" })
    }
}
