import XCTest
@testable import CadenceCore

final class StreakCalculatorTests: XCTestCase {

    func testConsecutiveRunEndingToday() {
        XCTAssertEqual(StreakCalculator.currentStreak(checkInDays: [100, 99, 98], today: 100), 3)
    }

    func testRestDayStillCounts() {
        // Every recorded day counts regardless of what happened that day.
        XCTAssertEqual(StreakCalculator.currentStreak(checkInDays: [10, 9, 8, 7], today: 10), 4)
    }

    func testStreakStaysAliveBeforeTodaysCheckIn() {
        // Today not recorded yet, but yesterday is → streak counts through yesterday, not 0.
        XCTAssertEqual(StreakCalculator.currentStreak(checkInDays: [99, 98, 97], today: 100), 3)
    }

    func testGapBreaksStreak() {
        XCTAssertEqual(StreakCalculator.currentStreak(checkInDays: [100, 98, 97], today: 100), 1)
    }

    func testNoRecentCheckInIsZero() {
        XCTAssertEqual(StreakCalculator.currentStreak(checkInDays: [90, 89], today: 100), 0)
        XCTAssertEqual(StreakCalculator.currentStreak(checkInDays: [], today: 100), 0)
    }

    func testLongestStreak() {
        // runs: 1..3 (len 3), 10..11 (len 2)
        XCTAssertEqual(StreakCalculator.longestStreak(checkInDays: [1, 2, 3, 10, 11]), 3)
        XCTAssertEqual(StreakCalculator.longestStreak(checkInDays: []), 0)
    }
}
