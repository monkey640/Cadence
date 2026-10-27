import XCTest
@testable import CadenceCore

/// The added overnight signals: sleep quality (deep+REM), respiratory rate
/// (inverted), wrist temperature (symmetric deviation), and graceful degradation
/// when a device doesn't provide them.
final class ExtraSignalsTests: XCTestCase {
    let engine = ReadinessEngine()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func mature(_ mean: Double, _ sd: Double) -> Baseline {
        Baseline(mean: mean, standardDeviation: sd, sampleCount: 30)
    }

    private func base(quality: Double? = nil, qualityBase: Baseline? = nil,
                      resp: Double? = nil, respBase: Baseline? = nil,
                      temp: Double? = nil, tempBase: Baseline? = nil) -> ReadinessInput {
        ReadinessInput(
            date: date,
            hrvSDNN: 60, hrvBaseline: mature(60, 8),
            sleepSeconds: 7 * 3600, sleepBaseline: mature(7 * 3600, 1800),
            sleepQualitySeconds: quality, sleepQualityBaseline: qualityBase,
            restingHR: 50, rhrBaseline: mature(50, 4),
            respiratoryRate: resp, respiratoryRateBaseline: respBase,
            wristTemperature: temp, wristTemperatureBaseline: tempBase,
            loadRatio: 1.0)
    }

    func testGracefulDegradationWhenExtrasAbsent() {
        // No quality/resp/temp → those components are nil; engine still works.
        let out = engine.evaluate(base())
        XCTAssertNil(out.components.sleepQuality)
        XCTAssertNil(out.components.respiratoryRate)
        XCTAssertNil(out.components.wristTemperature)
        XCTAssertEqual(out.verdict, .push)   // average day still reads normal
    }

    func testSleepQualityRaisesAndLowersScore() {
        let baseline = mature(3 * 3600, 1800)   // ~3h deep+REM baseline
        let good = engine.evaluate(base(quality: 3 * 3600 + 2 * 1800, qualityBase: baseline)) // +2σ
        let poor = engine.evaluate(base(quality: 3 * 3600 - 2 * 1800, qualityBase: baseline)) // −2σ
        XCTAssertNotNil(good.components.sleepQuality)
        XCTAssertGreaterThan(good.score, poor.score)
    }

    func testRespiratoryRateIsInverted() {
        let baseline = mature(14, 1)   // 14 breaths/min
        let low = engine.evaluate(base(resp: 12, respBase: baseline))   // below baseline = good
        let high = engine.evaluate(base(resp: 16, respBase: baseline))  // elevated = worse
        XCTAssertGreaterThan(low.score, high.score)
        XCTAssertGreaterThan(low.components.respiratoryRate!, high.components.respiratoryRate!)
    }

    func testWristTemperaturePenalizesDeviationEitherWay() {
        let baseline = mature(33.0, 0.3)   // °C
        let atBaseline = engine.evaluate(base(temp: 33.0, tempBase: baseline))
        let hotter = engine.evaluate(base(temp: 33.6, tempBase: baseline))   // +2σ
        let colder = engine.evaluate(base(temp: 32.4, tempBase: baseline))   // −2σ
        // Both deviations score below being at baseline.
        XCTAssertGreaterThan(atBaseline.components.wristTemperature!, hotter.components.wristTemperature!)
        XCTAssertGreaterThan(atBaseline.components.wristTemperature!, colder.components.wristTemperature!)
        // And symmetric: equal-magnitude deviations score the same.
        XCTAssertEqual(hotter.components.wristTemperature!, colder.components.wristTemperature!, accuracy: 0.01)
    }

    func testExtrasMissingDoesNotTripConservativeCap() {
        // A strong day with NO extra signals must still be able to reach Push
        // (missing optional hardware never forces the conservative cap).
        let strong = ReadinessInput(
            date: date,
            hrvSDNN: 84, hrvBaseline: mature(60, 8),          // +3σ
            sleepSeconds: 7 * 3600 + 3 * 1800, sleepBaseline: mature(7 * 3600, 1800),
            restingHR: 44, rhrBaseline: mature(50, 4),
            loadRatio: 0.8)
        XCTAssertEqual(engine.evaluate(strong).verdict, .push)
    }
}
