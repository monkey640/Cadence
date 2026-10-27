import SwiftUI
import SwiftData
import CadenceCore

/// Loads per-signal history for sparklines: HealthKit series for wearable
/// signals, `CheckIn` rows for subjective/phone-test signals.
@MainActor
@Observable
final class SignalHistoryModel {
    private(set) var series: [String: [TrendPoint]] = [:]

    private let health: HealthDataProviding
    init(health: HealthDataProviding = HealthKitService()) { self.health = health }

    func load(context: ModelContext) async {
        async let hrv = try? health.dailyHRV(days: 31)
        async let sleep = try? health.nightlySleep(days: 31)
        async let quality = try? health.nightlyDeepREMSleep(days: 31)
        async let rhr = try? health.dailyRestingHR(days: 31)
        async let resp = try? health.dailyRespiratoryRate(days: 31)
        async let temp = try? health.dailyWristTemperature(days: 31)

        var result: [String: [TrendPoint]] = [:]
        result["hrv"] = points(await hrv)
        result["sleep"] = points(await sleep)
        result["sleepQuality"] = points(await quality)
        result["rhr"] = points(await rhr)
        result["respiratory"] = points(await resp)
        result["wristTemp"] = points(await temp)

        let checkIns = ((try? context.fetch(
            FetchDescriptor<CheckIn>(sortBy: [SortDescriptor(\.day, order: .forward)]))) ?? [])
        result["tap"] = checkIns.compactMap { row in
            row.fingerTapCount.map { TrendPoint(date: row.day, value: $0) }
        }
        result["jump"] = checkIns.compactMap { row in
            row.jumpHeightCm.map { TrendPoint(date: row.day, value: $0) }
        }
        result["wellness"] = checkIns.compactMap { row in
            guard let sleep = row.wellnessSleep, let sore = row.wellnessSoreness,
                  let fatigue = row.wellnessFatigue, let stress = row.wellnessStress,
                  let mood = row.wellnessMood else { return nil }
            let avg = Double(sleep + sore + fatigue + stress + mood) / 5
            return TrendPoint(date: row.day, value: avg)
        }
        // Per-question series so a tapped subjective lane deep-links to its own
        // history, not the composite.
        let questions: [(String, (CheckIn) -> Int?)] = [
            ("subjSleep", \.wellnessSleep), ("subjSoreness", \.wellnessSoreness),
            ("subjFatigue", \.wellnessFatigue), ("subjStress", \.wellnessStress),
            ("subjMood", \.wellnessMood),
        ]
        for (id, value) in questions {
            result[id] = checkIns.compactMap { row in
                value(row).map { TrendPoint(date: row.day, value: Double($0)) }
            }
        }
        series = result
    }

    private func points(_ metrics: [DailyMetric]?) -> [TrendPoint] {
        (metrics ?? []).map { TrendPoint(date: $0.day, value: $0.value) }
    }

    /// Mean of the values before today — the "your 30-day avg" reference.
    func baseline(for id: String, today: Date = .now) -> Double? {
        let start = Calendar.current.startOfDay(for: today)
        let prior = (series[id] ?? []).filter { $0.date < start }.map(\.value)
        guard !prior.isEmpty else { return nil }
        return prior.reduce(0, +) / Double(prior.count)
    }

    /// Today's raw reading from the series, if it landed.
    func todayValue(for id: String, today: Date = .now) -> Double? {
        (series[id] ?? []).last(where: {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        })?.value
    }

    /// Last 14 days for the sparkline.
    func sparkline(for id: String) -> [TrendPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        return (series[id] ?? []).filter { $0.date >= cutoff }
    }
}

/// The full grouped breakdown: every signal, present or not, wearable /
/// subjective / phone tests. Missing signals are grayed out and explained —
/// never penalized. Rows push per-signal detail; Today's rings deep-link here.
struct SignalBreakdownSheet: View {
    let snapshot: DailyReadiness
    var focusSignalID: String?

    @Environment(\.modelContext) private var context
    @State private var model = SignalHistoryModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(SignalDescriptor.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(SignalDescriptor.all.filter { $0.group == group }) { descriptor in
                            row(descriptor)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Today's signals")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let descriptor = SignalDescriptor.by(id: id) {
                    SignalDetailView(descriptor: descriptor, snapshot: snapshot, model: model)
                }
            }
        }
        .preferredColorScheme(Theme.scheme)
        .task {
            await model.load(context: context)
            // Deep link from a tapped ring — a subjective question opens its OWN
            // detail now (by(id:) resolves the per-question descriptors), instead
            // of folding into the wellness composite.
            if let focus = focusSignalID, SignalDescriptor.by(id: focus) != nil {
                path.append(focus)
            }
        }
    }

    private func row(_ descriptor: SignalDescriptor) -> some View {
        let score = subscore(descriptor.id)
        return NavigationLink(value: descriptor.id) {
            HStack(spacing: 12) {
                Image(systemName: descriptor.icon)
                    .frame(width: 26)
                    .foregroundStyle(score == nil ? Theme.textSecondary : Theme.textPrimary)
                Text(descriptor.label)
                    .foregroundStyle(score == nil ? Theme.textSecondary : Theme.textPrimary)
                Spacer()
                statusPill(score)
            }
        }
    }

    @ViewBuilder private func statusPill(_ score: Double?) -> some View {
        let (text, color) = SignalStatus.pill(for: score)
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func subscore(_ id: String) -> Double? {
        SignalStatus.subscore(id: id, snapshot: snapshot)
    }
}

/// Shared subscore→status mapping so rows and detail agree.
enum SignalStatus {
    static func subscore(id: String, snapshot: DailyReadiness) -> Double? {
        switch id {
        case "hrv": return snapshot.hrvScore
        case "sleep": return snapshot.sleepScore
        case "sleepQuality": return snapshot.sleepQualityScore
        case "rhr": return snapshot.rhrScore
        case "respiratory": return snapshot.respiratoryScore
        case "wristTemp": return snapshot.wristTempScore
        case "load": return snapshot.loadScore
        case "wellness": return snapshot.wellnessScore
        case "tap": return snapshot.fingerTapScore
        case "jump": return snapshot.jumpScore
        default: return nil
        }
    }

    static func pill(for score: Double?) -> (String, Color) {
        guard let score else { return ("No data", Theme.textSecondary) }
        if score >= 66 { return ("Good", Theme.push) }
        if score >= 45 { return ("Below avg", Theme.hold) }
        return ("Well below avg", Theme.backOff)
    }

    static func read(_ descriptor: SignalDescriptor, score: Double?, snapshot: DailyReadiness) -> String {
        guard let score else { return missingCopy(descriptor, snapshot: snapshot) }
        if score >= 66 { return descriptor.goodRead }
        if score >= 45 { return descriptor.steadyRead }
        return descriptor.lowRead
    }

    /// True when *any* wearable sensor signal has data today — i.e. a watch is
    /// present and sharing something (load is workout-derived, not a sensor stream,
    /// so it doesn't count).
    static func hasAnyWearableSensor(_ snapshot: DailyReadiness) -> Bool {
        snapshot.hrvScore != nil || snapshot.sleepScore != nil || snapshot.rhrScore != nil
            || snapshot.sleepQualityScore != nil || snapshot.respiratoryScore != nil
            || snapshot.wristTempScore != nil
    }

    /// The "no data" copy, distinguishing two very different situations so we never
    /// tell an athlete to connect a watch they're already wearing:
    ///  - no wearable data at all → the signal's own "connect a wearable" line;
    ///  - a wearable is present but not sharing *this* sensor (the Garmin case —
    ///    Garmin never writes HRV / respiratory rate / wrist temp to Apple Health).
    static func missingCopy(_ descriptor: SignalDescriptor, snapshot: DailyReadiness) -> String {
        if descriptor.group == .wearable, descriptor.id != "load", hasAnyWearableSensor(snapshot) {
            return "Your wearable isn't sharing this signal with Apple Health."
        }
        return descriptor.missingRead
    }
}

/// One signal, in full: today's value, vs-baseline delta, status, 14-day
/// sparkline with the baseline rule, and the plain-language read.
struct SignalDetailView: View {
    let descriptor: SignalDescriptor
    let snapshot: DailyReadiness
    let model: SignalHistoryModel

    private var score: Double? {
        if descriptor.id.hasPrefix("subj") {
            // 1–5 self-rating → 0–100, matching the engine's subjective mapping.
            return todayValue.map { ($0 - 1) / 4 * 100 }
        }
        return SignalStatus.subscore(id: descriptor.id, snapshot: snapshot)
    }

    /// Today's raw value: snapshot fields first (they're the scored inputs),
    /// then the loaded series, then check-in data surfaced through the series.
    private var todayValue: Double? {
        switch descriptor.id {
        case "hrv": return snapshot.hrvSDNN ?? model.todayValue(for: "hrv")
        case "sleep": return snapshot.sleepSeconds ?? model.todayValue(for: "sleep")
        case "rhr": return snapshot.restingHR ?? model.todayValue(for: "rhr")
        default: return model.todayValue(for: descriptor.id)
        }
    }

    private var baseline: Double? { model.baseline(for: descriptor.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if score != nil || todayValue != nil {
                    valueCard
                    sparklineCard
                } else {
                    missingCard
                }

                Text(SignalStatus.read(descriptor, score: score, snapshot: snapshot))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .cadenceCard()

                if isDraftWeighted { draftNote }
            }
            .padding(20)
        }
        .cadenceBackground()
        .navigationTitle(descriptor.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// True for the signals whose engine weight is still a first-pass estimate.
    /// `ReadinessConfig` sets `phoneSignalWeightsAreDraft` precisely so the UI
    /// can say so out loud — the check-in, tap and jump weights are unvalidated,
    /// while the wearable signals rest on published physiology.
    private var isDraftWeighted: Bool {
        guard ReadinessConfig.standard.phoneSignalWeightsAreDraft else { return false }
        return descriptor.group == .phoneTests
            || descriptor.group == .subjective
    }

    /// Deliberately plain, not alarming: it tells the athlete how much to lean
    /// on this one signal without undermining the score as a whole.
    private var draftNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "flask.fill")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text("How heavily this signal counts toward your score is still a first-pass estimate, not a validated number. Read it as one input among several — the wearable signals are on firmer ground.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cadenceCard()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: descriptor.icon)
                .font(.title2)
                .foregroundStyle(Theme.textPrimary)
            Text(descriptor.label)
                .font(.displayBlack(24))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            pill
        }
    }

    private var pill: some View {
        let (text, color) = SignalStatus.pill(for: score)
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private var valueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let value = todayValue, let format = descriptor.format {
                Text(format(value))
                    .font(.timingBoard(36, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            } else if let score {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(score.rounded()))")
                        .font(.timingBoard(36, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("/ 100 vs your baseline")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let baseline, let value = todayValue, baseline != 0, let format = descriptor.format {
                let deltaPct = (value - baseline) / abs(baseline) * 100
                HStack(spacing: 6) {
                    Text("Your 30-day avg: \(format(baseline))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(String(format: "%@ %.0f%%", deltaPct >= 0 ? "↑" : "↓", abs(deltaPct)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SignalStatus.pill(for: score).1)
                }
            }
        }
        .cadenceCard()
    }

    @ViewBuilder private var sparklineCard: some View {
        let points = model.sparkline(for: descriptor.id)
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("LAST 14 DAYS")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textSecondary)
                Sparkline(points: points, baseline: baseline,
                          color: SignalStatus.pill(for: score).1)
                    .accessibilityLabel("\(descriptor.label), 14 day trend")
            }
            .cadenceCard()
        }
    }

    private var missingCard: some View {
        Text(SignalStatus.missingCopy(descriptor, snapshot: snapshot))
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .cadenceCard()
    }
}
