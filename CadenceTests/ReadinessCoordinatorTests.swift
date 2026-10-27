import XCTest
import CadenceCore
@testable import Cadence

/// In-memory health provider returning canned series, so the coordinator and
/// the HealthKit→engine wiring can be tested without HealthKit or a device.
private struct MockHealth: HealthDataProviding {
    var hrv: [DailyMetric] = []
    var rhr: [DailyMetric] = []
    var sleep: [DailyMetric] = []
    var ratio: Double? = nil

    var isAvailable: Bool { true }
    func requestAuthorization() async throws {}
    func dailyHRV(days: Int) async throws -> [DailyMetric] { hrv }
    func dailyRestingHR(days: Int) async throws -> [DailyMetric] { rhr }
    func lastNightSleepSeconds() async throws -> Double? { sleep.last?.value }
    func nightlySleep(days: Int) async throws -> [DailyMetric] { sleep }
    func workoutLoadRatio() async throws -> Double? { ratio }
}

final class ReadinessCoordinatorTests: XCTestCase {
    private let cal = Calendar.current

    /// Build a 30-day-prior baseline series plus a value for today.
    private func series(baseline: Double, today: Double, now: Date) -> [DailyMetric] {
        let start = cal.startOfDay(for: now)
        var out: [DailyMetric] = []
        for d in 1...30 {
            out.append(DailyMetric(day: cal.date(byAdding: .day, value: -d, to: start)!, value: baseline))
        }
        out.append(DailyMetric(day: start, value: today))
        return out.sorted { $0.day < $1.day }
    }

    func testStrongMorningProducesPush() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mock = MockHealth(
            hrv: series(baseline: 60, today: 90, now: now),     // well above baseline
            rhr: series(baseline: 52, today: 46, now: now),     // below baseline = good
            sleep: series(baseline: 7 * 3600, today: 8.5 * 3600, now: now),
            ratio: 0.8)
        let result = try await ReadinessCoordinator(health: mock).computeToday(asOf: now)
        XCTAssertEqual(result.output.verdict, .push)
        XCTAssertEqual(result.hrvSDNN, 90)
    }

    func testNoHistoryIsBaselining() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = cal.startOfDay(for: now)
        // Only today's readings, no prior days → baseline empty.
        let mock = MockHealth(
            hrv: [DailyMetric(day: start, value: 80)],
            rhr: [DailyMetric(day: start, value: 50)],
            sleep: [DailyMetric(day: start, value: 8 * 3600)],
            ratio: nil)
        let result = try await ReadinessCoordinator(health: mock).computeToday(asOf: now)
        XCTAssertTrue(result.output.isBaselining)
        XCTAssertNotEqual(result.output.verdict, .push)
    }
}
