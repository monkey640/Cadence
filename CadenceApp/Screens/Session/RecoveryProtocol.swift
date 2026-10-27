import Foundation

/// The Back Off day's content. A Back Off verdict never lands on an empty
/// screen — it swaps the session for these active-recovery items, logged as a
/// real "Recovery session" so history stays complete and the streak holds.
enum RecoveryProtocol {
    struct Item {
        let name: String
        let detail: String
    }

    static let items: [Item] = [
        Item(name: "10 min easy walk",
             detail: "Conversational pace, outside if you can. Blood flow without load."),
        Item(name: "Hip flexor stretch series",
             detail: "Half-kneeling hip flexor stretch, 45s each side, two rounds. Squeeze the glute of the down leg."),
        Item(name: "Quad + hamstring foam roll",
             detail: "90 seconds per leg, slow passes. Pause on tender spots, keep breathing."),
        Item(name: "Contrast shower",
             detail: "30s warm, 30s cool, three rounds. Finish cool."),
        Item(name: "8+ hrs sleep target tonight",
             detail: "The actual recovery session. Screens away 30 minutes before bed."),
    ]

    static let sessionTitle = "Recovery protocol"
}

/// Parses the plan's human rest notes ("3 min", "90 s", "2-3 min", "full
/// recovery walk back") into seconds for the rest timer. Returns nil when the
/// note doesn't carry a usable duration — the player then falls back to its
/// default rest.
///
/// Compound notes like "30s / 2-3 min" or "30s between reps / 2-3 min between
/// sets" describe two different rests. The player logs one rep at a time, so
/// the timer wants the first one — the rest between reps. Parsing the whole
/// string at once used to average 30, 2 and 3 into "11.7 minutes", handing a
/// tempo athlete twelve minutes of rest between 100s.
enum RestParser {
    static func seconds(from note: String?) -> Double? {
        guard let note = note?.lowercased(), !note.isEmpty else { return nil }
        let between = note.components(separatedBy: "/").first ?? note
        return segmentSeconds(between.trimmingCharacters(in: .whitespaces))
    }

    /// One duration with its own unit: "45s", "3 min", "2-3 min full".
    private static func segmentSeconds(_ segment: String) -> Double? {
        // Pull all numbers; a range like "2-3 min" averages to its midpoint.
        let numbers = segment
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap(Double.init)
        guard !numbers.isEmpty else { return nil }
        let value = numbers.reduce(0, +) / Double(numbers.count)

        if segment.contains("min") { return value * 60 }
        if segment.contains("sec") || segment.contains("s ") || segment.hasSuffix("s")
            || segment.range(of: #"\d\s*s\b"#, options: .regularExpression) != nil {
            return value
        }
        // Bare number: plans write rest in minutes.
        return value * 60
    }
}
