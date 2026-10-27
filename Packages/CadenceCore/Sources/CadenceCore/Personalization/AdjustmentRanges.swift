/// Codable model of `cadence_adjustment_ranges.json` — the BOUNDED envelope and
/// detection rules for plan personalization. Pure data: every band/threshold is
/// a field here so the (not-yet-final) numbers are trivial to change.
///
/// Unknown JSON keys are ignored by Codable, so the verbose `_meta` prose decodes
/// down to just what the engine needs.
public struct AdjustmentRanges: Codable, Sendable {
    public let meta: RangesMeta
    public let globalRules: GlobalAdjustmentRules
    public let profiles: [EventAdjustmentProfile]

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
        case globalRules = "global_adjustment_rules"
        case profiles = "event_adjustment_profiles"
    }

    public init(meta: RangesMeta, globalRules: GlobalAdjustmentRules, profiles: [EventAdjustmentProfile]) {
        self.meta = meta
        self.globalRules = globalRules
        self.profiles = profiles
    }

    /// The profile for an event, or nil → personalization disabled (no fabrication).
    public func profile(for event: String) -> EventAdjustmentProfile? {
        profiles.first { $0.event == event }
    }
}

public struct RangesMeta: Codable, Sendable {
    public let status: String
    public let requiresCoachSignoff: Bool
    public var isDraft: Bool { status.contains("DRAFT") || requiresCoachSignoff }

    enum CodingKeys: String, CodingKey {
        case status
        case requiresCoachSignoff = "requires_coach_signoff_before_shipping"
    }
    public init(status: String, requiresCoachSignoff: Bool) {
        self.status = status
        self.requiresCoachSignoff = requiresCoachSignoff
    }
}

public struct GlobalAdjustmentRules: Codable, Sendable {
    public let weeklyHighCNSSessionCap: Int
    public let maxVelocityWeeklyFloorSessions: Int
    public let reduce: EvidenceRuleJSON
    public let add: EvidenceRuleJSON

    enum CodingKeys: String, CodingKey {
        case weeklyHighCNSSessionCap = "weekly_high_cns_session_cap"
        case maxVelocityWeeklyFloorSessions = "max_velocity_weekly_floor_sessions"
        case reduce = "evidence_to_REDUCE"
        case add = "evidence_to_ADD"
    }
    public init(weeklyHighCNSSessionCap: Int, maxVelocityWeeklyFloorSessions: Int,
                reduce: EvidenceRuleJSON, add: EvidenceRuleJSON) {
        self.weeklyHighCNSSessionCap = weeklyHighCNSSessionCap
        self.maxVelocityWeeklyFloorSessions = maxVelocityWeeklyFloorSessions
        self.reduce = reduce
        self.add = add
    }
}

/// The raw evidence numbers from JSON. Pattern-consistency is expressed as prose
/// in the file ("3 of the last 4"), so the numeric k/n live in `EvidenceConfig`.
public struct EvidenceRuleJSON: Codable, Sendable {
    public let minSessionsObserved: Int
    public let maxChangePerWeekReps: Int?

    enum CodingKeys: String, CodingKey {
        case minSessionsObserved = "min_sessions_observed"
        case maxChangePerWeekReps = "max_change_per_week_reps"
    }
    public init(minSessionsObserved: Int, maxChangePerWeekReps: Int?) {
        self.minSessionsObserved = minSessionsObserved
        self.maxChangePerWeekReps = maxChangePerWeekReps
    }
}

public struct EventAdjustmentProfile: Codable, Sendable {
    public let event: String
    public let weeklyHighCNSBudget: Int
    public let qualities: [AdjustableQuality]
    public let deficiencies: [Deficiency]

    enum CodingKeys: String, CodingKey {
        case event
        case weeklyHighCNSBudget = "weekly_high_cns_budget_sessions"
        case qualities = "adjustable_qualities"
        case deficiencies
    }
    public init(event: String, weeklyHighCNSBudget: Int, qualities: [AdjustableQuality], deficiencies: [Deficiency]) {
        self.event = event
        self.weeklyHighCNSBudget = weeklyHighCNSBudget
        self.qualities = qualities
        self.deficiencies = deficiencies
    }

    public func adjustable(_ quality: Quality) -> AdjustableQuality? {
        qualities.first { $0.quality == quality }
    }
}

public struct AdjustableQuality: Codable, Sendable {
    public let qualityRaw: String
    public let defaultWeeklyReps: Int
    public let minWeeklyReps: Int
    public let maxWeeklyReps: Int
    public let distanceBand: [Int]
    public let phases: [String]
    public let isSpeedFloorRaw: Bool?

    public var quality: Quality? { Quality(rangesRaw: qualityRaw) }
    public var isSpeedFloor: Bool { isSpeedFloorRaw ?? false }

    enum CodingKeys: String, CodingKey {
        case qualityRaw = "quality"
        case defaultWeeklyReps = "default_weekly_reps"
        case minWeeklyReps = "min_weekly_reps"
        case maxWeeklyReps = "max_weekly_reps"
        case distanceBand = "distance_band_m"
        case phases
        case isSpeedFloorRaw = "is_speed_floor_quality"
    }
    public init(qualityRaw: String, defaultWeeklyReps: Int, minWeeklyReps: Int, maxWeeklyReps: Int,
                distanceBand: [Int], phases: [String], isSpeedFloorRaw: Bool?) {
        self.qualityRaw = qualityRaw
        self.defaultWeeklyReps = defaultWeeklyReps
        self.minWeeklyReps = minWeeklyReps
        self.maxWeeklyReps = maxWeeklyReps
        self.distanceBand = distanceBand
        self.phases = phases
        self.isSpeedFloorRaw = isSpeedFloorRaw
    }
}

public struct Deficiency: Codable, Sendable {
    public let name: String
    public let plainLanguage: String
    public let response: BoundedResponse

    enum CodingKeys: String, CodingKey {
        case name
        case plainLanguage = "plain_language"
        case response = "bounded_response"
    }
    public init(name: String, plainLanguage: String, response: BoundedResponse) {
        self.name = name
        self.plainLanguage = plainLanguage
        self.response = response
    }
}

public struct BoundedResponse: Codable, Sendable {
    public let increase: IncreaseSpec?
    public let offset: OffsetSpec?
    public let reduce: ReduceSpec?
    public let evidenceRaw: String

    /// "ADD rules" → full add gating; "REDUCE rules" → low-evidence protective reduce.
    public var usesAddRules: Bool { evidenceRaw.uppercased().contains("ADD") }

    enum CodingKeys: String, CodingKey {
        case increase, offset, reduce
        case evidenceRaw = "evidence"
    }
    public init(increase: IncreaseSpec?, offset: OffsetSpec?, reduce: ReduceSpec?, evidenceRaw: String) {
        self.increase = increase
        self.offset = offset
        self.reduce = reduce
        self.evidenceRaw = evidenceRaw
    }
}

public struct IncreaseSpec: Codable, Sendable {
    public let qualityRaw: String
    public let byReps: Int
    public let upToMax: Int
    public var quality: Quality? { Quality(rangesRaw: qualityRaw) }
    enum CodingKeys: String, CodingKey { case qualityRaw = "quality"; case byReps = "by_reps"; case upToMax = "up_to_max" }
    public init(qualityRaw: String, byReps: Int, upToMax: Int) {
        self.qualityRaw = qualityRaw; self.byReps = byReps; self.upToMax = upToMax
    }
}

public struct OffsetSpec: Codable, Sendable {
    public let reduceQualityRaw: String
    public let byReps: Int
    public let notBelowMin: Bool
    public var quality: Quality? { Quality(rangesRaw: reduceQualityRaw) }
    enum CodingKeys: String, CodingKey { case reduceQualityRaw = "reduce_quality"; case byReps = "by_reps"; case notBelowMin = "not_below_min" }
    public init(reduceQualityRaw: String, byReps: Int, notBelowMin: Bool) {
        self.reduceQualityRaw = reduceQualityRaw; self.byReps = byReps; self.notBelowMin = notBelowMin
    }
}

public struct ReduceSpec: Codable, Sendable {
    public let qualityRaw: String   // may be "any_high_cns" / "special_endurance_2_first"
    public let by: String
    enum CodingKeys: String, CodingKey { case qualityRaw = "quality"; case by }
    public init(qualityRaw: String, by: String) { self.qualityRaw = qualityRaw; self.by = by }
}

/// Adjustable quality, mapped across the two JSON files (ranges use
/// "acceleration"; templates use the block `type` "accel").
public enum Quality: String, Codable, Sendable, CaseIterable {
    case acceleration, maxVelocity, speedEndurance, specialEndurance1, specialEndurance2

    public init?(rangesRaw: String) {
        switch rangesRaw {
        case "acceleration": self = .acceleration
        case "max_velocity": self = .maxVelocity
        case "speed_endurance": self = .speedEndurance
        case "special_endurance_1": self = .specialEndurance1
        case "special_endurance_2": self = .specialEndurance2
        default: return nil
        }
    }

    /// Human-readable, athlete-facing name (lower-case, for mid-sentence use).
    public var displayName: String {
        switch self {
        case .acceleration: return "acceleration"
        case .maxVelocity: return "top-speed work"
        case .speedEndurance: return "speed-endurance"
        case .specialEndurance1: return "special-endurance"
        case .specialEndurance2: return "longer special-endurance"
        }
    }

    /// Endurance qualities — the only ones the "faded late?" marker is meaningful
    /// for (and where fade feeds speed-endurance / special-endurance detection).
    public var isEndurance: Bool {
        switch self {
        case .speedEndurance, .specialEndurance1, .specialEndurance2: return true
        case .acceleration, .maxVelocity: return false
        }
    }
}
