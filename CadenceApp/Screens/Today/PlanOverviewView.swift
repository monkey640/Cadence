import SwiftUI
import CadenceCore

/// A light secondary view (from Today's plan header) for browsing the whole plan:
/// the 12-week phase arc, a week picker to open ANY week, and any day's full
/// session with the same expandable detail used on Today. Read-only.
struct PlanOverviewView: View {
    let template: PlanTemplate
    let currentWeek: Int
    let dayInWeek: Int
    var trainingDays: Int = 7
    var maxHighDays: Int = .max
    var proposal: AdjustmentProposal? = nil
    var onApply: () -> Void = {}
    var onDismiss: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWeek: Int

    init(template: PlanTemplate, currentWeek: Int, dayInWeek: Int, trainingDays: Int = 7, maxHighDays: Int = .max,
         proposal: AdjustmentProposal? = nil, onApply: @escaping () -> Void = {}, onDismiss: @escaping () -> Void = {}) {
        self.template = template
        self.currentWeek = currentWeek
        self.dayInWeek = dayInWeek
        self.trainingDays = trainingDays
        self.maxHighDays = maxHighDays
        self.proposal = proposal
        self.onApply = onApply
        self.onDismiss = onDismiss
        _selectedWeek = State(initialValue: min(max(currentWeek, 1), template.durationWeeks))
    }

    private var selectedPhase: PlanPhase? { PlanScheduler.phase(in: template, week: selectedWeek) }
    private var viewingCurrentWeek: Bool { selectedWeek == currentWeek }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if PersonalizationGate.isEnabled, let proposal {
                        PersonalizationCard(proposal: proposal, isDraft: PersonalizationGate.isDraft,
                                            onApply: onApply, onDismiss: onDismiss)
                    }
                    phaseArc
                    weekPicker
                    weekOverview
                    Text("Daily volume is still scaled by your readiness each morning — this is the planned structure, not a fixed promise.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .navigationTitle(template.event + " · 12-week plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .cadenceBackground()
        }
        .preferredColorScheme(Theme.scheme)
    }

    // MARK: - Phase arc (tap a phase to jump to its first week)

    private var phaseArc: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("THE 12-WEEK ARC").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ProgressView(value: Double(min(currentWeek, template.durationWeeks)),
                         total: Double(template.durationWeeks))
                .tint(Theme.accent)
            VStack(spacing: 0) {
                ForEach(Array(template.phases.enumerated()), id: \.offset) { index, phase in
                    Button {
                        if let range = PlanScheduler.weekRange(phase.weeks) {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedWeek = range.lowerBound }
                        }
                    } label: { phaseRow(phase) }
                    .buttonStyle(.plain)
                    if index != template.phases.count - 1 { Divider().overlay(Theme.hairline) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func phaseRow(_ phase: PlanPhase) -> some View {
        let range = PlanScheduler.weekRange(phase.weeks)
        let isCurrent = range?.contains(currentWeek) ?? false
        let isPast = (range.map { $0.upperBound < currentWeek }) ?? false
        let isSelected = range?.contains(selectedWeek) ?? false
        return HStack(spacing: 12) {
            Image(systemName: isPast ? "checkmark.circle.fill" : (isCurrent ? "circle.inset.filled" : "circle"))
                .foregroundStyle(isCurrent ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(phase.name)
                    .font(.subheadline.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text("Weeks \(phase.weeks)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent { Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent) }
            else if isSelected { Image(systemName: "eye").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(isSelected ? Theme.accent.opacity(0.10) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Week picker (open any week)

    private var weekPicker: some View {
        Stepper(value: $selectedWeek, in: 1...template.durationWeeks) {
            HStack {
                Text("Week \(selectedWeek) of \(template.durationWeeks)").font(.headline)
                if viewingCurrentWeek {
                    Text("THIS WEEK").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Selected week's workouts

    @ViewBuilder private var weekOverview: some View {
        if let phase = selectedPhase {
            VStack(alignment: .leading, spacing: 10) {
                Text(phase.name.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                // The session "why" — phase intent.
                Text(phase.rationale)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                let kept = PlanFitter.keptTrainingDays(in: phase.weeklyMicrocycle, trainingDays: trainingDays, maxHighDays: maxHighDays)
                ForEach(phase.weeklyMicrocycle.sorted { $0.day < $1.day }, id: \.day) { day in
                    let isToday = viewingCurrentWeek && day.day == dayInWeek
                    let trimmed = PlanFitter.isTrimmedToRest(day, kept: kept)
                    NavigationLink {
                        PlanDayDetailView(day: day, isToday: isToday, intent: phase.rationale,
                                          fitNote: trimmed ? "Trimmed to fit your \(trainingDays) training days a week — keep it easy or take it off." : nil)
                    } label: {
                        dayRow(day, isToday: isToday, trimmed: trimmed)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func dayRow(_ day: PlanDay, isToday: Bool, trimmed: Bool) -> some View {
        HStack(spacing: 12) {
            Text("Day \(day.day)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isToday ? Theme.accent : .secondary)
                .frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(trimmed ? "Recovery / rest" : day.name)
                    .font(.subheadline.weight(isToday ? .semibold : .regular))
                    .foregroundStyle(.primary)
                if trimmed {
                    Text(day.name).font(.caption2).foregroundStyle(.tertiary).strikethrough()
                }
            }
            Spacer(minLength: 8)
            LoadBadge(load: trimmed ? .rest : day.load)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(isToday ? Theme.accent.opacity(0.12) : .clear)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(isToday ? Theme.accent.opacity(0.5) : .clear, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A single day's full workout (any week). Same expandable block detail + glossary
/// used on Today — unscaled, since only today's volume is adapted by readiness.
struct PlanDayDetailView: View {
    let day: PlanDay
    let isToday: Bool
    var intent: String? = nil
    var fitNote: String? = nil   // non-nil when this day was trimmed to rest by the weekly-days fit

    private var blocks: [TodayViewModel.DisplayBlock] {
        day.blocks.enumerated().map { index, b in
            TodayViewModel.DisplayBlock(
                id: index, name: b.name, scaledReps: b.reps,
                intensity: b.type.flatMap { $0 == .other ? nil : $0.displayLabel },
                quality: b.type?.quality,
                movementID: GlossaryResolver.movementID(forType: b.type, name: b.name),
                sets: b.sets, reps: b.reps, distanceM: b.distanceM,
                rest: b.rest, target: b.target, note: b.detail)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    LoadBadge(load: fitNote != nil ? .rest : day.load)
                    if isToday { Text("TODAY").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent) }
                }
                if let intent {
                    Text(intent).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let fitNote {
                    // Trimmed to rest by the weekly-days fit — show why, not the workout.
                    Label(fitNote, systemImage: "calendar.badge.checkmark")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The planned session here was \(day.name) — trimmed because your week has fewer training days.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(blocks) { block in
                        SessionBlockRow(block: block)
                        if block.id != blocks.last?.id { Divider().overlay(Theme.hairline) }
                    }
                    if isToday {
                        Text("Today's volume is scaled to your readiness — see the Today tab for the adapted version.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
        .cadenceBackground()
    }
}

/// Shared high/low/rest pill.
struct LoadBadge: View {
    let load: LoadLevel
    private var color: Color {
        switch load {
        case .high: return Theme.push
        case .low: return Theme.hold
        case .rest: return .secondary
        }
    }
    var body: some View {
        Text(load.rawValue.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
