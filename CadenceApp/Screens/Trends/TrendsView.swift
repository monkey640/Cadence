import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Trajectory over time — a story, not a data dump: readiness with verdict
/// colors, the push/recover rhythm (load vs readiness), PRs, and signal trends.
/// Shared x-axis for every trend chart: a 7-day stride labelled as numeric
/// month/day ("9/3"). Charts' default abbreviated-month label clipped to a
/// single letter at the trailing edge of the 30-day window; four narrow
/// characters always fit.
@AxisContentBuilder
func cadenceDayAxis() -> some AxisContent {
    AxisMarks(values: .stride(by: .day, count: 7)) {
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
    }
}

struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DailyReadiness.date, order: .forward) private var readiness: [DailyReadiness]
    @Query(sort: \TrainingSession.date, order: .forward) private var sessions: [TrainingSession]
    @Query(sort: \PersonalRecord.achievedOn, order: .reverse) private var records: [PersonalRecord]
    @Query private var profiles: [AthleteProfile]
    @State private var model = TrendsViewModel()
    @State private var selectedDay: DailyReadiness?

    private var last30: [DailyReadiness] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return readiness.filter { $0.date >= cutoff }
    }

    /// Weekly recovery report from already-stored readiness + session data.
    private var weeklyReport: WeeklyReport? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: today),
              let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: today) else { return nil }
        let thisWeek = readiness.filter { $0.date >= weekAgo }
        let priorWeek = readiness.filter { $0.date >= twoWeeksAgo && $0.date < weekAgo }
        let scaled = sessions.filter { $0.date >= weekAgo && $0.wasAdjusted }.map(\.volumeMultiplier)
        return WeeklyReportBuilder.build(
            readinessThisWeek: thisWeek.map(\.score),
            scaledMultipliers: scaled,
            hrvThisWeek: thisWeek.compactMap(\.hrvSDNN),
            hrvPriorWeek: priorWeek.compactMap(\.hrvSDNN))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let report = weeklyReport, last30.count >= 4 {
                        WeeklyReportCard(report: report)
                    }
                    readinessCard
                    loadRhythmCard
                    prTracker
                    signalTrends
                }
                .padding(20)
            }
            .navigationTitle("Trends")
            .cadenceBackground()
            .task { await model.load() }
            .refreshable { await model.load() }
        }
        .preferredColorScheme(Theme.scheme)
    }

    // MARK: - Readiness over time

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Readiness").font(.headline).foregroundStyle(Theme.textPrimary)
                if let delta = readinessDelta { deltaChip(delta) }
                Spacer()
                if let latest = last30.last {
                    Text("\(Int(latest.score.rounded()))")
                        .font(.timingBoard(20, weight: .bold))
                        .foregroundStyle(latest.verdict.color)
                }
            }

            Chart(last30, id: \.date) { day in
                LineMark(x: .value("Day", day.date), y: .value("Score", day.score))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Day", day.date), y: .value("Score", day.score))
                    .foregroundStyle(day.verdict.color)
                    .symbolSize(45)
            }
            .chartYScale(domain: readinessDomain)
            .chartXAxis { cadenceDayAxis() }
                .chartXScale(range: .plotDimension(endPadding: 16))
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let xInPlot = location.x - geo[plotFrame].origin.x
                            guard let date: Date = proxy.value(atX: xInPlot) else { return }
                            selectedDay = nearestDay(to: date)
                        }
                }
            }
            .frame(height: 150)
            .accessibilityLabel("Readiness over the last 30 days, \(last30.count) days recorded. Tap a day for its breakdown.")

            HStack {
                legend
                Spacer()
                if last30.count > 1 {
                    Text("Tap a day")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if last30.count < 7 {
                Text("Trends sharpen after a week of check-ins — \(last30.count) day\(last30.count == 1 ? "" : "s") so far.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cadenceCard(padding: 20)
        .sheet(item: $selectedDay) { day in
            SignalBreakdownSheet(snapshot: day, focusSignalID: nil)
        }
    }

    /// A week-over-week readiness change chip (avg this week vs last).
    private func deltaChip(_ delta: Int) -> some View {
        let color = delta > 0 ? Theme.push : (delta < 0 ? Theme.hold : Theme.textSecondary)
        let symbol = delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "arrow.right")
        return HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text("\(delta > 0 ? "+" : "")\(delta) vs last wk")
                .font(.caption2.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
        .accessibilityLabel("Readiness \(delta >= 0 ? "up" : "down") \(abs(delta)) versus last week")
    }

    /// Y-domain that fits the recorded scores (min span 30), clamped to 0–100 —
    /// so the line uses the card instead of hugging the middle of a fixed 0–100.
    private var readinessDomain: ClosedRange<Double> {
        let scores = last30.map(\.score)
        guard let lo = scores.min(), let hi = scores.max() else { return 0...100 }
        var lower = lo - 8, upper = hi + 8
        if upper - lower < 30 {
            let mid = (lower + upper) / 2
            lower = mid - 15; upper = mid + 15
        }
        return Swift.max(0, lower)...Swift.min(100, upper)
    }

    private var readinessDelta: Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: today),
              let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: today) else { return nil }
        let thisWeek = readiness.filter { $0.date >= weekAgo }.map(\.score)
        let priorWeek = readiness.filter { $0.date >= twoWeeksAgo && $0.date < weekAgo }.map(\.score)
        guard !thisWeek.isEmpty, !priorWeek.isEmpty else { return nil }
        let a = thisWeek.reduce(0, +) / Double(thisWeek.count)
        let b = priorWeek.reduce(0, +) / Double(priorWeek.count)
        return Int((a - b).rounded())
    }

    private func nearestDay(to date: Date) -> DailyReadiness? {
        last30.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Verdict.allCases, id: \.self) { verdict in
                HStack(spacing: 4) {
                    Circle().fill(verdict.color).frame(width: 7, height: 7)
                    Text(verdict.displayName)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Load vs readiness rhythm

    private struct LoadDay: Identifiable {
        let id = UUID()
        let date: Date
        let volume: Double     // completed meters (or reps when no distance)
    }

    private var loadDays: [LoadDay] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        return sessions
            .filter { $0.date >= cutoff && $0.isComplete && !$0.isRecovery }
            .map { session in
                let meters = session.sets.reduce(0.0) {
                    $0 + ($1.distanceMeters ?? 25) * Double($1.completedSets)
                }
                return LoadDay(date: session.date, volume: meters)
            }
            .filter { $0.volume > 0 }
    }

    @ViewBuilder private var loadRhythmCard: some View {
        let days = loadDays
        VStack(alignment: .leading, spacing: 12) {
            Text("The push / recover rhythm").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Bars are how much you did; the line is how ready you were. When training's matched to recovery, they rise and fall together.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if days.isEmpty {
                Text("Logged sessions land here — complete one to start the rhythm.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            } else {
                let maxVolume = max(days.map(\.volume).max() ?? 1, 1)
                Chart {
                    ForEach(days) { day in
                        BarMark(x: .value("Day", day.date, unit: .day),
                                y: .value("Volume", day.volume / maxVolume * 100))
                            .foregroundStyle(Theme.brand.opacity(0.55))
                    }
                    ForEach(last30, id: \.date) { day in
                        LineMark(x: .value("Day", day.date, unit: .day),
                                 y: .value("Readiness", day.score))
                            .foregroundStyle(Theme.textPrimary)
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis(.hidden)
                .chartXAxis { cadenceDayAxis() }
                .chartXScale(range: .plotDimension(endPadding: 16))
                .frame(height: 150)
                .accessibilityLabel("Training volume bars against the readiness line, last 30 days")
            }
        }
        .cadenceCard(padding: 20)
    }

    // MARK: - PR tracker

    private var prTracker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PR TRACKER")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 8)

            if records.isEmpty {
                Text("Log a timed rep in a session and your fastest marks collect here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(records, id: \.key) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.key)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(String(format: "%.2fs", record.bestTimeSeconds))
                                .font(.timingBoard(18, weight: .bold))
                                .foregroundStyle(Theme.brand)
                            Text(record.achievedOn.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                        // Trajectory toward the athlete's goal for their main event —
                        // the gap only, never a prediction.
                        if let goalLine = goalLine(for: record) {
                            Text(goalLine)
                                .font(.caption.weight(.medium)).monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 10)
                    if record.key != records.last?.key { LaneLine() }
                }
            }
        }
        .cadenceCard()
    }

    /// The gap from a PR to the athlete's goal, for their main event only.
    /// Trajectory, not prophecy — we state the distance, never predict arrival.
    private func goalLine(for record: PersonalRecord) -> String? {
        guard let profile = profiles.first,
              let goal = profile.goalTimeSeconds, goal > 0,
              record.key == profile.event.rawValue else { return nil }
        let gap = record.bestTimeSeconds - goal
        if gap <= 0 { return String(format: "Goal reached — target was %.2fs", goal) }
        return String(format: "%.2fs to goal (%.2fs)", gap, goal)
    }

    // MARK: - Signal trends

    private var signalTrends: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIGNAL TRENDS")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.textSecondary)

            SignalTrendCard(title: "HRV", unit: "ms", points: model.hrv)
            SignalTrendCard(title: "Sleep", unit: "h", points: model.sleepHours)
            SignalTrendCard(title: "Resting HR", unit: "bpm", points: model.restingHR)
        }
    }
}

/// A titled 30-day signal chart with the personal-baseline reference rule.
private struct SignalTrendCard: View {
    let title: String
    let unit: String
    let points: [TrendPoint]

    private var baseline: Double? {
        guard points.count >= 3 else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let latest = points.last {
                    Text(format(latest.value))
                        .font(.timingBoard(18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(unit).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }

            if points.count < 2 {
                Text("No data yet — this fills in from Apple Health.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                Chart {
                    if let baseline {
                        RuleMark(y: .value("Baseline", baseline))
                            .foregroundStyle(Theme.laneLine)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .topTrailing) {
                                Text("30-day avg")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                    }
                    ForEach(points) { point in
                        LineMark(x: .value("Day", point.date), y: .value(title, point.value))
                            .foregroundStyle(Theme.textPrimary)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Day", point.date), y: .value(title, point.value))
                            .foregroundStyle(.linearGradient(
                                colors: [Theme.textPrimary.opacity(0.15), .clear],
                                startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: autoRange)
                .chartXAxis { cadenceDayAxis() }
                .chartXScale(range: .plotDimension(endPadding: 16))
                .frame(height: 130)
                .accessibilityLabel("\(title), 30 day trend")
            }
        }
        .cadenceCard(padding: 20)
    }

    private var autoRange: ClosedRange<Double> {
        let values = points.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, 1)
        return (lo - pad)...(hi + pad)
    }

    private func format(_ value: Double) -> String {
        String(format: value < 10 ? "%.1f" : "%.0f", value)
    }
}

/// The weekly recovery report — a coach's note (takeaway) over three small
/// trend stats. All derived from stored data.
private struct WeeklyReportCard: View {
    let report: WeeklyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("THIS WEEK")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.textSecondary)

            Text(report.takeaway)
                .font(.title3)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            LaneLine()

            HStack(alignment: .top) {
                stat(title: "Lighter days",
                     value: "\(report.scaledSessions)",
                     detail: report.scaledSessions == 0 ? "full volume all week" : "~\(report.avgReductionPct)% lighter")
                Spacer()
                trendStat(title: "Readiness", trend: report.readinessTrend)
                Spacer()
                trendStat(title: "HRV base", trend: report.hrvBaselineTrend)
            }
        }
        .cadenceCard(padding: 20)
    }

    private func stat(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Theme.textSecondary)
            Text(value).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    private func trendStat(title: String, trend: WeeklyReport.Trend) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Theme.textSecondary)
            Label(word(trend), systemImage: icon(trend))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color(trend))
                .labelStyle(.titleAndIcon)
        }
    }

    private func word(_ t: WeeklyReport.Trend) -> String {
        switch t { case .up: return "Rising"; case .down: return "Easing"; case .flat: return "Steady" }
    }
    private func icon(_ t: WeeklyReport.Trend) -> String {
        switch t { case .up: return "arrow.up.right"; case .down: return "arrow.down.right"; case .flat: return "arrow.right" }
    }
    private func color(_ t: WeeklyReport.Trend) -> Color {
        switch t { case .up: return Theme.push; case .down: return Theme.hold; case .flat: return Theme.textSecondary }
    }
}
