import SwiftUI
import SwiftData
import CadenceCore

/// The full 12-week arc: week strip, phase structure, and every day of the
/// selected week — so the athlete always knows where they are and what's coming.
struct PlanTabView: View {
    @Query private var profiles: [AthleteProfile]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var readiness: [DailyReadiness]
    @Query private var sessions: [TrainingSession]
    /// Wrapper so the sheet gets an Identifiable without touching CadenceCore.
    private struct DaySelection: Identifiable {
        let day: PlanDay
        var id: Int { day.day }
    }

    @State private var selectedWeek: Int = 1
    @State private var selectedDay: DaySelection?

    private var profile: AthleteProfile? { profiles.first }
    private var template: PlanTemplate? {
        profile.flatMap { PlanLibraryLoader.template(for: $0.event) }
    }

    /// Week/day the athlete is on right now (1-based), from the plan start date.
    private var currentPosition: (week: Int, dayInWeek: Int)? {
        guard let start = profile?.planStartDate else { return nil }
        let cal = Calendar.current
        let elapsed = max(0, cal.dateComponents([.day],
            from: cal.startOfDay(for: start), to: cal.startOfDay(for: .now)).day ?? 0)
        return (elapsed / 7 + 1, elapsed % 7 + 1)
    }

    private var todayVerdict: Verdict? {
        readiness.first { Calendar.current.isDateInToday($0.date) }?.verdict
    }

    /// Count of completed sessions logged within a plan week's date range, so a
    /// week's "done" tick reflects real work — not just the calendar moving on.
    private func loggedSessions(inWeek week: Int) -> Int {
        guard let start = profile?.planStartDate else { return 0 }
        let cal = Calendar.current
        let weekStart = cal.date(byAdding: .day, value: (week - 1) * 7, to: cal.startOfDay(for: start)) ?? start
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return 0 }
        return sessions.filter { $0.isComplete && $0.date >= weekStart && $0.date < weekEnd }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if let template {
                    planBody(template)
                } else {
                    noPlan
                }
            }
            .navigationTitle("Plan")
            .cadenceBackground()
        }
        .preferredColorScheme(Theme.scheme)
        .onAppear {
            if let current = currentPosition { selectedWeek = min(current.week, template?.durationWeeks ?? 1) }
        }
        .sheet(item: $selectedDay) { selection in
            dayPreview(selection.day)
        }
    }

    private func planBody(_ template: PlanTemplate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                phaseArc(template)
                weekStrip(template)
                weekDetail(template)
            }
            .padding(20)
        }
    }

    // MARK: - Phase arc

    /// "Base → Speed Development → Peak" with week ranges — the plan's shape.
    private func phaseArc(_ template: PlanTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE ARC")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(template.phases.enumerated()), id: \.offset) { index, phase in
                        let isCurrent = PlanScheduler.phase(in: template, week: selectedWeek)?.name == phase.name
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase.name)
                                .font(.caption.weight(isCurrent ? .bold : .medium))
                                .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
                            Text("Weeks \(phase.weeks)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isCurrent ? Theme.surfaceSecondary : Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if index < template.phases.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.trailing, 28)   // room so the last phase clears the fade
                }
            }
            // Trailing fade — a quiet cue that the arc scrolls to more phases.
            .overlay(alignment: .trailing) {
                LinearGradient(colors: [Theme.background.opacity(0), Theme.background],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Week strip

    private func weekStrip(_ template: PlanTemplate) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(1...template.durationWeeks, id: \.self) { week in
                    let isCurrent = currentPosition?.week == week
                    // "Done" = a past week the athlete actually logged sessions in.
                    let isPast = (currentPosition?.week ?? 1) > week
                    let isDone = isPast && loggedSessions(inWeek: week) > 0
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { selectedWeek = week }
                    } label: {
                        VStack(spacing: 4) {
                            Text("W\(week)")
                                .font(.timingBoard(15, weight: .bold))
                                .foregroundStyle(selectedWeek == week ? Theme.background : Theme.textPrimary)
                            if isDone {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(selectedWeek == week ? Theme.background : Theme.push)
                            } else if isCurrent {
                                Circle().fill(selectedWeek == week ? Theme.background : Theme.brand)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .background(selectedWeek == week
                                    ? (isCurrent ? Theme.brand : Theme.textSecondary)
                                    : Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Week \(week)\(isCurrent ? ", current" : (isDone ? ", completed" : ""))")
                }
            }
        }
    }

    // MARK: - Week detail

    @ViewBuilder private func weekDetail(_ template: PlanTemplate) -> some View {
        if let phase = PlanScheduler.phase(in: template, week: selectedWeek) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.name)
                        .font(.displayBlack(22))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                    Text(phase.rationale)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let kept = PlanFitter.keptTrainingDays(
                    in: phase.weeklyMicrocycle,
                    trainingDays: profile?.weeklyTrainingDays ?? 7,
                    maxHighDays: profile?.experienceLevel.maxHighDays ?? 3)

                // The week as a start list — lane-ruled register rows, like Today.
                VStack(spacing: 0) {
                    ForEach(Array(phase.weeklyMicrocycle.enumerated()), id: \.element.day) { index, day in
                        if index > 0 { LaneLine() }
                        dayRow(day, trimmed: PlanFitter.isTrimmedToRest(day, kept: kept))
                    }
                }
                .cadenceCard(padding: 0)
            }
        }
    }

    private func dayRow(_ day: PlanDay, trimmed: Bool) -> some View {
        let isToday = currentPosition?.week == selectedWeek && currentPosition?.dayInWeek == day.day
        let accent: Color = todayVerdict?.color ?? Theme.brand
        return Button {
            selectedDay = DaySelection(day: day)
        } label: {
            HStack(spacing: 12) {
                // Leading accent bar marks today; a plain slot otherwise.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isToday ? accent : .clear)
                    .frame(width: 3, height: 34)

                Text("D\(day.day)")
                    .font(.timingBoard(14, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(trimmed ? "Rest day" : day.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if isToday {
                            Text("TODAY")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(accent)
                        }
                    }
                    HStack(spacing: 8) {
                        SessionTypeBadge(text: typeLabel(day, trimmed: trimmed),
                                         color: typeColor(day, trimmed: trimmed))
                        if let volume = volumeSummary(day), !trimmed {
                            Text(volume)
                                .font(.caption2).monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(isToday ? accent.opacity(0.07) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayPreview(_ day: PlanDay) -> some View {
        let isToday = currentPosition?.week == selectedWeek
            && currentPosition?.dayInWeek == day.day
        return NavigationStack {
            PlanDayDetailView(day: day, isToday: isToday,
                              intent: "Volumes shown are the plan's — they'll be scaled to your readiness that morning.")
                .navigationTitle(day.name)
                .navigationBarTitleDisplayMode(.inline)
                .cadenceBackground()
        }
        .preferredColorScheme(Theme.scheme)
    }

    // MARK: - Day metadata

    /// Speed / Endurance / Tempo / Strength / Recovery — from the day's blocks.
    private func typeLabel(_ day: PlanDay, trimmed: Bool) -> String {
        if trimmed || day.load == .rest { return "Recovery" }
        let types = day.blocks.compactMap(\.type)
        if types.contains(.accel) || types.contains(.maxVelocity) { return "Speed" }
        if types.contains(where: { $0 == .speedEndurance || $0 == .specialEndurance1 || $0 == .specialEndurance2 }) {
            return "Endurance"
        }
        if types.contains(.extensiveTempo) { return "Tempo" }
        if types.contains(.generalStrength) { return "Strength" }
        return "Training"
    }

    private func typeColor(_ day: PlanDay, trimmed: Bool) -> Color {
        switch typeLabel(day, trimmed: trimmed) {
        case "Speed": return Theme.brand
        case "Endurance": return Theme.push
        case "Tempo": return Theme.hold
        case "Recovery": return Theme.textSecondary
        default: return Theme.textSecondary
        }
    }

    /// "~1,240m" — planned track-work meters for the day.
    private func volumeSummary(_ day: PlanDay) -> String? {
        let meters = day.trackworkBlocks.reduce(0) { sum, block in
            sum + (block.reps ?? 0) * (block.distanceM ?? 0)
        }
        guard meters > 0 else { return nil }
        return "~\(meters.formatted())m"
    }

    private var noPlan: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.largeTitle)
                .foregroundStyle(Theme.textSecondary)
            Text("No structured plan for \(profile?.event.rawValue ?? "this event") yet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Sessions rotate by day instead. 100m, 200m and 400m get the full 12-week plan.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
