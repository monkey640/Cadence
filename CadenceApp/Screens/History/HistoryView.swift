import SwiftUI
import SwiftData
import CadenceCore

/// The season, as a continuous timeline: sessions grouped by week under month
/// headers, with checked-in-but-didn't-train days shown as faint slots so the
/// run reads unbroken. A season-stats header sits on top; a PR chip filters to
/// the days that mattered most.
struct HistoryView: View {
    @Query(sort: \TrainingSession.date, order: .reverse) private var sessions: [TrainingSession]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readiness: [DailyReadiness]
    @Environment(\.modelContext) private var context
    @Environment(TabRouter.self) private var router: TabRouter?
    @State private var showBuilder = false
    @State private var prOnly = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    timeline
                }
            }
            .navigationTitle("History")
            .sheet(isPresented: $showBuilder) { CustomWorkoutBuilderView() }
            .cadenceBackground()
        }
        .preferredColorScheme(Theme.scheme)
    }

    // MARK: - Timeline

    private var timeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                seasonHeader

                if timelineItems.isEmpty {
                    Text(prOnly ? "No PRs yet — log a timed rep faster than your best to set one."
                                : "Nothing logged yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 8)
                }

                ForEach(timelineItems) { item in
                    if let month = item.monthHeader {
                        Text(month)
                            .font(.displayBlack(20))
                            .tracking(-0.3)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 4)
                    }
                    weekSection(item.week)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Season header

    private var seasonHeader: some View {
        let totalReps = sessions.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.completedSets } }
        let prCount = sessions.filter { $0.sets.contains { $0.wasPR } }.count
        let streak = StreakService.currentStreak(context: context).days
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("Season").sectionLabel()
                Spacer()
                Button { showBuilder = true } label: {
                    Label("Log workout", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.brand.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log a custom workout")
            }
            HStack(alignment: .top, spacing: 8) {
                stat(compact(sessions.count), "sessions")
                stat(compact(totalReps), "reps")
                stat(compact(prCount), "PRs")
                stat(compact(streak), "streak")
            }
            prChip
        }
        .padding(18)
        .cadenceCard(padding: 0)
    }

    /// Scoreboard-style compaction: a full season's rep count runs to four digits,
    /// which crowds the neighbouring stat. 1459 → "1.5k".
    private func compact(_ n: Int) -> String {
        guard n >= 1000 else { return "\(n)" }
        let thousands = Double(n) / 1000
        return thousands >= 10 ? "\(Int(thousands.rounded()))k"
                               : String(format: "%.1fk", thousands)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // A full season reaches four digits (1,400+ reps) — shrink to fit its
            // column rather than colliding with the next stat.
            Text(value)
                .font(.timingBoard(26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .sectionLabel()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var prChip: some View {
        Button { prOnly.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill").font(.system(size: 10))
                Text("PRs only").font(.caption.weight(.semibold))
            }
            .foregroundStyle(prOnly ? Theme.background : Theme.brand)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(prOnly ? Theme.brand : Theme.brand.opacity(0.14))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prOnly ? "Showing PR sessions only. Tap to show all." : "Show PR sessions only")
    }

    // MARK: - Week section

    private func weekSection(_ week: WeekGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(week.label).sectionLabel()
            VStack(spacing: 0) {
                ForEach(Array(week.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { LaneLine() }
                    entryRow(entry)
                }
            }
            .cadenceCard(padding: 0)
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: DayEntry) -> some View {
        if let session = entry.session {
            NavigationLink {
                SessionLogView(session: session)
            } label: {
                sessionRow(session, on: entry.date)
            }
            .buttonStyle(.plain)
        } else {
            readinessRow(entry)
        }
    }

    /// A trained day: full row with type, that morning's readiness, volume, PR.
    private func sessionRow(_ session: TrainingSession, on date: Date) -> some View {
        let planned = session.sets.reduce(0) { $0 + $1.plannedSets }
        let completed = session.sets.reduce(0) { $0 + $1.completedSets }
        return HStack(spacing: 12) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    SessionTypeBadge(text: SessionTypeLabel.text(for: session),
                                     color: SessionTypeLabel.color(for: session))
                    if session.hadCheckIn {
                        HStack(spacing: 3) {
                            Text("\(Int(session.readinessScore.rounded()))")
                                .font(.caption2.weight(.bold)).monospacedDigit()
                            Text(session.verdict.badgeText)
                                .font(.system(size: 9, weight: .black))
                        }
                        .foregroundStyle(session.verdict.color)
                    }
                    if planned > 0 {
                        Text("\(completed)/\(planned) \(session.isRecovery ? "items" : "reps")")
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer(minLength: 8)
            if session.sets.contains(where: { $0.wasPR }) {
                Image(systemName: "trophy.fill").font(.caption).foregroundStyle(Theme.brand)
                    .accessibilityLabel("PR set")
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// A checked-in-but-didn't-train day: a faint slot keeping the season unbroken.
    private func readinessRow(_ entry: DayEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, alignment: .leading)
            if let r = entry.readiness {
                Circle().fill(r.verdict.color).frame(width: 7, height: 7)
                Text("Readiness \(Int(r.score.rounded()))")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("No session")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .opacity(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.readiness.map {
            "\(entry.date.formatted(.dateTime.weekday().day())): readiness \(Int($0.score.rounded())), no session"
        } ?? "")
    }

    // MARK: - Grouping

    private struct DayEntry: Identifiable {
        let date: Date
        let session: TrainingSession?
        let readiness: DailyReadiness?
        let id: String
    }

    private struct WeekGroup: Identifiable {
        let weekStart: Date
        let entries: [DayEntry]
        var id: Date { weekStart }
        /// Which month this week belongs to for the header above it. Entries are
        /// newest-first, so a week straddling a month boundary is labelled by its
        /// most recent day — the one the reader sees first. Using `weekStart`
        /// instead put an "August" header directly above Sep 1-3 rows.
        var monthAnchor: Date { entries.first?.date ?? weekStart }

        /// "This week" for the current week, else "Week of Jul 6".
        var label: String {
            let cal = Calendar.current
            if cal.isDate(weekStart, equalTo: .now, toGranularity: .weekOfYear) { return "This week" }
            return "Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private struct TimelineItem: Identifiable {
        let monthHeader: String?
        let week: WeekGroup
        var id: Date { week.weekStart }
    }

    /// One entry per logged session, plus checked-in-but-untrained days for
    /// continuity, newest first. Filtered to PR days when the chip is on.
    private var dayEntries: [DayEntry] {
        let cal = Calendar.current
        let sessionDays = Set(sessions.map { cal.startOfDay(for: $0.date) })
        let readinessByDay = Dictionary(
            readiness.map { (cal.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })

        var entries: [DayEntry] = sessions.map { session in
            let day = cal.startOfDay(for: session.date)
            return DayEntry(date: day, session: session, readiness: readinessByDay[day],
                            id: "s-\(session.persistentModelID.hashValue)")
        }
        for (day, r) in readinessByDay where !sessionDays.contains(day) {
            entries.append(DayEntry(date: day, session: nil, readiness: r,
                                    id: "r-\(day.timeIntervalSince1970)"))
        }
        let sorted = entries.sorted { $0.date > $1.date }
        guard prOnly else { return sorted }
        return sorted.filter { $0.session?.sets.contains { $0.wasPR } == true }
    }

    private var weekGroups: [WeekGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: dayEntries) { entry in
            cal.dateInterval(of: .weekOfYear, for: entry.date)?.start ?? entry.date
        }
        return grouped
            .map { WeekGroup(weekStart: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.weekStart > $1.weekStart }
    }

    /// Weeks with a month header emitted whenever the month changes going down.
    private var timelineItems: [TimelineItem] {
        var out: [TimelineItem] = []
        var lastMonth: String?
        for week in weekGroups {
            let month = week.monthAnchor.formatted(.dateTime.month(.wide).year())
            out.append(TimelineItem(monthHeader: month == lastMonth ? nil : month, week: week))
            lastMonth = month
        }
        return out
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundStyle(Theme.textSecondary)
            Text("Your first session gets logged here.")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Complete this morning's check-in to start.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Go to today's check-in") { router?.selection = .today }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Session-type derivation shared by History rows and the log detail.
enum SessionTypeLabel {
    static func text(for session: TrainingSession) -> String {
        if session.isRecovery { return "Recovery" }
        if session.isCustom { return "Custom" }
        let title = session.title.lowercased()
        if title.contains("tempo") { return "Tempo" }
        if title.contains("accel") || title.contains("speed") || title.contains("velocity")
            || title.contains("sprint") || title.contains("start") { return "Speed" }
        if title.contains("endurance") { return "Endurance" }
        if title.contains("strength") || title.contains("circuit") { return "Strength" }
        if title.contains("rest") || title.contains("recovery") { return "Recovery" }
        return "Session"
    }

    static func color(for session: TrainingSession) -> Color {
        switch text(for: session) {
        case "Speed": return Theme.brand
        case "Endurance": return Theme.push
        case "Tempo": return Theme.hold
        case "Recovery": return Theme.textSecondary
        default: return Theme.textSecondary
        }
    }
}
