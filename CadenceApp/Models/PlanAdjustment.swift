import Foundation
import SwiftData

/// The currently-applied personalization for an event: the cumulative per-quality
/// rep deltas the user has approved. Deleting it reverts to the vetted plan
/// (undo / restart). One row per event; absence = no personalization.
@Model
final class PlanAdjustment {
    @Attribute(.unique) var event: String
    var deficiencyName: String
    /// The plain-language note shown when it was applied.
    var reason: String
    /// quality rawValue → cumulative rep delta (e.g. ["speedEndurance": 1, "acceleration": -1]).
    var deltas: [String: Int]
    var appliedAt: Date

    init(event: String, deficiencyName: String, reason: String, deltas: [String: Int], appliedAt: Date = .now) {
        self.event = event
        self.deficiencyName = deficiencyName
        self.reason = reason
        self.deltas = deltas
        self.appliedAt = appliedAt
    }
}
