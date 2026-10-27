import XCTest
@testable import CadenceCore

/// Degraded-data behavior: every case must lean conservative (toward rest),
/// never crash, and never produce a confident "push" it can't justify.
final class RobustnessTests: XCTestCase {
    let engine = ReadinessEngine()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func mature(_ mean: Double, _ sd: Double) -> Baseline {
        Baseline(mean: mean, standardDeviation: sd, sampleCount: 30)
    }

    // 1. A missing night of sleep — sleep reading absent, everything else good.
    func testMissingNightOfSleep() {
        let out = engine.evaluate(ReadinessInput(
            date: date,
            hrvSDNN: 90, hrvBaseline: mature(80, 10),
            sleepSeconds: nil, sleepBaseline: mature(7 * 3600, 1800),
            restingHR: 46, rhrBaseline: mature(52, 4),
            loadRatio: 0.8))
        XCTAssertNil(out.components.sleep, "missing sleep is excluded, not zeroed")
        XCTAssertNotEqual(out.verdict, .push, "can't confidently push without sleep")
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.85, "conservative cap applies")
    }

    // 2. A single absurd HRV reading (sensor error) — must NOT push.
    func testAbsurdHRVReadingIsRejected() {
        let out = engine.evaluate(ReadinessInput(
            date: date,
            hrvSDNN: 500, hrvBaseline: mature(60, 8),   // z ≈ +55, impossible
            sleepSeconds: 7 * 3600, sleepBaseline: mature(7 * 3600, 1800),
            restingHR: 50, rhrBaseline: mature(50, 4),
            loadRatio: 1.0))
        XCTAssertNil(out.components.hrv, "absurd HRV is dropped as a sensor error")
        XCTAssertNotEqual(out.verdict, .push, "garbage HRV must not produce a push")
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.85)
    }

    // 2b. Guard against over-rejection: a real, strong +3σ day must still count.
    func testLegitimateExtremeIsNotRejected() {
        let out = engine.evaluate(ReadinessInput(
            date: date,
            hrvSDNN: 110, hrvBaseline: mature(80, 10),  // z = +3, real great day
            sleepSeconds: 9 * 3600, sleepBaseline: mature(7 * 3600, 1800),
            restingHR: 44, rhrBaseline: mature(52, 4),
            loadRatio: 0.7))
        XCTAssertNotNil(out.components.hrv, "+3σ is a real day, not an outlier")
        XCTAssertEqual(out.verdict, .push)
    }

    // 3. Fewer than 7 days of baseline — baselining, conservative, never push.
    func testInsufficientBaseline() {
        let young = Baseline(mean: 80, standardDeviation: 10, sampleCount: 4)
        let out = engine.evaluate(ReadinessInput(
            date: date,
            hrvSDNN: 130, hrvBaseline: young,
            sleepSeconds: 9 * 3600, sleepBaseline: young,
            restingHR: 42, rhrBaseline: young,
            loadRatio: 0.6))
        XCTAssertTrue(out.isBaselining)
        XCTAssertNil(out.components.hrv)
        XCTAssertNotEqual(out.verdict, .push)
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.85)
    }

    // 4. A day with absolutely no data — must not crash, must stay conservative.
    func testNoDataAtAll() {
        let out = engine.evaluate(ReadinessInput(
            date: date,
            hrvSDNN: nil, hrvBaseline: nil,
            sleepSeconds: nil, sleepBaseline: nil,
            restingHR: nil, rhrBaseline: nil,
            loadRatio: nil))
        XCTAssertTrue(out.isBaselining)
        XCTAssertNil(out.components.hrv)
        XCTAssertNil(out.components.sleep)
        XCTAssertNil(out.components.rhr)
        XCTAssertNotEqual(out.verdict, .push)
        XCTAssertLessThanOrEqual(out.volumeMultiplier, 0.85)
        XCTAssertGreaterThanOrEqual(out.volumeMultiplier, 0.5, "never below the floor")
    }

    // 5. Duplicate / overlapping sleep samples must not double-count.
    func testDuplicateSleepSamplesAreMerged() {
        let base = 1_700_000_000.0
        let eightHours = 8.0 * 3600
        // Two identical 8h records (iPhone + Watch) for the same night.
        let exactDuplicates = [
            (start: base, end: base + eightHours),
            (start: base, end: base + eightHours),
        ]
        XCTAssertEqual(SleepIntervalMerger.totalDuration(of: exactDuplicates), eightHours, accuracy: 0.5,
                       "exact duplicates count once, not 16h")

        // Overlapping records: 0–6h and 5–9h → union is 0–9h = 9h.
        let overlapping = [
            (start: base, end: base + 6 * 3600),
            (start: base + 5 * 3600, end: base + 9 * 3600),
        ]
        XCTAssertEqual(SleepIntervalMerger.totalDuration(of: overlapping), 9 * 3600, accuracy: 0.5)

        // Genuinely separate segments (woke up): 0–3h and 4–7h → 6h total.
        let separate = [
            (start: base, end: base + 3 * 3600),
            (start: base + 4 * 3600, end: base + 7 * 3600),
        ]
        XCTAssertEqual(SleepIntervalMerger.totalDuration(of: separate), 6 * 3600, accuracy: 0.5)

        XCTAssertEqual(SleepIntervalMerger.totalDuration(of: []), 0, "empty input is 0, not a crash")
    }
}
