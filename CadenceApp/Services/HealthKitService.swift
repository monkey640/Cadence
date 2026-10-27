import Foundation
import HealthKit
import CadenceCore

/// Concrete HealthKit implementation of `HealthDataProviding`.
///
/// Identifiers verified against Apple's docs:
///  - HRV: `.heartRateVariabilitySDNN`, unit `HKUnit.secondUnit(with: .milli)` (ms).
///    Apple Watch only records SDNN; we surface it as "HRV".
///  - Resting HR: `.restingHeartRate`, unit count/min.
///  - Sleep: `.sleepAnalysis`; "asleep" is the sum of the granular asleep stages
///    (`asleepCore/Deep/REM/Unspecified`), explicitly EXCLUDING `inBed` and `awake`.
///  - Workouts: `HKObjectType.workoutType()`.
final class HealthKitService: HealthDataProviding, @unchecked Sendable {
    private let store = HKHealthStore()

    private let hrvType  = HKQuantityType(.heartRateVariabilitySDNN)
    private let rhrType  = HKQuantityType(.restingHeartRate)
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let workoutType = HKObjectType.workoutType()
    private let respiratoryType = HKQuantityType(.respiratoryRate)
    private let wristTempType = HKQuantityType(.appleSleepingWristTemperature)

    private let hrvUnit = HKUnit.secondUnit(with: .milli)            // milliseconds
    private let bpmUnit = HKUnit.count().unitDivided(by: .minute())  // count/min
    private let tempUnit = HKUnit.degreeCelsius()

    /// The sleep-analysis category values that represent actual sleep.
    private let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]
    /// Restorative ("quality") sleep — deep + REM only.
    private let deepREMValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        let read: Set<HKObjectType> = [hrvType, rhrType, sleepType, workoutType, respiratoryType, wristTempType]
        try await store.requestAuthorization(toShare: [], read: read)
    }

    // MARK: - Live updates (late-synced data)

    /// The types whose late arrival should recompute today's readiness. HRV, sleep,
    /// and resting HR are the core recovery signals; a change in any is worth a
    /// rebuild. (No entitlement beyond the plain HealthKit one is required for
    /// background delivery.)
    private var liveTypes: [HKSampleType] { [hrvType, sleepType, rhrType] }

    private var observerQueries: [HKObserverQuery] = []

    /// Ask HealthKit to wake us (even backgrounded) when new samples land for the
    /// core recovery types. Hourly is plenty — recovery data isn't second-to-second.
    func enableBackgroundDelivery() {
        guard isAvailable else { return }
        for type in liveTypes {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    /// Register observer queries; `onChange` fires whenever Apple Health receives
    /// new samples for a core type (this is how late-synced Garmin data flows in
    /// with no user action). The caller recomputes; we call the completion handler
    /// so HealthKit knows we're done.
    func startObserving(onChange: @escaping @Sendable () -> Void) {
        guard isAvailable else { return }
        for type in liveTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                onChange()
                completion()
            }
            store.execute(query)
            observerQueries.append(query)
        }
    }

    // MARK: - Quantity daily averages

    func dailyHRV(days: Int) async throws -> [DailyMetric] {
        try await dailyAverages(quantityType: hrvType, unit: hrvUnit, days: days)
    }

    func dailyRestingHR(days: Int) async throws -> [DailyMetric] {
        try await dailyAverages(quantityType: rhrType, unit: bpmUnit, days: days)
    }

    /// Apple Watch records respiratory rate during sleep, so the daily average is
    /// effectively the overnight value.
    func dailyRespiratoryRate(days: Int) async throws -> [DailyMetric] {
        try await dailyAverages(quantityType: respiratoryType, unit: bpmUnit, days: days)
    }

    /// One sleeping wrist-temperature reading per night (Series 8+/Ultra).
    func dailyWristTemperature(days: Int) async throws -> [DailyMetric] {
        try await dailyAverages(quantityType: wristTempType, unit: tempUnit, days: days)
    }

    /// Daily `.discreteAverage` over the trailing window, bucketed on an **overnight
    /// window** (6 PM the prior evening → 6 PM) rather than midnight. Watches (and
    /// especially late-syncing third-party sources like Garmin) timestamp overnight
    /// recovery metrics across the evening and early morning; anchoring at 6 PM
    /// attributes both halves to the day they lead into, instead of splitting a
    /// night across the midnight boundary. Each bucket is labelled by the calendar
    /// day it ends on — the same rule sleep uses (attributed to the night it ends).
    private func dailyAverages(quantityType: HKQuantityType, unit: HKUnit, days: Int) async throws -> [DailyMetric] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: .now)
        guard let windowStart = cal.date(byAdding: .day, value: -days, to: todayStart),
              // Extend the enumeration through the bucket that ends at 6 PM today.
              let enumEnd = cal.date(byAdding: .day, value: 1, to: todayStart),
              // Any 6 PM instant is a valid bucket boundary for the daily collection.
              let anchor = cal.date(bySettingHour: 18, minute: 0, second: 0, of: todayStart)
        else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: .now, options: [.strictStartDate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                guard let results else { continuation.resume(returning: []); return }
                var metrics: [DailyMetric] = []
                results.enumerateStatistics(from: windowStart, to: enumEnd) { stat, _ in
                    if let avg = stat.averageQuantity() {
                        // Attribute the 6 PM→6 PM bucket to the day it ends on.
                        let day = cal.startOfDay(for: stat.endDate)
                        metrics.append(DailyMetric(day: day, value: avg.doubleValue(for: unit)))
                    }
                }
                continuation.resume(returning: metrics)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    func lastNightSleepSeconds() async throws -> Double? {
        let nights = try await nightlySleep(days: 1)
        return nights.last?.value
    }

    /// Total asleep seconds per night (all stages).
    func nightlySleep(days: Int) async throws -> [DailyMetric] {
        try await nightlyAsleep(values: asleepValues, days: days)
    }

    /// Deep + REM ("quality") seconds per night.
    func nightlyDeepREMSleep(days: Int) async throws -> [DailyMetric] {
        try await nightlyAsleep(values: deepREMValues, days: days)
    }

    /// Sums the given sleep-stage values per night, merging overlaps/duplicates.
    /// A "night" is attributed to the calendar day it ends on.
    private func nightlyAsleep(values: Set<Int>, days: Int) async throws -> [DailyMetric] {
        let cal = Calendar.current
        let end = Date.now
        guard let start = cal.date(byAdding: .day, value: -days - 1, to: cal.startOfDay(for: end)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        var intervalsByNight: [Date: [(start: Double, end: Double)]] = [:]
        for sample in samples where values.contains(sample.value) {
            let night = cal.startOfDay(for: sample.endDate)
            intervalsByNight[night, default: []].append(
                (start: sample.startDate.timeIntervalSince1970,
                 end: sample.endDate.timeIntervalSince1970))
        }
        return intervalsByNight.keys.sorted().map { night in
            DailyMetric(day: night, value: SleepIntervalMerger.totalDuration(of: intervalsByNight[night]!))
        }
    }

    // MARK: - Workout load (acute:chronic ratio)

    func workoutLoadRatio() async throws -> Double? {
        let cal = Calendar.current
        let now = Date.now
        guard let start = cal.date(byAdding: .day, value: -28, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [.strictStartDate])

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
        guard !workouts.isEmpty else { return nil }

        // Load proxy = workout duration in minutes (simple, intensity-agnostic for MVP).
        guard let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now) else { return nil }
        let acute = workouts.filter { $0.endDate >= sevenDaysAgo }
            .reduce(0.0) { $0 + $1.duration / 60 }
        let chronicTotal = workouts.reduce(0.0) { $0 + $1.duration / 60 }
        let chronicWeekly = chronicTotal / 4.0   // 28 days → weekly average
        guard chronicWeekly > 0 else { return nil }
        return acute / chronicWeekly
    }
}

enum HealthKitError: Error { case unavailable }
