import SwiftUI
import SwiftData
import CadenceCore

/// The hero screen. One glance answers "how hard do I go today?" — and it works
/// twice a day: the morning ritual (check-in → score → session) and the evening
/// recap (what you did, what's tomorrow).
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [AthleteProfile]
    @Query private var personalRecords: [PersonalRecord]
    @Query(sort: \TrainingSession.date, order: .reverse) private var allSessions: [TrainingSession]
    @Query(sort: \DailyReadiness.date, order: .reverse) private var allReadiness: [DailyReadiness]
    @State private var model = TodayViewModel()
    @State private var streak = StreakService.Streak(days: 0, isProtected: false)
    @State private var showCheckIn = false
    @State private var showPlayer = false
    /// Reopens a finished session's summary — so a PR card can still be shared
    /// after the summary was dismissed.
    @State private var showSummary = false
    @State private var summaryCelebrates = false
    @State private var breakdownFocus: String?
    @State private var showBreakdown = false
    @State private var showPlanOverview = false

    // Dopamine motion — the score reveal and the (rare) PR burst.
    @State private var revealScore: Double = 0
    @State private var revealVerdict = false
    @State private var celebratePR = false
    @State private var prPop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var profile: AthleteProfile? { profiles.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                switch model.state {
                case .loading:
                    loading
                case .needsCheckIn:
                    checkInCTA
                case .error(let message):
                    errorView(message)
                case .ready(let readout):
                    readyView(readout)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cadenceBackground()
        .overlay {
            if celebratePR {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .task {
            await reload()
            #if DEBUG
            // Sim-only: CADENCE_DEMO_PLAYER=1|rest auto-opens the session player.
            if ProcessInfo.processInfo.environment["CADENCE_DEMO_PLAYER"] != nil,
               case .ready = model.state { showPlayer = true }
            // Sim-only: CADENCE_DEMO_SUMMARY=1 (with _RECAP=1) opens the finished
            // session's summary *with* its celebration, for filming the PR moment.
            if ProcessInfo.processInfo.environment["CADENCE_DEMO_SUMMARY"] == "1" {
                summaryCelebrates = true
                showSummary = true
            }
            #endif
        }
        // Pull-to-refresh is a *true* recompute (re-query HealthKit + rebuild),
        // not just a re-render — so late-synced wearable data flows in.
        .refreshable { await recompute() }
        // Coming back to the foreground, silently recompute if the snapshot has
        // gone stale (data may have synced while we were away).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await recomputeIfStale() } }
        }
        .fullScreenCover(isPresented: $showCheckIn) {
            CheckInFlowView(onComplete: { Task { await reload() } })
        }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: { Task { await reload() } }) {
            if case .ready(let readout) = model.state, let session = readout.session {
                SessionPlayerView(
                    session: session,
                    displayBlocks: readout.displayBlocks,
                    firstName: profile?.firstName ?? "")
            }
        }
        .sheet(isPresented: $showBreakdown) {
            if case .ready(let readout) = model.state, let snapshot = readout.snapshot {
                SignalBreakdownSheet(snapshot: snapshot, focusSignalID: breakdownFocus)
            }
        }
    }

    private func reload() async {
        guard let profile else { return }
        // The streak is derived purely from completed check-ins (the check-in
        // flow persists completedAt before any HealthKit work), so opening Today
        // records nothing — it just reads the current run.
        streak = StreakService.currentStreak(context: context)
        await model.load(profile: profile, context: context)
        // Keep the optional contextual nudges current with today's state.
        await MorningNotificationService.shared.refreshContextual(context: context)
    }

    /// Re-query HealthKit and rebuild today's readiness in place (no loading flash,
    /// no re-reveal) — the living-value path for late-synced wearable data.
    private func recompute() async {
        guard let profile else { return }
        streak = StreakService.currentStreak(context: context)
        await model.load(profile: profile, context: context, forceRecompute: true)
    }

    /// Recompute on foreground only if today's snapshot has gone stale.
    private func recomputeIfStale() async {
        guard case .ready(let readout) = model.state, let snapshot = readout.snapshot else { return }
        let age = Date.now.timeIntervalSince(snapshot.updatedAt ?? .distantPast)
        if age > TodayViewModel.recomputeStaleness { await recompute() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                    if let name = profile?.firstName, !name.isEmpty {
                        Text(name)
                            .font(.displayBlack(28))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                Spacer()
                if streak.days > 0 { streakBadge }
                checkInButton
            }
            if streak.isProtected {
                Label("Streak protected — freeze used.", systemImage: "snowflake")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Always-available entry into the morning ritual — so you can (re)run the
    /// full check-in (wellness → tap test → jump test → score) any time, not
    /// just before 2 PM on a fresh day.
    private var checkInButton: some View {
        Button { showCheckIn = true } label: {
            Image(systemName: "checklist")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 36, height: 36)
                .background(Theme.card)
                .clipShape(Circle())
        }
        .accessibilityLabel("Open morning check-in")
    }

    private var streakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").foregroundStyle(Theme.brand)
            Text("\(streak.days)-day streak")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.card)
        .clipShape(Capsule())
        .accessibilityLabel("\(streak.days) day check-in streak")
    }

    // MARK: - Gate states

    private var checkInCTA: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.brand)
            Text("Complete your morning check-in to unlock today's plan.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Five questions, a tap test, and your verdict — about a minute.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text("Check in before \(TodayViewModel.checkInCutoffLabel) and today's session scales to your recovery. After that it stays at full plan volume.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Check in now") { showCheckIn = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .cadenceCard(padding: 20)
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView().tint(Theme.brand)
            Text("Reading your morning…").foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't read your data").font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await reload() } }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
    }

    // MARK: - Ready

    @ViewBuilder
    private func readyView(_ r: TodayViewModel.Readout) -> some View {
        if let plan = r.plan {
            planHeader(plan, proposal: r.proposal)
        }
        if r.planComplete { planCompleteBanner }

        if let days = taperDays {
            taperStrip(days)
        } else if let days = daysToMeet {
            meetRibbon(days)
        }

        if let report = weeklyReport { weeklyReportRegister(report) }

        // The hero, as flat registers ruled by lane lines — no card stack.
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot = r.snapshot {
                readinessRegister(snapshot)
                if !r.rings.isEmpty {
                    LaneLine().padding(.vertical, 18)
                    lanesRegister(r.rings, animated: !revealStatic(snapshot))
                }
            } else {
                lateRegister
            }

            LaneLine().padding(.vertical, 18)

            if let session = r.session, session.isComplete {
                recapRegister(session)
            } else if r.isRecoveryDay {
                recoveryRegister(r)
            } else if r.displayBlocks.isEmpty {
                restRegister(r)
            } else {
                sessionRegister(r)
            }
        }

        if let session = r.session, session.isComplete, let tomorrow = r.tomorrow {
            tomorrowCard(tomorrow)
        }

        if r.isPersonalized { personalizedBanner }
        if PersonalizationGate.isEnabled, let proposal = r.proposal {
            PersonalizationCard(
                proposal: proposal, isDraft: PersonalizationGate.isDraft,
                onApply: { applyProposal(proposal) },
                onDismiss: { dismissProposal(proposal) })
        }
        if let plan = r.plan, plan.isDraft { draftNotice }
        disclaimerFooter
    }

    // MARK: - Meet countdown

    /// Whole days until the next meet, or nil if none set / already past.
    private var daysToMeet: Int? {
        guard let meet = profile?.meetDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now),
                                      to: cal.startOfDay(for: meet)).day ?? -1
        return days >= 0 ? days : nil
    }

    /// A stadium ribbon — the clock the athlete is actually racing.
    private func meetRibbon(_ days: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Rectangle().fill(Theme.brand).frame(width: 12, height: 2)
                Text("Next meet").sectionLabel()
                Spacer()
                HStack(spacing: 5) {
                    Text("\(days)")
                        .font(.timingBoard(15, weight: .bold))
                        .foregroundStyle(Theme.brand)
                    Text(days == 1 ? "day out" : "days out").sectionLabel()
                }
            }
            pbGoalRow
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - PB → goal (wired goal time)

    /// The athlete's personal best for their main event (the PR key is the event's
    /// raw value, e.g. "100m").
    private var eventPB: Double? {
        guard let event = profile?.event else { return nil }
        return personalRecords.first { $0.key == event.rawValue }?.bestTimeSeconds
    }
    private var goalTime: Double? {
        guard let g = profile?.goalTimeSeconds, g > 0 else { return nil }
        return g
    }

    /// "PB 11.62 → goal 11.20" — trajectory only, no prediction or promise.
    @ViewBuilder private var pbGoalRow: some View {
        if let goal = goalTime {
            HStack(spacing: 6) {
                if let pb = eventPB {
                    Text("PB \(raceTime(pb))")
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("goal \(raceTime(goal))")
                    .foregroundStyle(Theme.brand)
            }
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(eventPB.map { "Personal best \(raceTime($0)), goal \(raceTime(goal))" }
                                ?? "Goal \(raceTime(goal))")
        }
    }

    /// Race-clock format: 11.62 under a minute, 1:02.4 above.
    private func raceTime(_ s: Double) -> String {
        if s < 60 { return String(format: "%.2f", s) }
        let m = Int(s) / 60
        return String(format: "%d:%04.1f", m, s - Double(m * 60))
    }

    // MARK: - Weekly report (Sunday evening)

    struct WeeklyReport {
        let trainedDays: Int
        let reps: Int
        let readinessAvg: Double?
        let prCount: Int
        let nextFocus: String?
        let weekLabel: String
    }

    /// Shown Sunday evening (or via the demo hook): a reflective week-in-review.
    private var weeklyReport: WeeklyReport? {
        let cal = Calendar.current
        let now = Date.now
        let isSundayEvening = cal.component(.weekday, from: now) == 1 && cal.component(.hour, from: now) >= 17
        var show = isSundayEvening
        #if DEBUG
        if ProcessInfo.processInfo.environment["CADENCE_DEMO_WEEKLY"] == "1" { show = true }
        #endif
        guard show, let week = cal.dateInterval(of: .weekOfYear, for: now) else { return nil }

        let trained = allSessions.filter { $0.isComplete && $0.date >= week.start }
        let reps = trained.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.completedSets } }
        let scores = allReadiness.filter { $0.date >= week.start }.map(\.score)
        let avg = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let prs = trained.flatMap(\.sets).filter(\.wasPR).count
        let endDate = cal.date(byAdding: .day, value: -1, to: week.end) ?? week.end
        let label = "\(week.start.formatted(.dateTime.month(.abbreviated).day()))–\(endDate.formatted(.dateTime.day()))"
        return WeeklyReport(trainedDays: trained.count, reps: reps, readinessAvg: avg,
                            prCount: prs, nextFocus: model.nextWeekFocus, weekLabel: label)
    }

    private func weeklyReportRegister(_ r: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week in review").sectionLabel()

            HStack(spacing: 26) {
                stat(value: "\(r.trainedDays)", label: "sessions")
                stat(value: "\(r.reps)", label: "reps")
                if let avg = r.readinessAvg {
                    stat(value: "\(Int(avg.rounded()))", label: "avg ready")
                }
                if r.prCount > 0 {
                    stat(value: "\(r.prCount)", label: r.prCount == 1 ? "PR" : "PRs")
                }
            }

            Text(weeklyNarrative(r))
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let focus = r.nextFocus {
                Label("Next week · \(focus)", systemImage: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let image = WeeklyRecapRenderer.image(
                firstName: profile?.firstName ?? "", weekLabel: r.weekLabel,
                trainedDays: r.trainedDays, reps: r.reps,
                readinessAvg: r.readinessAvg.map { Int($0.rounded()) }, prCount: r.prCount) {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("My week on Cadence", image: Image(uiImage: image))) {
                    Label("Share recap", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                        .padding(.top, 2)
                }
            }
        }
        .cadenceCard(padding: 20)
    }

    /// The coach's one-liner — same calm, specific voice as Trends' THIS WEEK card.
    private func weeklyNarrative(_ r: WeeklyReport) -> String {
        if r.trainedDays == 0 {
            return "A quiet week on the log. A fresh block starts tomorrow — first session resets the rhythm."
        }
        let prBit = r.prCount > 0 ? " with a new PR" : ""
        let readyBit: String
        switch r.readinessAvg {
        case let a? where a >= 80: readyBit = "Recovery held strong all week."
        case let a? where a >= 65: readyBit = "Recovery stayed steady."
        case .some: readyBit = "Recovery ran a little low — worth protecting sleep."
        case nil: readyBit = "Keep the morning check-ins going for a readiness read."
        }
        return "\(r.trainedDays) session\(r.trainedDays == 1 ? "" : "s") logged\(prBit). \(readyBit) Nice work."
    }

    // MARK: - Taper mode (race week)

    /// Inside this window the meet ribbon becomes a taper strip and sessions carry
    /// taper intent — the athlete is sharpening for the meet they're racing.
    private static let taperWindow = 7

    /// Days to meet when inside the taper window (0 = race day); else nil.
    private var taperDays: Int? {
        guard let d = daysToMeet, d <= Self.taperWindow else { return nil }
        return d
    }

    /// A lane running to the finish line — today's pip lit, race day a checkered
    /// flag. Calm and confident: the work is banked, this week is for sharpening.
    private func taperStrip(_ days: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(days == 0 ? "Race day" : "Race week").sectionLabel()
                Spacer()
                Text(days == 0 ? "TODAY" : "\(days) \(days == 1 ? "DAY" : "DAYS") OUT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Theme.brand)
            }
            HStack(spacing: 6) {
                ForEach(0...max(days, 0), id: \.self) { i in
                    if i == days {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.brand)
                    } else {
                        Capsule()
                            .fill(i == 0 ? Theme.brand : Theme.laneLine)
                            .frame(width: i == 0 ? 18 : 11, height: 4)
                    }
                }
                Spacer()
            }
            Text(taperCue(days))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            pbGoalRow
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(days == 0 ? "Race day" : "Race in \(days) days, taper week")
    }

    private func taperCue(_ days: Int) -> String {
        switch days {
        case 0:  return "Everything's in. Warm up, trust the work, and race."
        case 1:  return "One day out. Keep it light and sharp — the fitness is already banked."
        default: return "Taper week — volume eases off, intensity holds. You're sharpening, not building."
        }
    }

    // MARK: - Readiness register (the colossal readout)

    /// Persisted day-ordinal of the last reveal, so the count-up plays once per
    /// day (the morning moment) and opening Today again shows the final value.
    private static let lastRevealKey = "today.reveal.lastDayOrdinal"

    /// True when the reveal should NOT animate: motion is reduced, or today's
    /// reveal already played. Read in-body (cheap) so the hero never flashes 0.
    private func revealStatic(_ snapshot: DailyReadiness) -> Bool {
        reduceMotion || dayOrdinal(snapshot) == UserDefaults.standard.integer(forKey: Self.lastRevealKey)
    }
    private func dayOrdinal(_ snapshot: DailyReadiness) -> Int {
        Calendar.current.ordinality(of: .day, in: .era, for: snapshot.date) ?? 0
    }
    private func markRevealed(_ snapshot: DailyReadiness) {
        UserDefaults.standard.set(dayOrdinal(snapshot), forKey: Self.lastRevealKey)
    }

    /// Today's clearance as a percentage of planned volume — what the athlete
    /// actually needs to know. Uses the session-start-frozen multiplier.
    private func volumePercent(_ snapshot: DailyReadiness) -> Double {
        (snapshot.effectiveMultiplier * 100).rounded()
    }
    private func volumeLabel(_ snapshot: DailyReadiness) -> String {
        "\(Int(volumePercent(snapshot)))"
    }

    private func readinessRegister(_ snapshot: DailyReadiness) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(taperDays == 0 ? "Race day" : "Today's volume").sectionLabel()
                Spacer()
                Text(snapshot.effectiveVerdict.badgeText)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(snapshot.effectiveVerdict.color)
                    .opacity(revealStatic(snapshot) || revealVerdict ? 1 : 0)
                    .scaleEffect(revealStatic(snapshot) || revealVerdict ? 1 : 0.7, anchor: .trailing)
                    .accessibilityLabel("Verdict \(snapshot.effectiveVerdict.displayName)")
            }

            // The hero answers the question the screen exists for — how much of
            // the plan do I do today? A push day reads a clean 100%. The readiness
            // score stays the measurement, shown as a chip below and in Trends.
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                CountingText(value: revealStatic(snapshot) ? volumePercent(snapshot) : revealScore)
                    .font(.timingBoard(96))
                    .foregroundStyle(snapshot.effectiveVerdict.color)
                    // A recompute (late Health data) moves the number quietly — no
                    // re-reveal, no haptic; the reveal one-shot already guards that.
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: volumePercent(snapshot))
                Text("%")
                    .font(.timingBoard(40))
                    .foregroundStyle(snapshot.effectiveVerdict.color)
                Text("of plan")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(volumeLabel(snapshot)) percent of planned volume today, \(snapshot.effectiveVerdict.displayName), readiness \(Int(snapshot.score.rounded())) out of 100")

            Text(snapshot.reason)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            HStack(spacing: 8) {
                Text("Readiness \(Int(snapshot.score.rounded()))")
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.surfaceSecondary)
                    .clipShape(Capsule())
                ConfidenceBadge(confidence: snapshot.confidence)
                if snapshot.isBaselining {
                    Label("Building baseline — provisional", systemImage: "hourglass")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 2)

            // Quiet, non-modal: a recompute moved today's verdict on new data.
            if model.showUpdatedNotice {
                Label("Updated with new Apple Health data", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        // The reveal: number races up from 0, the verdict word stamps in a beat
        // later with a haptic — but only the first time today's score is seen.
        // Later opens of Today (revealStatic) render the final value immediately.
        .task(id: volumePercent(snapshot)) {
            guard !revealStatic(snapshot) else { return }
            revealScore = 0
            revealVerdict = false
            withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) {
                revealScore = volumePercent(snapshot)
            }
            try? await Task.sleep(for: .milliseconds(420))
            Haptics.stamp()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                revealVerdict = true
            }
            markRevealed(snapshot)
        }
    }

    // MARK: - Signal lanes

    private func lanesRegister(_ rings: [SignalRing], animated: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What shaped it").sectionLabel()

            VStack(spacing: 16) {
                ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                    Button {
                        breakdownFocus = ring.id
                        showBreakdown = true
                    } label: {
                        SignalLane(ring: ring, revealDelay: 0.35 + Double(index) * 0.08,
                                   animated: animated)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                breakdownFocus = nil
                showBreakdown = true
            } label: {
                HStack {
                    Text("See full breakdown")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var lateRegister: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No check-in today").sectionLabel()
            Text("Full plan volume")
                .font(.displayBlack(26))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
            Text("A check-in before \(TodayViewModel.checkInCutoffLabel) scales the session to your recovery; it's past that now, so today shows un-scaled. Use your judgment — you can still log everything as usual.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Session register (a start list)

    private func sessionRegister(_ r: TodayViewModel.Readout) -> some View {
        let verdict = r.snapshot?.verdict
        return VStack(alignment: .leading, spacing: 10) {
            Text("Today's session").sectionLabel()

            Text(sessionTitle(r))
                .font(.displayBlack(22))
                .tracking(-0.4)
                .foregroundStyle(Theme.textPrimary)
            Text(volumeLine(r))
                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(verdict?.color ?? Theme.textSecondary)

            if taperDays != nil {
                Label("Taper week — sharpen, don't strain.", systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(Theme.brand)
            }

            VStack(spacing: 0) {
                ForEach(Array(r.displayBlocks.prefix(4).enumerated()), id: \.element.id) { index, block in
                    if index > 0 { LaneLine() }
                    startRow(block)
                }
            }
            .padding(.top, 4)

            if r.displayBlocks.count > 4 {
                Text("+ \(r.displayBlocks.count - 4) more")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            if let session = r.session, !session.sets.isEmpty {
                Button(session.startedAt != nil ? "Resume session" : "Start session") {
                    showPlayer = true
                }
                .buttonStyle(PrimaryButtonStyle(tint: verdict?.color ?? Theme.brand))
                .padding(.top, 6)
            }
        }
    }

    private func sessionTitle(_ r: TodayViewModel.Readout) -> String {
        if let plan = r.plan { return "Week \(plan.weekNumber) · \(plan.dayName)" }
        return r.scaled.title
    }

    private func volumeLine(_ r: TodayViewModel.Readout) -> String {
        guard let snapshot = r.snapshot else { return "Full plan volume" }
        let percent = Int((snapshot.volumeMultiplier * 100).rounded())
        switch snapshot.verdict {
        case .push: return "Full volume · push day"
        case .hold: return "Scaled to \(percent)% · hold day"
        case .backOff: return "Recovery · back off day"
        }
    }

    /// One start-list row: exercise left, tabular target right, scaled reps
    /// struck through their original.
    private func startRow(_ block: TodayViewModel.DisplayBlock) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(block.name)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            if let reps = block.scaledReps {
                HStack(spacing: 6) {
                    if let unscaled = block.unscaledReps, unscaled != reps {
                        Text("\(unscaled)")
                            .foregroundStyle(Theme.textSecondary)
                            .strikethrough()
                    }
                    Text(block.distanceM.map { "\(reps) × \($0)m" } ?? "\(reps)×")
                        .foregroundStyle(Theme.textPrimary)
                }
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            }
        }
        .padding(.vertical, 11)
    }

    private func recoveryRegister(_ r: TodayViewModel.Readout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recovery day").sectionLabel()
            Text("Today builds tomorrow. Four easy items — they count.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 0) {
                ForEach(Array(r.displayBlocks.enumerated()), id: \.element.id) { index, block in
                    if index > 0 { LaneLine() }
                    HStack(spacing: 10) {
                        Image(systemName: "circle").foregroundStyle(Theme.backOff)
                        Text(block.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, 11)
                }
            }
            .padding(.top, 4)

            if let session = r.session, !session.sets.isEmpty {
                Button(session.startedAt != nil ? "Resume recovery" : "Start recovery") {
                    showPlayer = true
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.backOff))
                .padding(.top, 6)
            }
        }
    }

    private func restRegister(_ r: TodayViewModel.Readout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rest day").sectionLabel()
            Text(r.plan?.fittedToRest == true
                 ? "Your plan is fitted to \(r.plan?.weeklyTrainingDays ?? 0) training days a week, so a lower-priority session was trimmed here. Keep it easy or off."
                 : "Nothing scheduled. Easy movement is fine; sleep is better.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Evening recap

    private func recapRegister(_ session: TrainingSession) -> some View {
        let planned = session.sets.reduce(0) { $0 + $1.plannedSets }
        let completed = session.sets.reduce(0) { $0 + $1.completedSets }
        let hadPR = session.sets.contains { $0.wasPR }
        // Animate the trophy pop only while the (once-per-session) celebration is
        // playing; a PR seen on a later open shows the trophy at rest.
        let animatePR = hadPR && !session.prCelebrated && !reduceMotion
        return Button {
            summaryCelebrates = false
            showSummary = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(session.isRecovery ? "Recovery done" : "Session done").sectionLabel()
                    Spacer()
                    if hadPR {
                        Label("New PR", systemImage: "trophy.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.brand)
                            .scaleEffect(animatePR && !prPop ? 0.6 : 1)
                            .opacity(animatePR && !prPop ? 0 : 1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 28) {
                    stat(value: "\(completed)/\(planned)", label: session.isRecovery ? "items" : "reps")
                    if session.activeSeconds > 0 {
                        stat(value: durationText(session.activeSeconds), label: "duration")
                    }
                    stat(value: session.title, label: "session", numeric: false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hadPR ? "Opens the summary to share your PR" : "Opens the session summary")
        .sheet(isPresented: $showSummary) {
            SessionSummaryView(session: session, firstName: profile?.firstName ?? "",
                               celebrates: summaryCelebrates) { showSummary = false }
                .presentationBackground(Theme.background)
        }
        // The payoff moment: a PR earns a success haptic and a one-shot confetti
        // burst — exactly once per session (persisted), never re-firing on a later
        // open of Today. The trophy still shows (at rest) under Reduce Motion.
        .task(id: session.persistentModelID) {
            guard hadPR, !session.prCelebrated else { return }
            session.prCelebrated = true
            try? context.save()
            Haptics.success()
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { prPop = true }
            celebratePR = true
            try? await Task.sleep(for: .seconds(2))
            celebratePR = false
        }
    }

    private func stat(value: String, label: String, numeric: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(numeric ? .timingBoard(24, weight: .bold) : .subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(label).sectionLabel()
        }
    }

    private func tomorrowCard(_ tomorrow: TodayViewModel.TomorrowPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tomorrow · \(tomorrow.title)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(tomorrow.cue)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .cadenceCard(surface: Theme.surfaceSecondary)
    }

    private func durationText(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: - Plan chrome (kept from the previous Today)

    private func planHeader(_ plan: TodayViewModel.PlanContext, proposal: AdjustmentProposal?) -> some View {
        Button { showPlanOverview = true } label: {
            HStack(spacing: 8) {
                Text("WEEK \(plan.weekNumber) / \(plan.durationWeeks)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                Text("·").foregroundStyle(Theme.textSecondary)
                Text(plan.phaseName).font(.caption)
                Image(systemName: "chevron.right").font(.caption2)
                Spacer()
                Text(loadLabel(plan.load))
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.surfaceSecondary)
                    .foregroundStyle(Theme.textSecondary)
                    .clipShape(Capsule())
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPlanOverview) {
            PlanOverviewView(
                template: plan.template, currentWeek: plan.weekNumber, dayInWeek: plan.dayInWeek,
                trainingDays: plan.weeklyTrainingDays, maxHighDays: plan.maxHighDays,
                proposal: proposal,
                onApply: { if let p = proposal { applyProposal(p) }; showPlanOverview = false },
                onDismiss: { if let p = proposal { dismissProposal(p) }; showPlanOverview = false })
        }
    }

    private var planCompleteBanner: some View {
        Label("Plan complete — nice work. Showing maintenance sessions until you start a new block.",
              systemImage: "checkmark.seal.fill")
            .font(.subheadline)
            .foregroundStyle(Theme.push)
            .cadenceCard()
    }

    private var personalizedBanner: some View {
        HStack {
            Label("Personalized for you this week", systemImage: "wand.and.stars")
                .font(.caption).foregroundStyle(Theme.brand)
            Spacer()
            Button("Undo", action: undoPersonalization)
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }
        .cadenceCard(padding: 12)
    }

    private var draftNotice: some View {
        Text("These plans are a coach-review draft and a starting structure — not coaching or medical advice. Have a qualified coach individualize before following them.")
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .cadenceCard(padding: 12)
    }

    private var disclaimerFooter: some View {
        Text(Disclaimer.short)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    /// What kind of day the plan calls for, in words an athlete uses. Neutral
    /// on purpose: this chip used the verdict colours, so a green "HIGH" or an
    /// amber "LOW" sat next to the PUSH / HOLD verdict and read like a second,
    /// contradicting verdict.
    private func loadLabel(_ load: LoadLevel) -> String {
        switch load {
        case .high: return "SPEED DAY"
        case .low: return "EASY DAY"
        case .rest: return "REST DAY"
        }
    }

    // MARK: - Personalization actions (all reversible, none bypass the engine)

    private func applyProposal(_ proposal: AdjustmentProposal) {
        guard let profile else { return }
        let coordinator = PersonalizationCoordinator(context: context)
        coordinator.apply(proposal, event: profile.event)
        coordinator.dismiss(proposal)
        Task { await reload() }
    }

    private func dismissProposal(_ proposal: AdjustmentProposal) {
        PersonalizationCoordinator(context: context).dismiss(proposal)
        Task { await reload() }
    }

    private func undoPersonalization() {
        guard let profile else { return }
        PersonalizationCoordinator(context: context).undo(event: profile.event)
        Task { await reload() }
    }
}
