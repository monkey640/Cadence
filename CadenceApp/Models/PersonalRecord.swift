import Foundation
import SwiftData

/// A best-ever result for a given effort, keyed by a normalized label
/// (e.g. "60m", "120m"). Stored separately so PR detection on session save
/// is an O(1) lookup-and-compare instead of scanning all history.
@Model
final class PersonalRecord {
    @Attribute(.unique) var key: String
    /// Best time in seconds (lower is better). For sprint efforts, time is the PR metric.
    var bestTimeSeconds: Double
    var achievedOn: Date

    init(key: String, bestTimeSeconds: Double, achievedOn: Date) {
        self.key = key
        self.bestTimeSeconds = bestTimeSeconds
        self.achievedOn = achievedOn
    }
}
