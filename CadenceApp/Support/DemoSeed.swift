#if DEBUG
import Foundation
import SwiftData
import CadenceCore

/// DEBUG-only. Populates a realistic, deterministic app state so the UI can be
/// screenshotted in the simulator (where HealthKit returns nothing and there's
/// no way to tap through onboarding + check-in from the CLI). Never ships —
/// wrapped in `#if DEBUG` and only runs when launched with `CADENCE_DEMO=1`.
///
/// Launch:  xcrun simctl launch --terminate-running-process <sim> net.adnanahmad.Cadence
///          (after `simctl launch` with environment CADENCE_DEMO=1)
@MainActor
enum DemoSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["CADENCE_DEMO"] == "1"
    }

    /// Verdict to seed, so I can screenshot push / hold / backOff states.
    /// `CADENCE_DEMO_VERDICT` = push | hold | backOff (default hold).
    private static var verdict: Verdict {
        switch ProcessInfo.processInfo.environment["CADENCE_DEMO_VERDICT"] {
        case "push": return .push
        case "backOff": return .backOff
        default: return .hold
        }
    }

    /// Seed a *completed* session with a PR, so the evening recap and the PR
    /// confetti burst can be screenshotted. `CADENCE_DEMO_RECAP=1`.
    private static var seedRecap: Bool {
        ProcessInfo.processInfo.environment["CADENCE_DEMO_RECAP"] == "1"
    }

    /// Omit today's completed check-in so Today shows the gate (the check-in CTA
    /// before the cutoff, or the un-scaled late register after it). `CADENCE_DEMO_NOCHECKIN=1`.
    private static var skipCheckIn: Bool {
        ProcessInfo.processInfo.environment["CADENCE_DEMO_NOCHECKIN"] == "1"
    }

    /// Cold-start state: provisional score, "building baseline" notice, low
    /// confidence, and a short history. `CADENCE_DEMO_BASELINING=1`.
    private static var baselining: Bool {
        ProcessInfo.processInfo.environment["CADENCE_DEMO_BASELINING"] == "1"
    }

    /// Push the plan start back past week 12 so Today shows the plan-complete
    /// banner and maintenance sessions. `CADENCE_DEMO_PLANDONE=1`.
    private static var planDone: Bool {
        ProcessInfo.processInfo.environment["CADENCE_DEMO_PLANDONE"] == "1"
    }

    /// Bulk history for performance testing: ~200 completed sessions + readiness
    /// days across a long season. `CADENCE_DEMO_BULK=1`.
    private static var bulk: Bool {
        ProcessInfo.processInfo.environment["CADENCE_DEMO_BULK"] == "1"
    }

    static func seed(into context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // Wipe any prior demo state so relaunches are deterministic.
        for model: any PersistentModel.Type in [AthleteProfile.self, CheckIn.self,
                                                 DailyReadiness.self, TrainingSession.self,
                                                 SessionSet.self, PersonalRecord.self] {
            try? context.delete(model: model)
        }

        // Athlete — Week 3 of the 100m plan. Meet 23 days out by default; override
        // with CADENCE_DEMO_MEET=<days> to screenshot taper mode (e.g. 3, 1, 0).
        let meetOffset = ProcessInfo.processInfo.environment["CADENCE_DEMO_MEET"]
            .flatMap(Int.init) ?? 23
        let profile = AthleteProfile(
            firstName: "Marcus",
            meetDate: cal.date(byAdding: .day, value: meetOffset, to: today),
            event: .sprint100,
            goalTimeSeconds: 11.2,
            weeklyTrainingDays: 4,
            experienceLevel: .developing,
            // -15d = week 3 of 12; -95d puts the athlete past week 12 (plan complete).
            planStartDate: cal.date(byAdding: .day, value: planDone ? -95 : -15, to: today),
            hasCompletedOnboarding: true,
            hasAcknowledgedDisclaimer: true)
        context.insert(profile)

        // A completed check-in for today, so Today shows the score (not the gate).
        // Omitted under CADENCE_DEMO_NOCHECKIN to exercise the gate/late states.
        if !skipCheckIn {
            let checkIn = CheckIn(day: today)
            checkIn.wellnessSleep = 3; checkIn.wellnessSoreness = 3
            checkIn.wellnessFatigue = 2; checkIn.wellnessStress = 4; checkIn.wellnessMood = 4
            checkIn.fingerTapCount = 58
            checkIn.completedAt = .now
            context.insert(checkIn)
        }

        // 14 days of prior readiness so Trends/rings have history. Scores span the
        // real verdict bands (push ≥66 / hold ≥40 / back off below) including one
        // rough day and a mild recent easing — so the chart shows the true spread
        // and matches the "readiness drifted down" narrative. Index 0 = yesterday.
        let history: [Int] = [64, 71, 55, 88, 79, 48, 90, 66, 84, 38, 73, 86, 80, 70]
        // Cold-start seeds only a couple of prior days, so baselines are genuinely thin.
        let historyDays = baselining ? 2 : 14
        for offset in 1...historyDays {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            context.insert(DailyReadiness(
                date: day, output: output(score: Double(history[offset - 1])),
                hrvSDNN: 55 + Double(offset % 5) * 3, sleepSeconds: 7.2 * 3600, restingHR: 48))
            // A completed check-in each day (readiness implies one), so the streak
            // reflects the history rather than reading 1.
            let pastCheckIn = CheckIn(day: day)
            pastCheckIn.completedAt = cal.date(byAdding: .hour, value: 8, to: day)
            context.insert(pastCheckIn)
        }

        // A handful of completed past sessions so History's timeline and Trends'
        // volume bars are real (not just today's). Verdict/volume derive from that
        // day's seeded score; one older session carries a PR.
        let past: [(offset: Int, title: String, sets: [(String, Int, Int, Double?)])] = [
            (2,  "Tempo + Mobility",           [("Tempo 100m", 8, 8, nil), ("Mobility circuit", 3, 3, nil)]),
            (4,  "Acceleration Development",   [("Block starts 20m", 6, 6, nil), ("Flys 30m", 4, 4, nil)]),
            (5,  "Speed + Strength",           [("Speed 60m", 4, 3, nil), ("Back squat", 5, 5, nil)]),
            (9,  "Acceleration Development",   [("Block starts 20m", 6, 6, 2.42)]),
            (11, "Tempo + Mobility",           [("Tempo 150m", 6, 6, nil)]),
            (12, "Speed + Strength",           [("Speed 60m", 4, 4, nil), ("Bounds", 4, 4, nil)]),
        ]
        for spec in past {
            guard let day = cal.date(byAdding: .day, value: -spec.offset, to: today) else { continue }
            let score = Double(history[spec.offset - 1])
            let (v, mult) = verdictAndMultiplier(forScore: score)
            let session = TrainingSession(
                date: day, title: spec.title, verdict: v,
                readinessScore: score, volumeMultiplier: mult, wasAdjusted: v != .push)
            session.isComplete = true
            session.completedAt = cal.date(byAdding: .hour, value: 9, to: day)
            session.activeSeconds = Double(38 + spec.offset % 6) * 60
            session.prCelebrated = true   // historical PRs already celebrated
            session.sets = spec.sets.enumerated().map { i, s in
                SessionSet(name: s.0, order: i, plannedSets: s.1,
                           completedSets: s.2, bestTimeSeconds: s.3, wasPR: s.3 != nil)
            }
            context.insert(session)
        }

        // Today's readiness — the seeded verdict.
        let scores: (Double, Double) = { switch verdict {
            case .push: return (88, 1.0); case .hold: return (78, 0.75); case .backOff: return (61, 0.6) } }()
        context.insert(DailyReadiness(
            date: today,
            output: output(score: scores.0, verdict: verdict, multiplier: scores.1),
            hrvSDNN: 52, sleepSeconds: 6.8 * 3600, restingHR: 51))

        // Standing PRs so the tracker + PB→goal (event = 100m, goal 11.2) have data.
        context.insert(PersonalRecord(key: "100m", bestTimeSeconds: 11.62, achievedOn: cal.date(byAdding: .day, value: -12, to: today)!))
        // Under the recap seed today's session broke this record (6.95 → 6.88),
        // so the stored record is the new time, set today.
        context.insert(PersonalRecord(key: "60m", bestTimeSeconds: seedRecap ? 6.88 : 6.95,
                                      achievedOn: seedRecap ? today : cal.date(byAdding: .day, value: -9, to: today)!))

        // A completed session (with a PR block) so the recap + confetti render.
        if seedRecap {
            let session = TrainingSession(
                date: today, title: "Speed · Acceleration",
                verdict: verdict, readinessScore: scores.0,
                volumeMultiplier: scores.1, wasAdjusted: verdict != .push)
            session.isComplete = true
            session.completedAt = .now
            session.startedAt = cal.date(byAdding: .minute, value: -48, to: .now)
            session.activeSeconds = 42 * 60
            session.sets = [
                SessionSet(name: "Block starts 10m", order: 0, plannedSets: 6,
                           distanceMeters: 10, completedSets: 6),
                SessionSet(name: "Flying 20s", order: 1, plannedSets: 4,
                           distanceMeters: 20, completedSets: 4,
                           bestTimeSeconds: 2.21),
                SessionSet(name: "Speed 60m", order: 2, plannedSets: 3,
                           distanceMeters: 60, completedSets: 3,
                           bestTimeSeconds: 6.88, wasPR: true),
            ]
            session.sets[2].previousBestSeconds = 6.95
            context.insert(session)
        }

        // Performance seed: a long season of completed sessions + readiness days,
        // so History/Trends can be checked for hitching at realistic scale.
        if bulk {
            let titles = ["Tempo + Mobility", "Acceleration Development", "Speed + Strength",
                          "Speed Endurance", "Recovery protocol"]
            for offset in 15...260 {
                guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                // Deterministic pseudo-variation (no Math.random — keeps runs comparable).
                let score = Double(40 + (offset * 7 + offset % 13 * 3) % 55)
                context.insert(DailyReadiness(
                    date: day, output: output(score: score),
                    hrvSDNN: 48 + Double(offset % 11), sleepSeconds: 6.5 * 3600 + Double(offset % 5) * 900,
                    restingHR: 46 + Double(offset % 7)))
                let past = CheckIn(day: day)
                past.completedAt = cal.date(byAdding: .hour, value: 8, to: day)
                context.insert(past)

                // ~4 sessions a week.
                guard offset % 7 < 4 else { continue }
                let (v, mult) = verdictAndMultiplier(forScore: score)
                let session = TrainingSession(
                    date: day, title: titles[offset % titles.count], verdict: v,
                    readinessScore: score, volumeMultiplier: mult, wasAdjusted: v != .push)
                session.isComplete = true
                session.completedAt = cal.date(byAdding: .hour, value: 17, to: day)
                session.activeSeconds = Double(35 + offset % 25) * 60
                session.sets = [
                    SessionSet(name: "Main set", order: 0, plannedSets: 6,
                               distanceMeters: 100, completedSets: 6,
                               bestTimeSeconds: offset % 37 == 0 ? 11.4 : nil,
                               wasPR: offset % 37 == 0),
                    SessionSet(name: "Strength", order: 1, plannedSets: 4, completedSets: 4),
                ]
                context.insert(session)
            }
        }

        try? context.save()
    }

    /// Verdict + volume multiplier for a score, matching the engine's curve.
    private static func verdictAndMultiplier(forScore score: Double) -> (Verdict, Double) {
        let config = ReadinessConfig()
        let mult = Normalization.multiplier(fromScore: score, config: config)
        let verdict: Verdict = mult >= config.pushMultiplierThreshold ? .push
            : (mult >= config.holdMultiplierThreshold ? .hold : .backOff)
        return (verdict, mult)
    }

    /// Build a plausible ReadinessOutput with per-signal subscores so the lanes
    /// populate. When `verdict`/`multiplier` are omitted they're derived from the
    /// score exactly as the engine would (via the real config + curve), so seeded
    /// history days carry an honest verdict instead of a blanket push.
    private static func output(score: Double, verdict: Verdict? = nil,
                               multiplier: Double? = nil) -> ReadinessOutput {
        let config = ReadinessConfig()
        let mult = multiplier ?? Normalization.multiplier(fromScore: score, config: config)
        let v = verdict ?? {
            if mult >= config.pushMultiplierThreshold { return .push }
            if mult >= config.holdMultiplierThreshold { return .hold }
            return .backOff
        }()
        return ReadinessOutput(
            score: score,
            verdict: v,
            volumeMultiplier: mult,
            // A baselining day can't cite a baseline it doesn't have yet.
            reason: baselining
                ? "Still learning your normal — a few more mornings and this score gets sharper."
                : (v == .backOff
                   ? "Your HRV and sleep are both well below baseline — today is for recovery, and that protects the week."
                   : (v == .push
                      ? "Everything's at or above your baseline — green light. Attack today's session."
                      : "Your HRV is 15% below your baseline — your nervous system is still catching up from Tuesday's speed work.")),
            confidence: baselining ? .low : .high,
            isBaselining: baselining,
            baselineSampleCount: baselining ? 2 : 30,
            // Components must agree with the narrative above: a push day claims
            // "everything's at or above your baseline", so every lane has to
            // read at or above it. The hold day keeps the mixed set the HRV
            // sentence describes.
            components: v == .push
                ? ComponentScores(
                    hrv: 88,
                    sleep: 84, sleepQuality: 86,
                    rhr: 85, respiratoryRate: 83, wristTemperature: 84,
                    trainingLoad: 82,
                    wellness: 85, fingerTap: 87, countermovementJump: nil)
                : ComponentScores(
                    hrv: 42,
                    sleep: 55, sleepQuality: 58,
                    rhr: 78, respiratoryRate: 70, wristTemperature: 68,
                    trainingLoad: 64,
                    wellness: 62, fingerTap: 66, countermovementJump: nil))
    }
}
#endif
