import Foundation
import SwiftData
import CadenceCore

/// Orchestrates the morning readiness loop:
/// fetch HealthKit windows → build rolling baselines → run the engine →
/// return the result (and persist a `DailyReadiness`).
///
/// The compute step depends only on `HealthDataProviding`, so it is unit-testable
/// with canned data; persistence is a separate, thin step.
struct ReadinessCoordinator {
    let health: HealthDataProviding
    let engine: ReadinessEngine

    init(health: HealthDataProviding, engine: ReadinessEngine = ReadinessEngine()) {
        self.health = health
        self.engine = engine
    }

    struct Result: Sendable {
        let output: ReadinessOutput
        let hrvSDNN: Double?
        let sleepSeconds: Double?
        let restingHR: Double?
    }

    /// Phone-only inputs for the day, sourced from SwiftData `CheckIn` rows by the
    /// caller and passed in as plain values so the compute path stays free of any
    /// persistence dependency (and unit-testable with canned data). Histories are
    /// *prior* days only — today's value is scored against them.
    struct PhoneInputs: Sendable {
        var wellness: WellnessCheckIn?
        var fingerTapToday: Double?
        var fingerTapHistory: [Double]
        var jumpToday: Double?
        var jumpHistory: [Double]

        static let none = PhoneInputs(wellness: nil, fingerTapToday: nil,
                                      fingerTapHistory: [], jumpToday: nil, jumpHistory: [])

        /// Gather the day's phone-only inputs from the `CheckIn` rows: today's
        /// wellness check-in and finger-tap / jump values, plus the prior-day
        /// histories the engine builds personal baselines from. Check-in rows are
        /// one-per-day and few, so fetching all and filtering in memory is simplest.
        @MainActor
        static func from(context: ModelContext, now: Date = .now) -> PhoneInputs {
            let today = Calendar.current.startOfDay(for: now)
            let all = (try? context.fetch(
                FetchDescriptor<CheckIn>(sortBy: [SortDescriptor(\.day, order: .forward)]))) ?? []
            let todayRow = all.first { Calendar.current.isDate($0.day, inSameDayAs: today) }
            let prior = all.filter { $0.day < today }
            return PhoneInputs(
                wellness: todayRow?.wellnessCheckIn,
                fingerTapToday: todayRow?.fingerTapCount,
                fingerTapHistory: prior.compactMap(\.fingerTapCount),
                jumpToday: todayRow?.jumpHeightCm,
                jumpHistory: prior.compactMap(\.jumpHeightCm))
        }
    }

    /// Compute today's readiness. Baselines use the *prior* 30 days so today's
    /// reading is scored against history, not against itself. `phone` carries the
    /// optional phone-only inputs (wellness check-in, finger-tap, jump) so the app
    /// works without a wearable.
    func computeToday(asOf now: Date = .now, phone: PhoneInputs = .none) async throws -> Result {
        let today = Calendar.current.startOfDay(for: now)

        async let hrvSeries = health.dailyHRV(days: 31)
        async let rhrSeries = health.dailyRestingHR(days: 31)
        async let sleepSeries = health.nightlySleep(days: 31)
        async let qualitySeries = health.nightlyDeepREMSleep(days: 31)
        async let respSeries = health.dailyRespiratoryRate(days: 31)
        async let tempSeries = health.dailyWristTemperature(days: 31)
        async let loadRatio = health.workoutLoadRatio()

        let (hrvToday, hrvBaseline) = split(try await hrvSeries, today: today)
        let (rhrToday, rhrBaseline) = split(try await rhrSeries, today: today)
        let (sleepToday, sleepBaseline) = split(try await sleepSeries, today: today)
        let (qualityToday, qualityBaseline) = split(try await qualitySeries, today: today)
        let (respToday, respBaseline) = split(try await respSeries, today: today)
        let (tempToday, tempBaseline) = split(try await tempSeries, today: today)
        let load = try await loadRatio

        let input = ReadinessInput(
            date: today,
            hrvSDNN: hrvToday, hrvBaseline: hrvBaseline,
            sleepSeconds: sleepToday, sleepBaseline: sleepBaseline,
            sleepQualitySeconds: qualityToday, sleepQualityBaseline: qualityBaseline,
            restingHR: rhrToday, rhrBaseline: rhrBaseline,
            respiratoryRate: respToday, respiratoryRateBaseline: respBaseline,
            wristTemperature: tempToday, wristTemperatureBaseline: tempBaseline,
            loadRatio: load,
            wellness: phone.wellness,
            fingerTapCount: phone.fingerTapToday,
            fingerTapBaseline: BaselineCalculator.baseline(from: phone.fingerTapHistory),
            countermovementJumpCm: phone.jumpToday,
            cmjBaseline: BaselineCalculator.baseline(from: phone.jumpHistory))

        return Result(
            output: engine.evaluate(input),
            hrvSDNN: hrvToday, sleepSeconds: sleepToday, restingHR: rhrToday)
    }

    /// Persist today's `DailyReadiness`, updating the existing row **in place** when
    /// one exists (late wearable data recomputing a living value) so its identity
    /// and the session-start freeze survive; inserting only on first compute of the
    /// day. Returns the row so callers can detect a verdict change.
    @MainActor
    @discardableResult
    func persist(_ result: Result, on date: Date = .now, into context: ModelContext) throws -> DailyReadiness {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.date == day })
        let row: DailyReadiness
        if let existing = try context.fetch(descriptor).first {
            existing.apply(result.output, hrvSDNN: result.hrvSDNN,
                           sleepSeconds: result.sleepSeconds, restingHR: result.restingHR)
            row = existing
        } else {
            row = DailyReadiness(
                date: day, output: result.output,
                hrvSDNN: result.hrvSDNN, sleepSeconds: result.sleepSeconds, restingHR: result.restingHR)
            context.insert(row)
        }
        try context.save()
        return row
    }

    /// Separate today's reading from the baseline window (everything before today).
    private func split(_ series: [DailyMetric], today: Date) -> (today: Double?, baseline: Baseline?) {
        let todayValue = series.first(where: { Calendar.current.isDate($0.day, inSameDayAs: today) })?.value
        let priorValues = series.filter { $0.day < today }.map(\.value)
        return (todayValue, BaselineCalculator.baseline(from: priorValues))
    }
}
