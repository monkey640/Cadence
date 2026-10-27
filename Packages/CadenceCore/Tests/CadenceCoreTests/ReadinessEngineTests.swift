import XCTest
@testable import CadenceCore

final class ReadinessEngineTests: XCTestCase {
    let engine = ReadinessEngine()
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    /// Baselines with plenty of history so cold-start does not trigger.
    private func mature(mean: Double, sd: Double) -> Baseline {
        Baseline(mean: mean, standardDeviation: sd, sampleCount: 30)
    }

    /// A perfectly average day — every signal exactly at its 30-day baseline,
    /// balanced load. With neutral centering at 72, a typical day reads "Push",
    /// not "Hold": physiological signals sit at 72, load at 100.
    func testPerfectlyAverageDay() {
        let input = ReadinessInput(
            date: date,
            hrvSDNN: 60, hrvBaseline: mature(mean: 60, sd: 8),       // z = 0 → 72
            sleepSeconds: 7 * 3600, sleepBaseline: mature(mean: 7 * 3600, sd: 1800), // z = 0 → 72
            restingHR: 50, rhrBaseline: mature(mean: 50, sd: 4),     // z = 0 → 72 (inverted)
            loadRatio: 1.0)                                          // balanced → 100
        let out = engine.evaluate(input)
        // Only HRV/sleep/RHR/load present (no temp/resp/quality), weights re-normalized
        // over them: (72·.35 + 72·.15 + 72·.12 + 100·.08) / .70 = 75.2 → curve 0.876 → push.
        // A push verdict now scales to FULL volume by design (the curve's 0.876 is
        // promoted to 1.0), so an average day trains the whole session.
        XCTAssertEqual(out.score, 75.2, accuracy: 0.05)
        XCTAssertEqual(out.verdict, .push)
        XCTAssertEqual(out.volumeMultiplier, 1.0, accuracy: 0.001)
    }

    func testAllSignalsStrongGivesPush() {
        let input = ReadinessInput(
            date: date,
            hrvSDNN: 110, hrvBaseline: mature(mean: 80, sd: 10),      // +3σ
            sleepSeconds: 9 * 3600, sleepBaseline: mature(mean: 7 * 3600, sd: 1800), // well above
            restingHR: 44, rhrBaseline: mature(mean: 52, sd: 4),      // well below = good
            loadRatio: 0.7)                                            // rested
        let out = engine.evaluate(input)
        XCTAssertEqual(out.verdict, .push)
        XCTAssertGreaterThanOrEqual(out.volumeMultiplier, 0.90)
        XCTAssertFalse(out.isBaselining)
    }

    func testAllSignalsPoorGivesBackOff() {
        let input = ReadinessInput(
            date: date,
            hrvSDNN: 50, hrvBaseline: mature(mean: 80, sd: 10),       // -3σ
            sleepSeconds: 4 * 3600, sleepBaseline: mature(mean: 7 * 3600, sd: 1800),
            restingHR: 62, rhrBaseline: mature(mean: 52, sd: 4),      // elevated = bad
            loadRatio: 1.6)                                            // overreached
        let out = engine.evaluate(input)
        XCTAssertEqual(out.verdict, .backOff)
        XCTAssertLessThan(out.volumeMultiplier, 0.70)
    }

    func testMultiplierNeverBelowFloor() {
        let input = ReadinessInput(
            date: date,
            hrvSDNN: 10, hrvBaseline: mature(mean: 80, sd: 10),
            sleepSeconds: 1 * 3600, sleepBaseline: mature(mean: 7 * 3600, sd: 1800),
            restingHR: 90, rhrBaseline: mature(mean: 52, sd: 4),
            loadRatio: 3.0)
        let out = engine.evaluate(input)
        XCTAssertGreaterThanOrEqual(out.volumeMultiplier, 0.5)
    }

    func testMultiplierNeverAboveOne() {
        let input = ReadinessInput(
            date: date,
            hrvSDNN: 999, hrvBaseline: mature(mean: 80, sd: 10),
            sleepSeconds: 24 * 3600, sleepBaseline: mature(mean: 7 * 3600, sd: 1800),
            restingHR: 20, rhrBaseline: mature(mean: 52, sd: 4),
            loadRatio: 0.1)
        let out = engine.evaluate(input)
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 1.0)
    }

    func testColdStartShowsBaseliningAndNeverPushes() {
        // Only 3 days of history — below the 7-day minimum.
        let young = Baseline(mean: 80, standardDeviation: 10, sampleCount: 3)
        let input = ReadinessInput(
            date: date,
            hrvSDNN: 120, hrvBaseline: young,         // would be a huge push if trusted
            sleepSeconds: 9 * 3600, sleepBaseline: young,
            restingHR: 44, rhrBaseline: young,
            loadRatio: 0.6)
        let out = engine.evaluate(input)
        XCTAssertTrue(out.isBaselining)
        XCTAssertNotEqual(out.verdict, .push, "must not give a confident push while baselining")
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.85)
        XCTAssertNil(out.components.hrv, "signals without enough history are excluded")
    }

    func testMissingHRVCapsAtConservativeAndExcludesComponent() {
        // Strong sleep + RHR, but no HRV reading at all. Should not "push".
        let input = ReadinessInput(
            date: date,
            hrvSDNN: nil, hrvBaseline: mature(mean: 80, sd: 10),
            sleepSeconds: 9 * 3600, sleepBaseline: mature(mean: 7 * 3600, sd: 1800),
            restingHR: 44, rhrBaseline: mature(mean: 52, sd: 4),
            loadRatio: 0.7)
        let out = engine.evaluate(input)
        XCTAssertNil(out.components.hrv)
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.85)
        XCTAssertNotEqual(out.verdict, .push)
    }

    func testMissingLoadDoesNotInflate() {
        // Identical strong physiological signals, with vs without load data.
        // Missing load defaults to a sub-neutral 75, so it should not score higher.
        func make(loadRatio: Double?) -> ReadinessOutput {
            engine.evaluate(ReadinessInput(
                date: date,
                hrvSDNN: 100, hrvBaseline: mature(mean: 80, sd: 10),
                sleepSeconds: 8 * 3600, sleepBaseline: mature(mean: 7 * 3600, sd: 1800),
                restingHR: 48, rhrBaseline: mature(mean: 52, sd: 4),
                loadRatio: loadRatio))
        }
        let rested = make(loadRatio: 0.5)   // load subscore 100
        let unknown = make(loadRatio: nil)  // load subscore 75
        XCTAssertGreaterThan(rested.score, unknown.score)
    }

    func testWeightRenormalizationKeepsScoreInRange() {
        // Only HRV available (+1σ) → composite should reflect HRV's subscore (70),
        // not be diluted toward zero by the missing signals.
        let input = ReadinessInput(
            date: date,
            hrvSDNN: 90, hrvBaseline: mature(mean: 80, sd: 10),
            sleepSeconds: nil, sleepBaseline: nil,
            restingHR: nil, rhrBaseline: nil,
            loadRatio: nil)
        let out = engine.evaluate(input)
        // HRV +1σ → subscore 92 (weight .35) blended with default load 75 (weight .08):
        // (92*.35 + 75*.08) / .43 ≈ 88.8
        XCTAssertEqual(out.score, 88.84, accuracy: 0.5)
    }
}
