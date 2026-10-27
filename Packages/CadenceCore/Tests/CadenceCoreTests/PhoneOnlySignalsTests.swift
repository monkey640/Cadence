import XCTest
@testable import CadenceCore

/// The phone-only readiness inputs that let Cadence work for teens without a
/// wearable: the subjective wellness check-in (highest-evidence, baseline-free,
/// can stand alone), the CNS finger-tap test, and the phone-camera jump (both
/// low-confidence, baseline-relative). Covers the four requirements: a confidence
/// level on the score, more-conservative bias on phone-only / conflicting inputs,
/// graceful degradation when inputs are skipped, and that the new weights are
/// flagged draft.
final class PhoneOnlySignalsTests: XCTestCase {
    let engine = ReadinessEngine()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func mature(_ m: Double, _ sd: Double) -> Baseline {
        Baseline(mean: m, standardDeviation: sd, sampleCount: 30)
    }
    private func checkIn(_ v: Int) -> WellnessCheckIn {
        WellnessCheckIn(sleepRating: v, soreness: v, fatigue: v, stress: v, mood: v)
    }
    /// A phone-only morning: no wearable signals at all.
    private func phoneOnly(wellness: WellnessCheckIn? = nil,
                           tap: Double? = nil, tapBase: Baseline? = nil,
                           cmj: Double? = nil, cmjBase: Baseline? = nil,
                           load: Double? = nil) -> ReadinessInput {
        ReadinessInput(
            date: date,
            hrvSDNN: nil, hrvBaseline: nil, sleepSeconds: nil, sleepBaseline: nil,
            restingHR: nil, rhrBaseline: nil, loadRatio: load,
            wellness: wellness, fingerTapCount: tap, fingerTapBaseline: tapBase,
            countermovementJumpCm: cmj, cmjBaseline: cmjBase)
    }

    // MARK: - Wellness sub-score mapping

    func testWellnessSubscoreAnchoredAndAsymmetric() {
        let c = ReadinessConfig.standard
        XCTAssertEqual(Normalization.wellnessSubscore(fromAverage: 5, config: c), 95, accuracy: 0.01)
        XCTAssertEqual(Normalization.wellnessSubscore(fromAverage: 3, config: c), 72, accuracy: 0.01) // neutral
        XCTAssertEqual(Normalization.wellnessSubscore(fromAverage: 1, config: c), 24, accuracy: 0.01)
        // A level below neutral costs more than a level above gains (anti-overtraining).
        let up = Normalization.wellnessSubscore(fromAverage: 4, config: c) - 72
        let down = 72 - Normalization.wellnessSubscore(fromAverage: 2, config: c)
        XCTAssertGreaterThan(down, up)
    }

    func testWellnessAverageClampsAndAverages() {
        XCTAssertEqual(checkIn(5).average, 5, accuracy: 0.001)
        XCTAssertEqual(WellnessCheckIn(sleepRating: 4, soreness: 2, fatigue: 3, stress: 5, mood: 1).average,
                       3.0, accuracy: 0.001)
    }

    // MARK: - Wellness stands alone (the wearable gate is removed)

    func testGoodCheckInStandsAloneButCappedModerate() {
        let out = engine.evaluate(phoneOnly(wellness: checkIn(5)))
        XCTAssertFalse(out.isBaselining, "a daily check-in anchors the day — never stuck baselining")
        XCTAssertNotNil(out.components.wellness)
        XCTAssertEqual(out.confidence, .moderate, "subjective-only is trustworthy but not high confidence")
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.80 + 1e-9, "phone-only is capped at moderate volume")
        XCTAssertNotEqual(out.verdict, .push, "self-report alone can't green-light a hard push")
        XCTAssertTrue(out.reason.contains("check-in"))
    }

    func testTerribleCheckInStandsAloneAndBacksOff() {
        let out = engine.evaluate(phoneOnly(wellness: checkIn(1)))
        XCTAssertEqual(out.verdict, .backOff)
        XCTAssertLessThan(out.volumeMultiplier, 0.70)
    }

    func testNeutralCheckInHolds() {
        let out = engine.evaluate(phoneOnly(wellness: checkIn(3)))
        XCTAssertEqual(out.verdict, .hold)
    }

    // MARK: - Low-confidence phone tests

    func testFingerTapOnlyIsLowConfidenceAndCannotPush() {
        let out = engine.evaluate(phoneOnly(tap: 100, tapBase: mature(80, 10))) // +2σ, a "good" tap
        XCTAssertEqual(out.confidence, .low)
        XCTAssertNotNil(out.components.fingerTap)
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.70 + 1e-9, "a weak test never green-lights a hard day")
        XCTAssertNotEqual(out.verdict, .push)
        XCTAssertTrue(out.reason.contains("phone test"))
    }

    func testPoorFingerTapOnlyStaysConservative() {
        let out = engine.evaluate(phoneOnly(tap: 50, tapBase: mature(80, 10))) // −3σ
        XCTAssertEqual(out.confidence, .low)
        XCTAssertNotEqual(out.verdict, .push)
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.70 + 1e-9)
    }

    func testJumpHeightMovesScoreInRightDirection() {
        let good = engine.evaluate(phoneOnly(cmj: 40, cmjBase: mature(34, 3))) // +2σ
        let poor = engine.evaluate(phoneOnly(cmj: 28, cmjBase: mature(34, 3))) // −2σ
        XCTAssertNotNil(good.components.countermovementJump)
        XCTAssertGreaterThan(good.score, poor.score)
    }

    // MARK: - Graceful degradation

    func testPhoneTestWithoutBaselineDropsOutAndBaselines() {
        // A finger-tap with too little history can't be trusted yet → dropped,
        // and with nothing else usable the day is honestly "baselining".
        let young = Baseline(mean: 80, standardDeviation: 10, sampleCount: 3)
        let out = engine.evaluate(phoneOnly(tap: 100, tapBase: young))
        XCTAssertNil(out.components.fingerTap)
        XCTAssertTrue(out.isBaselining)
        XCTAssertNotEqual(out.verdict, .push)
    }

    // MARK: - Conflict biases conservative

    func testConflictingSignalsDemoteConfidenceAndCap() {
        // Full wearable picture, but HRV (+3σ) and sleep (−3σ) wildly disagree.
        let out = engine.evaluate(ReadinessInput(
            date: date,
            hrvSDNN: 110, hrvBaseline: mature(80, 10),
            sleepSeconds: 7 * 3600 - 3 * 1800, sleepBaseline: mature(7 * 3600, 1800),
            restingHR: 50, rhrBaseline: mature(50, 4),
            loadRatio: 1.0))
        XCTAssertEqual(out.confidence, .moderate, "conflict demotes high → moderate")
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.80 + 1e-9)
        XCTAssertNotEqual(out.verdict, .push)
        XCTAssertTrue(out.reason.contains("disagree"))
    }

    func testAgreeingSignalsAreNotFlaggedAsConflict() {
        let out = engine.evaluate(ReadinessInput(
            date: date,
            hrvSDNN: 60, hrvBaseline: mature(60, 8),
            sleepSeconds: 7 * 3600, sleepBaseline: mature(7 * 3600, 1800),
            restingHR: 50, rhrBaseline: mature(50, 4),
            loadRatio: 1.0))
        XCTAssertEqual(out.confidence, .high)
        XCTAssertFalse(out.reason.contains("disagree"))
    }

    // MARK: - Wearable is a premium layer on top, not a gate

    func testWellnessBlendsWithWearableAtHighConfidence() {
        let out = engine.evaluate(ReadinessInput(
            date: date,
            hrvSDNN: 84, hrvBaseline: mature(60, 8),
            sleepSeconds: 7 * 3600 + 2 * 1800, sleepBaseline: mature(7 * 3600, 1800),
            restingHR: 46, rhrBaseline: mature(50, 4),
            loadRatio: 0.8,
            wellness: checkIn(5)))
        XCTAssertNotNil(out.components.wellness)
        XCTAssertEqual(out.confidence, .high, "full wearable trio + agreeing check-in")
        XCTAssertEqual(out.verdict, .push)
    }

    // MARK: - Draft weights are flagged

    func testPhoneSignalWeightsAreFlaggedDraft() {
        XCTAssertTrue(ReadinessConfig.standard.phoneSignalWeightsAreDraft,
                      "the unvalidated phone-signal weights must advertise themselves as draft")
    }
}
