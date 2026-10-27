import Foundation
import SwiftData
import CadenceCore

/// A training session for a given day: the (possibly scaled) plan plus the
/// readiness context that produced it, and the athlete's logged results.
@Model
final class TrainingSession {
    /// Normalized to the start of the day it belongs to.
    var date: Date
    var title: String

    // --- Readiness snapshot at the time the session was generated ----------
    var verdictRaw: String
    var readinessScore: Double
    var volumeMultiplier: Double
    /// True when the multiplier reduced volume — drives the "Adjusted today" callout.
    var wasAdjusted: Bool

    // --- Completion --------------------------------------------------------
    var completedAt: Date?
    var isComplete: Bool

    // --- Session-player state (persisted continuously so a killed app resumes
    //     exactly where it left off). Inline defaults for lightweight migration.
    /// Set when the athlete first taps "Start session"; nil = not started.
    var startedAt: Date? = nil
    /// Accumulated active seconds (excludes paused time), updated as the player runs.
    var activeSeconds: Double = 0
    /// Index of the block the player was on, for resume.
    var resumeBlockIndex: Int = 0
    /// True for Back Off days: the recovery protocol logged as a real session
    /// type, so history stays complete and the streak logic never sees a gap.
    var isRecovery: Bool = false
    /// False when the session was generated without a check-in (opened after
    /// 2 PM, shown at full plan volume) — history then hides the readiness badge.
    var hadCheckIn: Bool = true

    /// True for athlete-authored workouts (built from the movement library),
    /// vs plan-derived sessions. Inline default for lightweight migration.
    var isCustom: Bool = false

    /// One-tap "ill / unusually stressed today?" marker. Off by default. Excludes
    /// the session from deficiency detection (confounder exclusion, per the spec).
    /// Inline default lets SwiftData lightweight-migrate existing stores.
    var flaggedExternalStress: Bool = false

    /// Set once the PR celebration (confetti + success haptic) has fired for this
    /// session, so the payoff plays exactly once — never re-firing on later opens
    /// of Today. Inline default for lightweight migration.
    var prCelebrated: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \SessionSet.session)
    var sets: [SessionSet]

    init(
        date: Date,
        title: String,
        verdict: Verdict,
        readinessScore: Double,
        volumeMultiplier: Double,
        wasAdjusted: Bool,
        isCustom: Bool = false,
        flaggedExternalStress: Bool = false,
        sets: [SessionSet] = []
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.title = title
        self.verdictRaw = verdict.rawValue
        self.readinessScore = readinessScore
        self.volumeMultiplier = volumeMultiplier
        self.wasAdjusted = wasAdjusted
        self.completedAt = nil
        self.isComplete = false
        self.isCustom = isCustom
        self.flaggedExternalStress = flaggedExternalStress
        self.sets = sets
    }

    var verdict: Verdict { Verdict(rawValue: verdictRaw) ?? .hold }
}

/// A subjective end-of-block marker for endurance reps — the low-friction
/// substitute for a true within-rep split. One tap.
enum FadeMarker: String, Codable, Sendable {
    case held    // held pace through the rep
    case faded   // faded late
}

/// One block of a session (e.g. "6 × 60m"), with planned target and logged result.
@Model
final class SessionSet {
    var name: String
    var order: Int

    /// Planned number of sets/reps (already scaled by the readiness multiplier).
    var plannedSets: Int
    var distanceMeters: Double?
    /// Planned target duration per rep, if time-based.
    var targetSeconds: Double?
    /// The block's quality (CadenceCore `Quality` raw value), so the app knows
    /// which blocks are endurance (fade marker) and can route detection signals.
    var qualityRaw: String?
    /// Glossary movement id, so any block (plan or custom) can show its how-to.
    var movementID: String?

    // --- Logged results ----------------------------------------------------
    var completedSets: Int
    /// Best logged time across reps of this block, seconds — used for PR detection.
    var bestTimeSeconds: Double?
    /// True if this block's logged time set a personal record (drives the PR badge).
    /// Inline default lets SwiftData lightweight-migrate existing stores.
    var wasPR: Bool = false
    /// The record this block's time beat, seconds — nil when it wasn't a PR or
    /// it was the first time on record. Lets the summary say "was 11.62, −0.14s"
    /// after the tracker has overwritten the stored record. Inline default for
    /// migration.
    var previousBestSeconds: Double? = nil
    /// Subjective "held pace / faded late" marker — endurance blocks only, optional.
    var fadeMarker: FadeMarker?

    /// Rest between reps, seconds — parsed from the plan's rest note when the
    /// session is generated; drives the player's rest timer. Inline default for migration.
    var restSeconds: Double? = nil

    var session: TrainingSession?

    init(
        name: String,
        order: Int,
        plannedSets: Int,
        distanceMeters: Double? = nil,
        targetSeconds: Double? = nil,
        qualityRaw: String? = nil,
        movementID: String? = nil,
        completedSets: Int = 0,
        bestTimeSeconds: Double? = nil,
        wasPR: Bool = false,
        fadeMarker: FadeMarker? = nil,
        restSeconds: Double? = nil
    ) {
        self.name = name
        self.order = order
        self.plannedSets = plannedSets
        self.distanceMeters = distanceMeters
        self.targetSeconds = targetSeconds
        self.qualityRaw = qualityRaw
        self.movementID = movementID
        self.completedSets = completedSets
        self.bestTimeSeconds = bestTimeSeconds
        self.wasPR = wasPR
        self.fadeMarker = fadeMarker
        self.restSeconds = restSeconds
    }
}
