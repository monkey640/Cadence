import Foundation

/// A day's raw physiological reading, keyed to the start of that day.
struct DailyMetric: Sendable, Equatable {
    let day: Date
    let value: Double
}

/// Abstraction over HealthKit so the readiness pipeline can be unit-tested
/// with canned data and previewed without Health permissions.
protocol HealthDataProviding: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws

    /// Daily-average HRV (SDNN, ms) for the trailing `days`, oldest→newest.
    func dailyHRV(days: Int) async throws -> [DailyMetric]
    /// Daily resting heart rate (bpm) for the trailing `days`, oldest→newest.
    func dailyRestingHR(days: Int) async throws -> [DailyMetric]
    /// Total *asleep* seconds for the most recent night, or nil if none recorded.
    func lastNightSleepSeconds() async throws -> Double?
    /// Per-night asleep seconds for the trailing `days` (for the sleep baseline + Trends).
    func nightlySleep(days: Int) async throws -> [DailyMetric]
    /// Acute:chronic workout-load ratio (7-day vs 28-day weekly average), or nil if no data.
    func workoutLoadRatio() async throws -> Double?

    // Optional overnight signals — default to empty so conformers (and devices)
    // that don't provide them degrade gracefully.
    func nightlyDeepREMSleep(days: Int) async throws -> [DailyMetric]
    func dailyRespiratoryRate(days: Int) async throws -> [DailyMetric]
    func dailyWristTemperature(days: Int) async throws -> [DailyMetric]
}

extension HealthDataProviding {
    func nightlyDeepREMSleep(days: Int) async throws -> [DailyMetric] { [] }
    func dailyRespiratoryRate(days: Int) async throws -> [DailyMetric] { [] }
    func dailyWristTemperature(days: Int) async throws -> [DailyMetric] { [] }
}
