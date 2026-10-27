import Foundation
import Observation
import SwiftData
import CadenceCore

/// Drives the Today screen. The check-in is the gate: before it's done (and
/// before 2 PM) Today shows only the check-in CTA; after it's done, Today shows
/// the persisted score, the signals that shaped it, and the scaled session.
/// After 2 PM with no check-in, the plan shows un-scaled — a missed morning
/// never locks the athlete out of training.
@MainActor
@Observable
final class TodayViewModel {

    /// Check-ins are valid until this hour (2 PM). Before it, a missed check-in
    /// gates Today; after it, the plan shows un-scaled.
    static let checkInCutoffHour = 14

    /// Human label for the cutoff, derived from `checkInCutoffHour` (e.g. "2 PM"),
    /// so UI copy that mentions the deadline stays in sync with the constant.
    static var checkInCutoffLabel: String {
        var comps = DateComponents()
        comps.hour = checkInCutoffHour
        let date = Calendar.current.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    /// Context shown when an active plan day drives the session.
    struct PlanContext {
        let phaseName: String
        let phaseRationale: String
        let dayName: String
        let load: LoadLevel
        let weekNumber: Int
        let dayInWeek: Int
        let durationWeeks: Int
        let descriptiveBlocks: [PlanBlock]
        let isDraft: Bool
        let template: PlanTemplate
        let fittedToRest: Bool
        let weeklyTrainingDays: Int
        let maxHighDays: Int
    }

    /// One session block, flattened for display (and for building the player's sets).
    struct DisplayBlock: Identifiable, Sendable, Equatable {
        let id: Int
        let name: String
        let scaledReps: Int?
        let intensity: String?
        let quality: Quality?
        let movementID: String?
        let sets: Int?
        let reps: Int?
        let distanceM: Int?
        let rest: String?
        let target: String?
        let note: String?
        /// The pre-scaling rep count, for the "Scaled from 8 reps" line.
        /// Defaulted so existing call sites (plan previews) can omit it.
        var unscaledReps: Int? = nil

        var hasDetail: Bool {
            sets != nil || reps != nil || distanceM != nil || rest != nil
                || target != nil || intensity != nil || (note?.isEmpty == false)
        }
    }

    struct TomorrowPreview {
        let title: String
        let cue: String
    }

    struct Readout {
        /// Today's persisted readiness; nil on a no-check-in (late) day.
        let snapshot: DailyReadiness?
        /// The 2–4 most impactful signal rings (subjective fallback when phone-only).
        let rings: [SignalRing]
        let scaled: ScaledSession
        let displayBlocks: [DisplayBlock]
        let plan: PlanContext?
        let planComplete: Bool
        let proposal: AdjustmentProposal?
        let isPersonalized: Bool
        /// Today's upserted session row — the player starts/resumes from this.
        let session: TrainingSession?
        /// True when a Back Off verdict swapped the session for the recovery protocol.
        let isRecoveryDay: Bool
        /// Present once today's session is complete (the evening-recap state).
        let tomorrow: TomorrowPreview?
    }

    enum State {
        case loading
        /// Before the cutoff with no completed check-in: show only the CTA.
        case needsCheckIn
        case ready(Readout)
        case error(String)
    }

    private(set) var state: State = .loading

    /// Set when a recompute (late Apple Health data) changed today's *verdict*
    /// before a session started — Today shows a quiet "Updated with new Apple
    /// Health data" line. Cleared when the athlete acts on it or the day rolls.
    private(set) var showUpdatedNotice = false

    /// The training phase carrying into the coming week — surfaced in the weekly
    /// report's "next week" line. Set during load from the resolved plan.
    private(set) var nextWeekFocus: String?

    /// A recompute is considered worthwhile only if the snapshot is older than
    /// this; a fresh foreground within the window is a no-op (avoids churn).
    static let recomputeStaleness: TimeInterval = 15 * 60

    private let health: HealthDataProviding
    init(health: HealthDataProviding = HealthKitService()) { self.health = health }

    func dismissUpdatedNotice() { showUpdatedNotice = false }

    // MARK: - Load

    /// `forceRecompute` re-queries HealthKit and rebuilds today's readiness in
    /// place (late-data recompute), instead of reusing the persisted snapshot.
    func load(profile: AthleteProfile, context: ModelContext, now: Date = .now,
              forceRecompute: Bool = false) async {
        if !forceRecompute { state = .loading }
        let event = profile.event
        let planStart = profile.planStartDate
        let trainingDays = profile.weeklyTrainingDays
        let maxHighDays = profile.experienceLevel.maxHighDays

        let checkInDone = todayCheckIn(context: context, now: now)?.completedAt != nil
        if !checkInDone, Calendar.current.component(.hour, from: now) < Self.checkInCutoffHour {
            WidgetBridge.publishAwaitingCheckIn(on: now)
            state = .needsCheckIn
            return
        }

        do {
            // Check-in done → today's readiness. Normally the persisted snapshot;
            // on forceRecompute it's re-queried from HealthKit and rebuilt in place
            // (late-data path). No check-in → nil, plan runs un-scaled.
            let snapshot: DailyReadiness? = checkInDone
                ? try await ensureReadiness(context: context, now: now, forceRecompute: forceRecompute)
                : nil
            if let snapshot {
                WidgetBridge.publish(score: snapshot.score, verdict: snapshot.effectiveVerdict,
                                     multiplier: snapshot.effectiveMultiplier, on: now)
            }

            let personalization = PersonalizationCoordinator(context: context)
            let deltas = personalization.activeDeltas(event: event)
            let resolved = resolvePlannedSession(
                event: event, planStart: planStart, now: now,
                deltas: deltas, trainingDays: trainingDays, maxHighDays: maxHighDays)
            // Forward focus for the weekly report (the training phase carrying into
            // the coming week — the plan's current phase name).
            nextWeekFocus = resolved.plan?.phaseName

            // Use the *effective* (session-start-frozen) verdict/multiplier so a
            // late-data recompute can move the score without rescaling work already
            // underway. Before any session starts, effective == latest.
            let isRecoveryDay = snapshot?.effectiveVerdict == .backOff
            let scaled: ScaledSession
            let blocks: [DisplayBlock]
            if isRecoveryDay {
                (scaled, blocks) = recoverySession()
            } else {
                scaled = SessionScaler.scale(resolved.session, by: snapshot?.effectiveMultiplier ?? 1.0)
                blocks = displayBlocks(source: resolved.sourceBlocks, scaled: scaled)
            }

            let session = upsertTrainingSession(
                scaled: scaled, blocks: blocks,
                verdict: snapshot?.effectiveVerdict ?? .hold,
                score: snapshot?.score ?? 0,
                multiplier: snapshot?.effectiveMultiplier ?? 1.0,
                hadCheckIn: checkInDone, isRecovery: isRecoveryDay,
                on: now, context: context)

            // The instant a session begins, freeze what the athlete trained under
            // so future recomputes never retroactively rescale it.
            if let snapshot, let session, session.startedAt != nil || session.isComplete,
               snapshot.freezeForSessionStart(verdict: session.verdict, multiplier: session.volumeMultiplier) {
                try? context.save()
            }

            let proposal = pendingProposal(
                plan: resolved.plan, coordinator: personalization, event: event, context: context)

            let tomorrow = (session?.isComplete == true)
                ? tomorrowPreview(event: event, planStart: planStart, now: now,
                                  deltas: deltas, trainingDays: trainingDays, maxHighDays: maxHighDays)
                : nil

            state = .ready(Readout(
                snapshot: snapshot,
                rings: buildRings(snapshot: snapshot, checkIn: todayCheckIn(context: context, now: now)),
                scaled: scaled, displayBlocks: blocks,
                plan: resolved.plan, planComplete: resolved.planComplete,
                proposal: proposal, isPersonalized: !deltas.isEmpty,
                session: session, isRecoveryDay: isRecoveryDay, tomorrow: tomorrow))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Readiness

    private func todayCheckIn(context: ModelContext, now: Date) -> CheckIn? {
        let today = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<CheckIn>(predicate: #Predicate { $0.day == today })
        return try? context.fetch(descriptor).first
    }

    /// Today's `DailyReadiness`. Returns the persisted snapshot as-is, unless it's
    /// missing (repair path) or `forceRecompute` is set — then it re-queries
    /// HealthKit, reuses the already-stored check-in inputs silently (never
    /// re-prompts), and rebuilds today's row in place. A verdict change from a
    /// recompute (before any session started) raises the "updated" notice.
    private func ensureReadiness(context: ModelContext, now: Date,
                                 forceRecompute: Bool) async throws -> DailyReadiness? {
        let today = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.date == today })
        let existing = try? context.fetch(descriptor).first
        if let existing, !forceRecompute { return existing }

        let priorVerdict = existing?.verdict
        let wasFrozen = existing?.verdictAtSessionStart != nil
        let coordinator = ReadinessCoordinator(health: health)
        let result = try await coordinator.computeToday(
            asOf: now, phone: .from(context: context, now: now))
        let row = try coordinator.persist(result, on: now, into: context)
        if forceRecompute, !wasFrozen, let priorVerdict, priorVerdict != row.verdict {
            showUpdatedNotice = true
        }
        return row
    }

    // MARK: - Signal rings

    /// The 2–4 signals that most shaped today's score: ranked by distance from
    /// the neutral anchor (72), so a wrecked sleep and a strong HRV both surface.
    /// Phone-only mornings fall back to the check-in's subjective answers.
    private func buildRings(snapshot: DailyReadiness?, checkIn: CheckIn?) -> [SignalRing] {
        guard let snapshot else { return [] }

        var candidates: [(id: String, label: String, score: Double?)] = [
            ("hrv", "HRV", snapshot.hrvScore),
            ("sleep", "Sleep", snapshot.sleepScore),
            ("sleepQuality", "Sleep quality", snapshot.sleepQualityScore),
            ("rhr", "Resting HR", snapshot.rhrScore),
            ("respiratory", "Breathing", snapshot.respiratoryScore),
            ("wristTemp", "Wrist temp", snapshot.wristTempScore),
            ("load", "Load", snapshot.loadScore),
            ("wellness", "Check-in", snapshot.wellnessScore),
            ("tap", "Tap test", snapshot.fingerTapScore),
            ("jump", "Jump", snapshot.jumpScore),
        ]

        // Phone-only (no wearable subscores at all): the check-in's own answers
        // are the story — show them individually instead of one composite ring.
        let hasWearable = snapshot.hrvScore != nil || snapshot.sleepScore != nil
            || snapshot.rhrScore != nil
        if !hasWearable, let checkIn {
            candidates = [
                ("subjSleep", "Sleep", checkIn.wellnessSleep.map(subjectiveScore)),
                ("subjSoreness", "Soreness", checkIn.wellnessSoreness.map(subjectiveScore)),
                ("subjFatigue", "Fatigue", checkIn.wellnessFatigue.map(subjectiveScore)),
                ("subjStress", "Stress", checkIn.wellnessStress.map(subjectiveScore)),
                ("subjMood", "Mood", checkIn.wellnessMood.map(subjectiveScore)),
                ("tap", "Tap test", snapshot.fingerTapScore),
                ("jump", "Jump", snapshot.jumpScore),
            ]
        }

        return candidates
            .compactMap { candidate -> SignalRing? in
                guard let score = candidate.score else { return nil }
                return SignalRing(id: candidate.id, label: candidate.label, score: score)
            }
            .sorted { abs($0.score - 72) > abs($1.score - 72) }
            .prefix(4)
            .map { $0 }
    }

    /// 1–5 slider answer → 0–100 ring scale.
    private func subjectiveScore(_ value: Int) -> Double { Double(value - 1) / 4 * 100 }

    // MARK: - Recovery day

    private func recoverySession() -> (ScaledSession, [DisplayBlock]) {
        let blocks = RecoveryProtocol.items.enumerated().map { index, item in
            DisplayBlock(
                id: index, name: item.name, scaledReps: 1,
                intensity: nil, quality: nil, movementID: nil,
                sets: nil, reps: nil, distanceM: nil, rest: nil, target: nil,
                note: item.detail, unscaledReps: nil)
        }
        let scaled = ScaledSession(
            title: RecoveryProtocol.sessionTitle,
            blocks: RecoveryProtocol.items.map { TrainingBlock(name: $0.name, sets: 1) },
            multiplier: 1.0, wasAdjusted: false)
        return (scaled, blocks)
    }

    // MARK: - Tomorrow preview (evening-recap state)

    private func tomorrowPreview(
        event: Event, planStart: Date?, now: Date,
        deltas: [Quality: Int], trainingDays: Int, maxHighDays: Int
    ) -> TomorrowPreview? {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return nil }
        let resolved = resolvePlannedSession(
            event: event, planStart: planStart, now: tomorrow,
            deltas: deltas, trainingDays: trainingDays, maxHighDays: maxHighDays)
        let title: String
        if let plan = resolved.plan {
            title = "Week \(plan.weekNumber) · \(plan.dayName)"
        } else {
            title = resolved.session.title
        }
        let cue: String
        switch resolved.plan?.load {
        case .high: cue = "Target 8+ hrs tonight — big session tomorrow."
        case .rest: cue = "Rest day tomorrow. Sleep is still training."
        default: cue = "Recover well tonight — steady work tomorrow."
        }
        return TomorrowPreview(title: title, cue: cue)
    }

    // MARK: - Plan resolution

    private func resolvePlannedSession(
        event: Event, planStart: Date?, now: Date, deltas: [Quality: Int], trainingDays: Int, maxHighDays: Int
    ) -> (session: PlannedSession, plan: PlanContext?, planComplete: Bool, sourceBlocks: [PlanBlock]?) {

        // A plan applies only when the event is covered AND we have a start date.
        guard let template = PlanLibraryLoader.template(for: event), let planStart else {
            return (SessionTemplates.todaysSession(for: event, on: now), nil, false, nil)
        }

        let cal = Calendar.current
        let elapsedDays = max(0, cal.dateComponents([.day],
            from: cal.startOfDay(for: planStart), to: cal.startOfDay(for: now)).day ?? 0)
        let week = elapsedDays / 7 + 1
        let dayInWeek = elapsedDays % 7 + 1

        guard week <= template.durationWeeks,
              let selection = PlanScheduler.selectDay(in: template, week: week, dayInWeek: dayInWeek) else {
            // Plan finished → fallback rotation, flagged as complete.
            return (SessionTemplates.todaysSession(for: event, on: now), nil, true, nil)
        }

        // Fit to the athlete's declared training days (reduce-only): a trimmed
        // training day becomes a recovery/rest day.
        let kept = PlanFitter.keptTrainingDays(in: selection.phase.weeklyMicrocycle, trainingDays: trainingDays, maxHighDays: maxHighDays)
        let fittedToRest = PlanFitter.isTrimmedToRest(selection.day, kept: kept)

        let plan = PlanContext(
            phaseName: selection.phase.name,
            phaseRationale: selection.phase.rationale,
            dayName: fittedToRest ? "Recovery / rest" : selection.day.name,
            load: fittedToRest ? .rest : selection.day.load,
            weekNumber: week,
            dayInWeek: dayInWeek,
            durationWeeks: template.durationWeeks,
            descriptiveBlocks: fittedToRest ? [] : selection.day.descriptiveBlocks,
            isDraft: PlanLibraryLoader.shared?.meta.isDraft ?? false,
            template: template,
            fittedToRest: fittedToRest,
            weeklyTrainingDays: trainingDays,
            maxHighDays: maxHighDays)

        if fittedToRest {
            return (PlannedSession(title: "Recovery / rest", blocks: []), plan, false, nil)
        }

        // Reflect any applied per-quality trade onto today's blocks (designated-day
        // rule), then return — readiness scaling is applied by the caller on top.
        let session = personalizedSession(day: selection.day, phase: selection.phase,
                                          dayInWeek: dayInWeek, deltas: deltas)
        return (session, plan, false, selection.day.blocks)
    }

    /// Build today's track-work session, reflecting applied personalization deltas.
    /// With empty deltas this is identical to `PlanDay.scalableSession()`.
    private func personalizedSession(day: PlanDay, phase: PlanPhase, dayInWeek: Int,
                                     deltas: [Quality: Int]) -> PlannedSession {
        let blocks = day.trackworkBlocks.map { block -> TrainingBlock in
            let reps = PlanPersonalizer.adjustedReps(for: block, dayInWeek: dayInWeek,
                                                     phase: phase, deltas: deltas) ?? (block.reps ?? 1)
            return TrainingBlock(name: block.scaledDisplayName, sets: reps,
                                 distanceMeters: block.distanceM.map { Double($0) }, durationSeconds: nil)
        }
        return PlannedSession(title: day.name, blocks: blocks)
    }

    /// Compute a pending personalization proposal for the current plan day (nil
    /// unless the feature is on, the event is covered, and evidence supports it).
    private func pendingProposal(plan: PlanContext?, coordinator: PersonalizationCoordinator,
                                 event: Event, context: ModelContext) -> AdjustmentProposal? {
        guard let plan,
              let phase = PlanScheduler.phase(in: plan.template, week: plan.weekNumber) else { return nil }
        return coordinator.currentProposal(
            event: event, currentPhase: phase,
            recentSessions: recentCompletedSessions(context: context),
            readinessTrend: readinessTrend(context: context),
            lowReadinessDays: lowReadinessDays(context: context))
    }

    private func recentCompletedSessions(context: ModelContext) -> [TrainingSession] {
        // Plan sessions only — off-plan custom workouts don't drive plan-deficiency detection.
        let descriptor = FetchDescriptor<TrainingSession>(
            predicate: #Predicate { $0.isComplete && !$0.isCustom },
            sortBy: [SortDescriptor(\.date, order: .forward)])
        return Array(((try? context.fetch(descriptor)) ?? []).suffix(8))
    }

    private func readinessTrend(context: ModelContext) -> ReadinessTrend {
        let descriptor = FetchDescriptor<DailyReadiness>(sortBy: [SortDescriptor(\.date, order: .forward)])
        guard let all = try? context.fetch(descriptor), all.count >= 4 else { return .flat }
        let scores = all.suffix(10).map(\.score)
        let half = scores.count / 2
        let first = scores.prefix(half).reduce(0, +) / Double(half)
        let second = scores.suffix(half).reduce(0, +) / Double(half)
        let diff = second - first
        if abs(diff) < 3 { return .flat }
        return diff > 0 ? .up : .down
    }

    private func lowReadinessDays(context: ModelContext) -> Set<Date> {
        let backOff = Verdict.backOff.rawValue
        let descriptor = FetchDescriptor<DailyReadiness>(predicate: #Predicate { $0.verdictRaw == backOff })
        let rows = (try? context.fetch(descriptor)) ?? []
        return Set(rows.map { Calendar.current.startOfDay(for: $0.date) })
    }

    /// Flatten blocks for display, pairing each plan block with its scaled rep
    /// count (track-work) and carrying every detail field the plan stores.
    /// `source` is the full ordered plan blocks (plan path) or nil (fallback rotation).
    private func displayBlocks(source: [PlanBlock]?, scaled: ScaledSession) -> [DisplayBlock] {
        guard let source else {
            // Fallback rotation: only headline + distance exist; the rest is omitted.
            return scaled.blocks.enumerated().map { index, block in
                DisplayBlock(id: index, name: block.name, scaledReps: block.sets,
                             intensity: nil, quality: nil,
                             movementID: GlossaryResolver.movementID(forType: nil, name: block.name),
                             sets: nil, reps: nil,
                             distanceM: block.distanceMeters.map { Int($0) },
                             rest: nil, target: nil, note: nil, unscaledReps: nil)
            }
        }
        var result: [DisplayBlock] = []
        var trackIndex = 0   // scaled.blocks are the track-work blocks in source order
        for (index, block) in source.enumerated() {
            let isTrackwork = block.reps != nil
            var scaledReps: Int? = nil
            if isTrackwork {
                scaledReps = trackIndex < scaled.blocks.count ? scaled.blocks[trackIndex].sets : block.reps
                trackIndex += 1
            }
            result.append(DisplayBlock(
                id: index,
                name: block.name,
                scaledReps: scaledReps,
                intensity: block.type.flatMap { $0 == .other ? nil : $0.displayLabel },
                quality: block.type?.quality,
                movementID: GlossaryResolver.movementID(forType: block.type, name: block.name),
                sets: block.sets,
                reps: block.reps,
                distanceM: block.distanceM,
                rest: block.rest,
                target: block.target,
                note: block.detail,
                unscaledReps: isTrackwork ? block.reps : nil))
        }
        return result
    }

    /// Create today's `TrainingSession` from the scaled plan if one doesn't
    /// already exist. Never overwrites a session the athlete has logged into.
    @discardableResult
    private func upsertTrainingSession(
        scaled: ScaledSession, blocks: [DisplayBlock], verdict: Verdict,
        score: Double, multiplier: Double, hadCheckIn: Bool, isRecovery: Bool,
        on date: Date, context: ModelContext
    ) -> TrainingSession? {
        let day = Calendar.current.startOfDay(for: date)
        // Only the plan-derived session for the day — never the athlete's custom workouts.
        let descriptor = FetchDescriptor<TrainingSession>(predicate: #Predicate { $0.date == day && !$0.isCustom })
        if let existing = try? context.fetch(descriptor).first {
            let hasProgress = existing.isComplete || existing.startedAt != nil
                || existing.sets.contains { $0.completedSets > 0 }
            if hasProgress { return existing }
            context.delete(existing)
        }

        let session = TrainingSession(
            date: day,
            title: scaled.title,
            verdict: verdict,
            readinessScore: score,
            volumeMultiplier: multiplier,
            wasAdjusted: scaled.wasAdjusted)
        session.hadCheckIn = hadCheckIn
        session.isRecovery = isRecovery
        // Log the blocks with a rep count (track-work / recovery items), carrying
        // quality for fade routing and parsed rest for the player's timer.
        session.sets = blocks.filter { $0.scaledReps != nil }.enumerated().map { index, block in
            SessionSet(
                name: block.name,
                order: index,
                plannedSets: block.scaledReps ?? 0,
                distanceMeters: block.distanceM.map { Double($0) },
                targetSeconds: nil,
                qualityRaw: block.quality?.rawValue,
                movementID: block.movementID,
                restSeconds: RestParser.seconds(from: block.rest))
        }
        context.insert(session)
        try? context.save()
        return session
    }
}
