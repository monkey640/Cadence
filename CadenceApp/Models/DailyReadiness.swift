import Foundation
import SwiftData
import CadenceCore

/// One persisted readiness result per day. Stored because the *score* is
/// computed by us (HealthKit can't give it back), so the Trends "readiness
/// trend" needs its own history. Also snapshots the raw metrics so Trends can
/// chart HRV/sleep/RHR without re-querying HealthKit for 30 days each render.
@Model
final class DailyReadiness {
    /// Start of day; unique per day.
    @Attribute(.unique) var date: Date

    var score: Double
    var verdictRaw: String
    var volumeMultiplier: Double
    var reason: String
    var isBaselining: Bool
    /// How much to trust this day's call given which inputs were present.
    /// Defaulted for lightweight migration of rows written before phone-only support.
    var confidenceRaw: String = ReadinessConfidence.moderate.rawValue

    /// When this row was last (re)computed. Today's readiness is a *living* value:
    /// late-syncing wearable data recomputes it in place until midnight, at which
    /// point the day is final. Drives the "recompute if stale" check. Optional with
    /// a nil default (SwiftData forbids `.now` defaults); nil = treat as stale.
    var updatedAt: Date? = nil

    /// The verdict/multiplier the athlete actually trained under, frozen the moment
    /// a session starts. A later recompute (new Apple Health data) may move the
    /// score and breakdown for accuracy, but never retroactively rescales a session
    /// already underway. nil until a session starts today. Inline defaults migrate.
    var verdictAtSessionStart: String? = nil
    var multiplierAtSessionStart: Double? = nil

    // Component sub-scores (nil when that signal was unavailable).
    var hrvScore: Double?
    var sleepScore: Double?
    var rhrScore: Double?
    var loadScore: Double?
    // Optional overnight sub-scores (inline defaults for lightweight migration).
    var sleepQualityScore: Double? = nil
    var respiratoryScore: Double? = nil
    var wristTempScore: Double? = nil
    // Phone-only component sub-scores.
    var wellnessScore: Double?
    var fingerTapScore: Double?
    var jumpScore: Double?

    // Raw metric snapshots for charting.
    var hrvSDNN: Double?
    var sleepSeconds: Double?
    var restingHR: Double?

    init(date: Date, output: ReadinessOutput, hrvSDNN: Double?, sleepSeconds: Double?,
         restingHR: Double?, at updatedAt: Date = .now) {
        self.date = Calendar.current.startOfDay(for: date)
        self.updatedAt = updatedAt
        self.score = output.score
        self.verdictRaw = output.verdict.rawValue
        self.volumeMultiplier = output.volumeMultiplier
        self.reason = output.reason
        self.isBaselining = output.isBaselining
        self.confidenceRaw = output.confidence.rawValue
        self.hrvScore = output.components.hrv
        self.sleepScore = output.components.sleep
        self.rhrScore = output.components.rhr
        self.loadScore = output.components.trainingLoad
        self.sleepQualityScore = output.components.sleepQuality
        self.respiratoryScore = output.components.respiratoryRate
        self.wristTempScore = output.components.wristTemperature
        self.wellnessScore = output.components.wellness
        self.fingerTapScore = output.components.fingerTap
        self.jumpScore = output.components.countermovementJump
        self.hrvSDNN = hrvSDNN
        self.sleepSeconds = sleepSeconds
        self.restingHR = restingHR
    }

    /// Recompute in place — update every score/metric field and the timestamp,
    /// preserving `date` (identity) and the session-start freeze. Used when late
    /// wearable data lands, so the row keeps its identity and observing views
    /// update smoothly instead of a delete/insert flash.
    func apply(_ output: ReadinessOutput, hrvSDNN: Double?, sleepSeconds: Double?,
               restingHR: Double?, at updatedAt: Date = .now) {
        self.updatedAt = updatedAt
        self.score = output.score
        self.verdictRaw = output.verdict.rawValue
        self.volumeMultiplier = output.volumeMultiplier
        self.reason = output.reason
        self.isBaselining = output.isBaselining
        self.confidenceRaw = output.confidence.rawValue
        self.hrvScore = output.components.hrv
        self.sleepScore = output.components.sleep
        self.rhrScore = output.components.rhr
        self.loadScore = output.components.trainingLoad
        self.sleepQualityScore = output.components.sleepQuality
        self.respiratoryScore = output.components.respiratoryRate
        self.wristTempScore = output.components.wristTemperature
        self.wellnessScore = output.components.wellness
        self.fingerTapScore = output.components.fingerTap
        self.jumpScore = output.components.countermovementJump
        self.hrvSDNN = hrvSDNN
        self.sleepSeconds = sleepSeconds
        self.restingHR = restingHR
    }

    var verdict: Verdict { Verdict(rawValue: verdictRaw) ?? .hold }
    var confidence: ReadinessConfidence { ReadinessConfidence(rawValue: confidenceRaw) ?? .moderate }

    /// The verdict the athlete trains under today: frozen at session start if a
    /// session has begun, else the latest computed verdict.
    var effectiveVerdict: Verdict {
        verdictAtSessionStart.flatMap(Verdict.init(rawValue:)) ?? verdict
    }
    /// The volume multiplier the athlete trains under today (frozen at session start).
    var effectiveMultiplier: Double {
        multiplierAtSessionStart ?? volumeMultiplier
    }

    /// Freeze the verdict/multiplier the athlete started training under, so a later
    /// recompute never retroactively rescales a session already underway. Pass the
    /// session's own values (what actually generated the work). No-op if already
    /// frozen today. Returns true if it froze (caller should save).
    @discardableResult
    func freezeForSessionStart(verdict: Verdict, multiplier: Double) -> Bool {
        guard verdictAtSessionStart == nil else { return false }
        verdictAtSessionStart = verdict.rawValue
        multiplierAtSessionStart = multiplier
        return true
    }
}
