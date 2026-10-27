import Foundation

/// Root of the bundled, hand-authored plans file: metadata + event templates.
/// Static vetted data — never generated. Decoded from `plans.json` at launch.
public struct PlanLibrary: Codable, Sendable {
    public let meta: PlanMeta
    public let templates: [PlanTemplate]

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"   // the JSON key is "_meta"
        case templates
    }
}

/// `_meta` — carries the disclaimers/coach-review status we surface in-app.
public struct PlanMeta: Codable, Sendable {
    // Behaviour-bearing: these two gate the in-app draft notice.
    public let status: String
    public let requiresCoachSignoffBeforeShipping: Bool
    // Descriptive provenance only — nothing in the app renders these, so they are
    // optional: editing or renaming a documentation key must never stop the plans
    // from decoding (that once took the whole Plan/Today surface down).
    public let audience: String?
    public let notMedicalOrCoachingAdvice: String?
    public let methodologyBasis: String?
    public let coachReviewChecklist: [String]?
    public let intensityKey: [String: String]?
    public let scalingNote: String?

    /// True while the plans are a coach-review draft (gates the in-app notice).
    public var isDraft: Bool { status.contains("DRAFT") || requiresCoachSignoffBeforeShipping }

    enum CodingKeys: String, CodingKey {
        case status
        case requiresCoachSignoffBeforeShipping = "requires_coach_signoff_before_shipping"
        case audience
        case notMedicalOrCoachingAdvice = "not_medical_or_coaching_advice"
        case methodologyBasis = "methodology_basis"
        case coachReviewChecklist = "coach_review_checklist"
        case intensityKey = "intensity_key"
        case scalingNote = "scaling_note"
    }
}

public struct PlanTemplate: Codable, Sendable, Identifiable {
    public let id: String
    public let event: String              // matches Event.rawValue ("100m"/"200m"/"400m")
    public let durationWeeks: Int
    public let primaryQualities: [String]
    public let secondaryQualities: [String]
    public let summary: String
    public let phases: [PlanPhase]

    enum CodingKeys: String, CodingKey {
        case id, event, summary, phases
        case durationWeeks = "duration_weeks"
        case primaryQualities = "primary_qualities"
        case secondaryQualities = "secondary_qualities"
    }
}

public struct PlanPhase: Codable, Sendable {
    public let name: String
    public let weeks: String              // "1-3" — parsed to a range by PlanScheduler
    public let rationale: String
    public let progression: String
    public let weeklyMicrocycle: [PlanDay]

    enum CodingKeys: String, CodingKey {
        case name, weeks, rationale, progression
        case weeklyMicrocycle = "weekly_microcycle"
    }
}

public struct PlanDay: Codable, Sendable {
    public let day: Int                   // 1...7
    public let load: LoadLevel
    public let name: String
    public let blocks: [PlanBlock]
}

public enum LoadLevel: String, Codable, Sendable {
    case high, low, rest
}

/// One block. Track-work blocks carry type/sets/reps/distance; descriptive
/// blocks (warm-up, mobility, rest) carry only name + detail. All training
/// fields are optional so both shapes decode from the same type.
public struct PlanBlock: Codable, Sendable {
    public let name: String
    public let type: IntensityType?
    public let sets: Int?
    public let reps: Int?
    public let distanceM: Int?
    public let rest: String?
    public let target: String?
    public let detail: String?

    enum CodingKeys: String, CodingKey {
        case name, type, sets, reps, rest, target, detail
        case distanceM = "distance_m"
    }
}

/// The intensity vocabulary from `_meta.intensity_key`. Decodes leniently — an
/// unrecognized future value becomes `.other` rather than failing the whole load.
public enum IntensityType: String, Codable, Sendable {
    case accel
    case maxVelocity = "max_velocity"
    case speedEndurance = "speed_endurance"
    case specialEndurance1 = "special_endurance_1"
    case specialEndurance2 = "special_endurance_2"
    case extensiveTempo = "extensive_tempo"
    case generalStrength = "general_strength"
    case other

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IntensityType(rawValue: raw) ?? .other
    }

    /// The adjustable `Quality` this intensity maps to (nil for tempo/strength).
    public var quality: Quality? {
        switch self {
        case .accel: return .acceleration
        case .maxVelocity: return .maxVelocity
        case .speedEndurance: return .speedEndurance
        case .specialEndurance1: return .specialEndurance1
        case .specialEndurance2: return .specialEndurance2
        case .extensiveTempo, .generalStrength, .other: return nil
        }
    }

    /// Human-readable label for the intensity category (from the `type` field).
    public var displayLabel: String {
        switch self {
        case .accel: return "Acceleration"
        case .maxVelocity: return "Max velocity"
        case .speedEndurance: return "Speed endurance"
        case .specialEndurance1: return "Special endurance I"
        case .specialEndurance2: return "Special endurance II"
        case .extensiveTempo: return "Extensive tempo"
        case .generalStrength: return "General strength"
        case .other: return "—"
        }
    }
}
