/// Codable model of `movement_glossary.json` — two-tier movement descriptions
/// (`short` shown by default, `full` revealed on tap). Pure data; describing how
/// to perform standard drills, never prescribing volume/load.
public struct MovementGlossary: Codable, Sendable {
    public let movements: [MovementEntry]

    public init(movements: [MovementEntry]) { self.movements = movements }

    public func entry(id: String) -> MovementEntry? {
        movements.first { $0.movementID == id }
    }
}

public struct MovementEntry: Codable, Sendable, Identifiable {
    public let movementID: String
    public let name: String
    public let develops: String   // the "why" / intent
    public let short: String      // default cue
    public let full: MovementFull // revealed on tap

    public var id: String { movementID }

    enum CodingKeys: String, CodingKey {
        case movementID = "movement_id"
        case name, develops, short, full
    }
    public init(movementID: String, name: String, develops: String, short: String, full: MovementFull) {
        self.movementID = movementID; self.name = name; self.develops = develops
        self.short = short; self.full = full
    }
}

public struct MovementFull: Codable, Sendable {
    public let howToDoIt: String
    public let whatGoodFeelsLike: String
    public let commonMistakes: [String]
    public let keyCue: String

    enum CodingKeys: String, CodingKey {
        case howToDoIt = "how_to_do_it"
        case whatGoodFeelsLike = "what_good_feels_like"
        case commonMistakes = "common_mistakes"
        case keyCue = "key_cue"
    }
    public init(howToDoIt: String, whatGoodFeelsLike: String, commonMistakes: [String], keyCue: String) {
        self.howToDoIt = howToDoIt; self.whatGoodFeelsLike = whatGoodFeelsLike
        self.commonMistakes = commonMistakes; self.keyCue = keyCue
    }
}

/// Maps a plan block to a glossary `movement_id`. Deterministic lookup (name +
/// intensity type) — not a guess. Returns nil when nothing matches, so the UI
/// falls back to the plan's own target/detail and omits the glossary expander.
public enum GlossaryResolver {
    public static func movementID(forType type: IntensityType?, name: String) -> String? {
        let n = name.lowercased()
        if n.contains("warm-up") || n.contains("warm up") || n.contains("drill") { return "warmup_drills" }
        if n.contains("block start") && (type == .accel || type == nil) { return "block_starts" }
        switch type {
        case .accel:             return "acceleration"
        case .maxVelocity:       return "max_velocity"
        case .speedEndurance:    return "speed_endurance"
        case .specialEndurance1: return "special_endurance_1"
        case .specialEndurance2: return "special_endurance_2"
        case .extensiveTempo:    return "extensive_tempo"
        case .generalStrength:   return "strength"
        case .other, .none:      return nil
        }
    }
}
