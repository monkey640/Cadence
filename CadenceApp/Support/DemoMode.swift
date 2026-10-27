import Foundation
import SwiftData
import CadenceCore

#if DEBUG
/// DEBUG-only demo mode, for filming and showing the app: a **separate** SwiftData
/// store seeded with about five weeks of consistent use — a check-in every
/// morning, the athlete's real plan sessions on training days, readiness that
/// dips after hard sessions and trends upward, and a few training PRs.
///
/// The athlete's real store is never touched: switching demo mode on opens
/// `CadenceDemo.store` instead, and switching it off reopens the real one exactly
/// as it was. The demo profile copies the real one (name, event, PB, goal, meet,
/// training days), so the demo shows *their* app, not a stranger's.
///
/// While it's on, nothing recomputes today from HealthKit (see `isOn` call
/// sites), so the chosen verdict holds for filming. The history is invented —
/// present it as an example, never as the athlete's own record.
///
/// Never ships: compiled out of Release builds, where `isOn` is always false.
@MainActor
enum DemoMode {
    enum Key {
        static let enabled = "demo.enabled"
        static let verdict = "demo.verdict"
        static let checkedIn = "demo.todayCheckedIn"
    }

    /// Days of invented history before today.
    static let historyDays = 36

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: Key.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.enabled) }
    }

    /// The verdict today's seeded readiness lands on.
    static var todayVerdict: Verdict {
        get { UserDefaults.standard.string(forKey: Key.verdict).flatMap(Verdict.init(rawValue:)) ?? .push }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.verdict) }
    }

    /// Off = today has no check-in yet, so the real check-in flow can be filmed.
    static var todayCheckedIn: Bool {
        get { UserDefaults.standard.object(forKey: Key.checkedIn) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.checkedIn) }
    }

    static var storeURL: URL { URL.applicationSupportDirectory.appending(path: "CadenceDemo.store") }

    static func makeContainer() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: .applicationSupportDirectory,
                                                withIntermediateDirectories: true)
        let config = ModelConfiguration("CadenceDemo", schema: AppSchema.schema, url: storeURL)
        return try ModelContainer(for: AppSchema.schema, configurations: config)
    }

    // MARK: - Profile copy

    /// The parts of the real profile the demo reuses.
    struct ProfileSnapshot {
        var firstName: String
        var event: Event
        var goalTimeSeconds: Double?
        var meetDate: Date?
        var weeklyTrainingDays: Int
        var weekdayMask: Int
        var experience: ExperienceLevel
        var eventPB: Double?

        static func read(from context: ModelContext) -> ProfileSnapshot? {
            guard let profile = try? context.fetch(FetchDescriptor<AthleteProfile>()).first else { return nil }
            let key = profile.event.rawValue
            let pb = (try? context.fetch(FetchDescriptor<PersonalRecord>(
                predicate: #Predicate { $0.key == key })))?.first?.bestTimeSeconds
            return ProfileSnapshot(
                firstName: profile.firstName, event: profile.event,
                goalTimeSeconds: profile.goalTimeSeconds, meetDate: profile.meetDate,
                weeklyTrainingDays: profile.weeklyTrainingDays,
                weekdayMask: profile.trainingWeekdayMask,
                experience: profile.experienceLevel, eventPB: pb)
        }
    }

    // MARK: - Seeding

    /// Wipes the demo store and fills it. Deterministic: the same day and settings
    /// always produce the same history.
    static func populate(_ context: ModelContext, from snapshot: ProfileSnapshot?) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let config = ReadinessConfig.standard

        for model: any PersistentModel.Type in [AthleteProfile.self, CheckIn.self, DailyReadiness.self,
                                                 TrainingSession.self, SessionSet.self,
                                                 PersonalRecord.self, PlanAdjustment.self] {
            try? context.delete(model: model)
        }
        // Let today's one-shot reveal play again on the fresh demo day.
        UserDefaults.standard.removeObject(forKey: "today.reveal.lastDayOrdinal")

        let name = snapshot?.firstName.trimmingCharacters(in: .whitespaces) ?? ""
        let event = snapshot?.event ?? .sprint100
        let experience = snapshot?.experience ?? .developing
        let trainingDays = snapshot?.weeklyTrainingDays ?? 4
        let template = PlanLibraryLoader.template(for: event)

        // Start the plan ~5 weeks back, nudged so today lands on a training day —
        // a demo whose "today" is a rest day has nothing to show.
        var planStart = cal.date(byAdding: .day, value: -historyDays, to: today)!
        for back in historyDays...(historyDays + 6) {
            let candidate = cal.date(byAdding: .day, value: -back, to: today)!
            if planDay(on: today, planStart: candidate, template: template,
                       trainingDays: trainingDays, maxHighDays: experience.maxHighDays) != nil {
                planStart = candidate
                break
            }
        }
        let totalDays = cal.dateComponents([.day], from: planStart, to: today).day ?? historyDays

        let profile = AthleteProfile(
            firstName: name.isEmpty ? "Zain" : name,
            // Keep their real meet; with none set, show one a few weeks out so the
            // countdown and taper are visible.
            meetDate: snapshot?.meetDate.flatMap { $0 >= today ? $0 : nil }
                ?? cal.date(byAdding: .day, value: 24, to: today),
            event: event,
            goalTimeSeconds: snapshot?.goalTimeSeconds,
            weeklyTrainingDays: trainingDays,
            experienceLevel: experience,
            planStartDate: planStart,
            hasCompletedOnboarding: true,
            hasAcknowledgedDisclaimer: true)
        profile.trainingWeekdayMask = snapshot?.weekdayMask ?? 0
        context.insert(profile)

        // Their real event PB carries over unchanged — the demo invents training
        // PRs (short timed reps) but never a race result.
        if let pb = snapshot?.eventPB {
            context.insert(PersonalRecord(key: event.rawValue, bestTimeSeconds: pb,
                                          achievedOn: cal.date(byAdding: .day, value: -60, to: today)!))
        }

        // Pass 1: what the plan called for each day, so a hard day can depress the next.
        var plans: [Int: PlanDayInfo] = [:]
        for offset in 1...totalDays {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            plans[offset] = planDay(on: day, planStart: planStart, template: template,
                                    trainingDays: trainingDays, maxHighDays: experience.maxHighDays)
        }

        var best: [String: Double] = [:]
        for offset in stride(from: totalDays, through: 1, by: -1) {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let daysIn = totalDays - offset             // days of history before this one
            let progress = Double(daysIn) / Double(totalDays)
            let score = historyScore(offset: offset, progress: progress,
                                     dayAfterHard: plans[offset + 1]?.load == .high)
            let baselining = daysIn < config.minBaselineDays
            let (verdict, multiplier) = verdictAndMultiplier(score: score, config: config)
            let checkInTime = cal.date(byAdding: .minute, value: 7 * 60 + 20 + offset % 25, to: day)!

            context.insert(checkIn(on: day, at: checkInTime, score: score, seed: offset))
            context.insert(DailyReadiness(
                date: day,
                output: output(score: score, verdict: verdict, multiplier: multiplier,
                               baselining: baselining, samples: daysIn, seed: offset),
                hrvSDNN: 60 + (score - 72) * 0.45 + noise(offset * 3) * 2,
                sleepSeconds: (7.3 + (score - 72) * 0.02 + noise(offset * 5) * 0.3) * 3600,
                restingHR: 50 - (score - 72) * 0.12,
                at: checkInTime))

            if verdict == .backOff {
                context.insert(recoverySession(on: day, score: score, multiplier: multiplier))
            } else if let plan = plans[offset] {
                context.insert(trainingSession(on: day, plan: plan, score: score,
                                               verdict: verdict, multiplier: multiplier,
                                               progress: progress, seed: offset, best: &best))
            }
        }

        // Training records from the invented history.
        for (key, time) in best where key != event.rawValue {
            context.insert(PersonalRecord(key: key, bestTimeSeconds: time,
                                          achievedOn: cal.date(byAdding: .day, value: -3, to: today)!))
        }

        // Today: the chosen verdict, or no check-in yet (to film the real flow).
        if todayCheckedIn {
            let score: Double = switch todayVerdict {
            case .push: 87
            case .hold: 61
            case .backOff: 36
            }
            let (verdict, multiplier) = verdictAndMultiplier(score: score, config: config)
            let at = min(Date.now, cal.date(byAdding: .minute, value: 7 * 60 + 35, to: today)!)
            context.insert(checkIn(on: today, at: at, score: score, seed: 0))
            context.insert(DailyReadiness(
                date: today,
                output: output(score: score, verdict: verdict, multiplier: multiplier,
                               baselining: false, samples: totalDays, seed: 0, today: true),
                hrvSDNN: 60 + (score - 72) * 0.45, sleepSeconds: (7.3 + (score - 72) * 0.02) * 3600,
                restingHR: 50 - (score - 72) * 0.12, at: at))
        }

        try? context.save()
    }

    // MARK: - Plan days

    struct PlanDayInfo {
        let title: String
        let load: LoadLevel
        let blocks: [PlanBlock]          // track-work blocks, in order
        let planned: PlannedSession
    }

    /// The plan's session for a date, or nil on rest / trimmed days — mirroring
    /// how Today resolves the plan.
    private static func planDay(on date: Date, planStart: Date, template: PlanTemplate?,
                                trainingDays: Int, maxHighDays: Int) -> PlanDayInfo? {
        guard let template else { return nil }
        let cal = Calendar.current
        let elapsed = cal.dateComponents([.day], from: cal.startOfDay(for: planStart),
                                         to: cal.startOfDay(for: date)).day ?? 0
        guard elapsed >= 0 else { return nil }
        let week = elapsed / 7 + 1
        guard week <= template.durationWeeks,
              let selection = PlanScheduler.selectDay(in: template, week: week, dayInWeek: elapsed % 7 + 1)
        else { return nil }
        let kept = PlanFitter.keptTrainingDays(in: selection.phase.weeklyMicrocycle,
                                               trainingDays: trainingDays, maxHighDays: maxHighDays)
        guard !PlanFitter.isTrimmedToRest(selection.day, kept: kept),
              selection.day.load != .rest,
              !selection.day.trackworkBlocks.isEmpty
        else { return nil }
        return PlanDayInfo(title: selection.day.name, load: selection.day.load,
                           blocks: selection.day.trackworkBlocks,
                           planned: selection.day.scalableSession())
    }

    // MARK: - Sessions

    private static func trainingSession(on day: Date, plan: PlanDayInfo, score: Double,
                                        verdict: Verdict, multiplier: Double, progress: Double,
                                        seed: Int, best: inout [String: Double]) -> TrainingSession {
        let cal = Calendar.current
        let scaled = SessionScaler.scale(plan.planned, by: multiplier)
        let session = TrainingSession(date: day, title: scaled.title, verdict: verdict,
                                      readinessScore: score, volumeMultiplier: multiplier,
                                      wasAdjusted: scaled.wasAdjusted)
        session.hadCheckIn = true
        session.isComplete = true
        session.prCelebrated = true
        session.startedAt = cal.date(byAdding: .minute, value: 16 * 60 + 5, to: day)
        session.activeSeconds = Double(38 + seed % 17) * 60
        session.completedAt = session.startedAt?.addingTimeInterval(session.activeSeconds + 300)

        session.sets = zip(plan.blocks, scaled.blocks).enumerated().map { index, pair in
            let (block, scaledBlock) = pair
            let planned = scaledBlock.sets
            // Now and then a set gets cut short — real logs aren't perfect.
            let completed = (seed + index) % 13 == 0 ? max(0, planned - 1) : planned
            let set = SessionSet(
                name: scaledBlock.name, order: index, plannedSets: planned,
                distanceMeters: scaledBlock.distanceMeters,
                qualityRaw: block.type?.quality?.rawValue,
                completedSets: completed,
                restSeconds: RestParser.seconds(from: block.rest))

            // Time the short speed reps — the ones an athlete actually clocks.
            if let distance = scaledBlock.distanceMeters, distance <= 60,
               block.type == .accel || block.type == .maxVelocity {
                let flying = block.name.lowercased().contains("fly")
                let time = repTime(distance: distance, flying: flying, progress: progress,
                                   score: score, seed: seed * 31 + index)
                let key = PersonalRecordTracker.key(forDistance: distance)
                set.bestTimeSeconds = time
                if let previous = best[key] {
                    // A PR has to clear the day-to-day wobble, not just tie it.
                    if time < previous - 0.02 {
                        set.wasPR = true
                        set.previousBestSeconds = previous
                        best[key] = time
                    }
                } else {
                    best[key] = time     // first time on record sets the mark, quietly
                }
            }
            return set
        }
        return session
    }

    private static func recoverySession(on day: Date, score: Double, multiplier: Double) -> TrainingSession {
        let cal = Calendar.current
        let session = TrainingSession(date: day, title: RecoveryProtocol.sessionTitle, verdict: .backOff,
                                      readinessScore: score, volumeMultiplier: multiplier, wasAdjusted: true)
        session.hadCheckIn = true
        session.isRecovery = true
        session.isComplete = true
        session.prCelebrated = true
        session.startedAt = cal.date(byAdding: .minute, value: 17 * 60, to: day)
        session.activeSeconds = 24 * 60
        session.completedAt = session.startedAt?.addingTimeInterval(session.activeSeconds)
        session.sets = RecoveryProtocol.items.enumerated().map { index, item in
            SessionSet(name: item.name, order: index, plannedSets: 1, completedSets: 1)
        }
        return session
    }

    /// A believable high-school sprint time. Fitness improves in a step, not a
    /// smooth slope — a plateau, then a jump mid-block — so PRs come a few at a
    /// time. A smooth curve made almost every session a record, which read fake.
    private static func repTime(distance: Double, flying: Bool, progress: Double,
                                score: Double, seed: Int) -> Double {
        let base = flying ? distance / 9.2 : 0.78 + distance * 0.108
        let trained = progress < 0.55 ? 1.0 : 0.984           // ~1.6% faster after the jump
        let readiness = 1 - (score - 72) * 0.0001             // fresher days run a touch faster
        let wobble = 1 + noise(seed) * 0.002
        return (base * trained * readiness * wobble * 100).rounded() / 100
    }

    // MARK: - Readiness

    /// Mostly push and hold, drifting up as the athlete adapts, dipping the day
    /// after a hard session — with one sick day and one rough morning.
    private static func historyScore(offset: Int, progress: Double, dayAfterHard: Bool) -> Double {
        if offset == 23 { return 34 }      // sick day → back off
        if offset == 9 { return 51 }       // rough morning → hold
        var score = 71 + progress * 9 + noise(offset) * 7
        if dayAfterHard { score -= 9 }
        return min(94, max(42, score.rounded()))
    }

    private static func verdictAndMultiplier(score: Double, config: ReadinessConfig) -> (Verdict, Double) {
        let curve = Normalization.multiplier(fromScore: score, config: config)
        if curve >= config.pushMultiplierThreshold { return (.push, config.maxMultiplier) }   // push = full session
        if curve >= config.holdMultiplierThreshold { return (.hold, curve) }
        return (.backOff, curve)
    }

    private static func checkIn(on day: Date, at time: Date, score: Double, seed: Int) -> CheckIn {
        let level = score >= 80 ? 5 : score >= 68 ? 4 : score >= 52 ? 3 : 2
        func answer(_ i: Int) -> Int { min(5, max(1, level + Int((noise(seed * 11 + i) * 1.2).rounded()))) }
        let checkIn = CheckIn(day: day)
        checkIn.wellnessSleep = answer(1)
        checkIn.wellnessSoreness = answer(2)
        checkIn.wellnessFatigue = answer(3)
        checkIn.wellnessStress = answer(4)
        checkIn.wellnessMood = answer(5)
        checkIn.fingerTapCount = (56 + (score - 72) * 0.2 + noise(seed * 13) * 3).rounded()
        checkIn.completedAt = time
        return checkIn
    }

    private static func output(score: Double, verdict: Verdict, multiplier: Double,
                               baselining: Bool, samples: Int, seed: Int,
                               today: Bool = false) -> ReadinessOutput {
        ReadinessOutput(
            score: score, verdict: verdict, volumeMultiplier: multiplier,
            reason: reason(verdict: verdict, baselining: baselining, seed: seed, today: today),
            confidence: baselining ? .low : .high,
            isBaselining: baselining,
            baselineSampleCount: min(samples, 30),
            components: components(score: score, verdict: verdict, seed: seed))
    }

    private static func reason(verdict: Verdict, baselining: Bool, seed: Int, today: Bool) -> String {
        if baselining { return "Still learning your normal — a few more mornings and this score gets sharper." }
        switch verdict {
        case .push:
            return today || seed % 2 == 0
                ? "Everything's at or above your baseline — green light. Attack today's session."
                : "Sleep and HRV are both back above your baseline — you've absorbed the last session."
        case .hold:
            return today || seed % 2 == 0
                ? "Your HRV is 12% below your baseline after yesterday's speed work — trimming today protects the week."
                : "You slept less than usual, so today's volume comes down a notch."
        case .backOff:
            return "HRV and sleep are both well below your baseline — today is for recovery, and that protects the week."
        }
    }

    /// Per-signal subscores that agree with the reason: a push day reads at or
    /// above baseline everywhere; a hold day is led by a low HRV; a back-off day
    /// by low HRV and sleep.
    private static func components(score: Double, verdict: Verdict, seed: Int) -> ComponentScores {
        func c(_ base: Double, _ i: Int) -> Double { min(97, max(18, (base + noise(seed * 7 + i) * 4).rounded())) }
        switch verdict {
        case .push:
            let s = max(score, 82)
            return ComponentScores(hrv: c(s + 1, 1), sleep: c(s - 1, 2), sleepQuality: c(s, 3),
                                   rhr: c(s + 2, 4), respiratoryRate: c(s, 5), wristTemperature: c(s, 6),
                                   trainingLoad: c(s - 2, 7), wellness: c(s, 8), fingerTap: c(s + 1, 9),
                                   countermovementJump: nil)
        case .hold:
            return ComponentScores(hrv: c(score - 20, 1), sleep: c(score - 6, 2), sleepQuality: c(score - 4, 3),
                                   rhr: c(score + 10, 4), respiratoryRate: c(score + 8, 5),
                                   wristTemperature: c(score + 8, 6), trainingLoad: c(score + 2, 7),
                                   wellness: c(score + 4, 8), fingerTap: c(score + 6, 9),
                                   countermovementJump: nil)
        case .backOff:
            return ComponentScores(hrv: c(score - 10, 1), sleep: c(score - 8, 2), sleepQuality: c(score - 6, 3),
                                   rhr: c(score + 6, 4), respiratoryRate: c(score + 4, 5),
                                   wristTemperature: c(score + 2, 6), trainingLoad: c(score + 10, 7),
                                   wellness: c(score, 8), fingerTap: c(score + 4, 9),
                                   countermovementJump: nil)
        }
    }

    /// Deterministic noise in [-1, 1] — no randomness, so a rebuild is repeatable.
    private static func noise(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + 4.1414) * 43758.5453
        return (x - x.rounded(.down)) * 2 - 1
    }
}
#else
/// Demo mode doesn't exist in Release builds.
enum DemoMode {
    static var isOn: Bool { false }
}
#endif
