import Foundation
import SwiftData
import CadenceCore

/// The athlete's event, used to pick training templates. Sprint-focused for MVP.
public enum Event: String, Codable, CaseIterable, Sendable {
    case sprint100 = "100m"
    case sprint200 = "200m"
    case sprint400 = "400m"
    case hurdles    = "Hurdles"
    case relay      = "Relay"
}

/// Training age, captured at onboarding. Caps starting high-CNS days (reduce-only).
public enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
    case beginner, developing, experienced

    /// Max high-CNS days/week to start with — beginners get fewer (per coach checklist).
    var maxHighDays: Int { self == .beginner ? 2 : 3 }
    var label: String {
        switch self {
        case .beginner: return "New to sprint training"
        case .developing: return "A few seasons in"
        case .experienced: return "Experienced"
        }
    }
}

/// Self-reported priority, captured at onboarding. Sets a one-time bounded
/// starting emphasis; does NOT feed the deficiency engine.
public enum FocusArea: String, CaseIterable, Sendable {
    case acceleration, topSpeed, speedEndurance, raceEndurance

    var label: String {
        switch self {
        case .acceleration: return "My start / acceleration"
        case .topSpeed: return "My top speed"
        case .speedEndurance: return "Holding speed"
        case .raceEndurance: return "Finishing races strong"
        }
    }

    /// Maps to an adjustable quality for the event (nil if not adjustable there).
    func quality(in profile: EventAdjustmentProfile) -> Quality? {
        switch self {
        case .acceleration: return profile.adjustable(.acceleration) != nil ? .acceleration : nil
        case .topSpeed: return profile.adjustable(.maxVelocity) != nil ? .maxVelocity : nil
        case .speedEndurance: return profile.adjustable(.speedEndurance) != nil ? .speedEndurance : nil
        case .raceEndurance:
            if profile.adjustable(.specialEndurance2) != nil { return .specialEndurance2 }
            if profile.adjustable(.specialEndurance1) != nil { return .specialEndurance1 }
            return profile.adjustable(.speedEndurance) != nil ? .speedEndurance : nil
        }
    }
}

/// Single-row profile captured during onboarding (<2 min).
/// There is exactly one of these; the app fetches `.first`.
@Model
final class AthleteProfile {
    /// First name for the Today header and PR card. Inline default for migration.
    var firstName: String = ""
    /// Next competition date (stored for v1.5 taper logic; no taper in v1).
    var meetDate: Date?
    /// Which weekdays the athlete trains, as a bitmask (bit 0 = Monday … bit 6 =
    /// Sunday). 0 = not captured; `weeklyTrainingDays` remains the source of
    /// truth for plan fitting. Inline default for migration.
    var trainingWeekdayMask: Int = 0

    var event: Event
    /// Goal time for the event, in seconds (e.g. 11.2s → 11.2). Optional: some athletes don't have one yet.
    var goalTimeSeconds: Double?
    /// Self-reported training days per week, captured at onboarding.
    var weeklyTrainingDays: Int
    /// Training age — caps starting high-CNS days. Inline default for migration.
    var experienceRaw: String = ExperienceLevel.developing.rawValue
    var createdAt: Date

    var experienceLevel: ExperienceLevel { ExperienceLevel(rawValue: experienceRaw) ?? .developing }
    /// Day the 12-week plan started (set when onboarding completes). Drives which
    /// plan week/day the Today screen shows. Optional for lightweight migration.
    var planStartDate: Date?
    var hasCompletedOnboarding: Bool
    /// Set once the athlete has acknowledged the not-medical-advice disclaimer.
    var hasAcknowledgedDisclaimer: Bool

    /// Weekday indices (0 = Monday … 6 = Sunday) unpacked from the mask.
    var trainingWeekdays: Set<Int> {
        get { Set((0..<7).filter { trainingWeekdayMask & (1 << $0) != 0 }) }
        set { trainingWeekdayMask = newValue.reduce(0) { $0 | (1 << $1) } }
    }

    init(
        firstName: String = "",
        meetDate: Date? = nil,
        event: Event = .sprint100,
        goalTimeSeconds: Double? = nil,
        weeklyTrainingDays: Int = 4,
        experienceLevel: ExperienceLevel = .developing,
        createdAt: Date = .now,
        planStartDate: Date? = nil,
        hasCompletedOnboarding: Bool = false,
        hasAcknowledgedDisclaimer: Bool = false
    ) {
        self.firstName = firstName
        self.meetDate = meetDate
        self.event = event
        self.goalTimeSeconds = goalTimeSeconds
        self.weeklyTrainingDays = weeklyTrainingDays
        self.experienceRaw = experienceLevel.rawValue
        self.createdAt = createdAt
        self.planStartDate = planStartDate
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hasAcknowledgedDisclaimer = hasAcknowledgedDisclaimer
    }
}
