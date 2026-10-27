import XCTest
@testable import CadenceCore

final class BaselineCalculatorTests: XCTestCase {

    func testEmptyReturnsNil() {
        XCTAssertNil(BaselineCalculator.baseline(from: []))
    }

    func testMeanAndSD() {
        // Population SD of [2,4,4,4,5,5,7,9] is 2.0, mean 5.0 (classic example).
        let b = BaselineCalculator.baseline(from: [2, 4, 4, 4, 5, 5, 7, 9])
        XCTAssertNotNil(b)
        XCTAssertEqual(b!.mean, 5.0, accuracy: 0.0001)
        XCTAssertEqual(b!.standardDeviation, 2.0, accuracy: 0.0001)
        XCTAssertEqual(b!.sampleCount, 8)
    }

    func testZScoreHandlesZeroSD() {
        let b = Baseline(mean: 50, standardDeviation: 0, sampleCount: 10)
        XCTAssertEqual(b.zScore(for: 80), 0)  // no spread → neutral, not a crash
    }
}
