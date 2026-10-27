import XCTest
@testable import CadenceCore

final class NormalizationTests: XCTestCase {
    let config = ReadinessConfig.standard

    func testSubscoreNeutralAtZero() {
        // Centered at 72: a value exactly at baseline reads as a normal/good day.
        XCTAssertEqual(Normalization.subscore(fromZ: 0, config: config), 72, accuracy: 0.0001)
    }

    func testSubscoreSaturatesHigh() {
        // With neutral 72 and 20 pts/σ, the top saturates by +1.4σ.
        XCTAssertEqual(Normalization.subscore(fromZ: 3, config: config), 100, accuracy: 0.0001)
        XCTAssertEqual(Normalization.subscore(fromZ: 1.5, config: config), 100, accuracy: 0.0001)
    }

    func testSubscoreFloorsLow() {
        // Downside has more room: −3σ still scores 12; it floors only below ~−3.6σ.
        XCTAssertEqual(Normalization.subscore(fromZ: -3, config: config), 12, accuracy: 0.0001)
        XCTAssertEqual(Normalization.subscore(fromZ: -4, config: config), 0, accuracy: 0.0001)
    }

    func testRHRInversion() {
        // A below-baseline RHR (negative z) is GOOD → above-neutral score.
        XCTAssertEqual(Normalization.invertedSubscore(fromZ: -1, config: config), 92, accuracy: 0.0001)
        XCTAssertEqual(Normalization.invertedSubscore(fromZ: 1, config: config), 52, accuracy: 0.0001)
    }

    func testLoadSubscoreMonotonicAndBounded() {
        XCTAssertEqual(Normalization.loadSubscore(fromRatio: 0.8), 100, accuracy: 0.0001)  // rested
        XCTAssertEqual(Normalization.loadSubscore(fromRatio: 1.0), 100, accuracy: 0.0001)  // balanced
        XCTAssertEqual(Normalization.loadSubscore(fromRatio: 1.333), 50, accuracy: 0.5)    // overreaching
        XCTAssertEqual(Normalization.loadSubscore(fromRatio: 2.0), 0, accuracy: 0.0001)    // deep hole
    }

    func testMultiplierCurveEndpoints() {
        XCTAssertEqual(Normalization.multiplier(fromScore: 100, config: config), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Normalization.multiplier(fromScore: 50, config: config), 0.75, accuracy: 0.0001)
        XCTAssertEqual(Normalization.multiplier(fromScore: 0, config: config), 0.5, accuracy: 0.0001)
        // The brief's worked example: score 80 → 0.9 (push threshold).
        XCTAssertEqual(Normalization.multiplier(fromScore: 80, config: config), 0.9, accuracy: 0.0001)
    }
}
