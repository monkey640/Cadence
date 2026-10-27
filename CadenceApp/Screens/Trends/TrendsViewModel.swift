import Foundation
import Observation
import CadenceCore

/// One charted data point.
struct TrendPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let value: Double
}

/// Loads the 30-day physiological series for Trends straight from HealthKit
/// (HealthKit retains the raw history, so we don't depend on the app having
/// run every day). The readiness-score series comes from persisted
/// `DailyReadiness` and is supplied by the view via @Query.
@MainActor
@Observable
final class TrendsViewModel {
    enum State { case loading, ready, error(String) }
    private(set) var state: State = .loading

    private(set) var hrv: [TrendPoint] = []
    private(set) var restingHR: [TrendPoint] = []
    private(set) var sleepHours: [TrendPoint] = []

    private let health: HealthDataProviding
    init(health: HealthDataProviding = HealthKitService()) { self.health = health }

    func load() async {
        state = .loading
        do {
            async let hrvSeries = health.dailyHRV(days: 30)
            async let rhrSeries = health.dailyRestingHR(days: 30)
            async let sleepSeries = health.nightlySleep(days: 30)

            hrv = try await hrvSeries.map { TrendPoint(date: $0.day, value: $0.value) }
            restingHR = try await rhrSeries.map { TrendPoint(date: $0.day, value: $0.value) }
            sleepHours = try await sleepSeries.map { TrendPoint(date: $0.day, value: $0.value / 3600) }
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
