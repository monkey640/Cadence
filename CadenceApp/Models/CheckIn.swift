import Foundation
import SwiftData
import CadenceCore

/// One row per calendar day, unique on `day`. Append-only — nothing ever deletes
/// a check-in, so a sync/HealthKit error can never wipe the streak. A row counts
/// toward the streak only once `completedAt` is set (see StreakService).
///
/// This is also where the **phone-only readiness inputs** live: the daily
/// subjective wellness check-in and the optional finger-tap / jump tests. All are
/// optional — the engine degrades gracefully on whatever is present — but the
/// morning check-in flow must be completed (`completedAt`) for the day to count.
@Model
final class CheckIn {
    @Attribute(.unique) var day: Date

    // Subjective wellness, 1...5 in the engine's higher-is-better convention
    // (5 = well-rested / no soreness / fresh / calm / good mood). nil until answered.
    var wellnessSleep: Int?
    var wellnessSoreness: Int?
    var wellnessFatigue: Int?
    var wellnessStress: Int?
    var wellnessMood: Int?

    // Phone-only performance tests for the day (nil until taken).
    var fingerTapCount: Double?
    var jumpHeightCm: Double?

    /// When the morning check-in *flow* was completed. nil = the row holds only
    /// phone-only inputs or is otherwise incomplete: Today keeps showing the
    /// "Check in now" gate and the streak does not count this day. Inline default
    /// for migration.
    var completedAt: Date? = nil

    init(day: Date,
         wellnessSleep: Int? = nil, wellnessSoreness: Int? = nil, wellnessFatigue: Int? = nil,
         wellnessStress: Int? = nil, wellnessMood: Int? = nil,
         fingerTapCount: Double? = nil, jumpHeightCm: Double? = nil) {
        self.day = day
        self.wellnessSleep = wellnessSleep
        self.wellnessSoreness = wellnessSoreness
        self.wellnessFatigue = wellnessFatigue
        self.wellnessStress = wellnessStress
        self.wellnessMood = wellnessMood
        self.fingerTapCount = fingerTapCount
        self.jumpHeightCm = jumpHeightCm
    }

    /// The value-type check-in the engine consumes — present only once all five
    /// items are answered (a partial check-in isn't scored).
    var wellnessCheckIn: WellnessCheckIn? {
        guard let sleep = wellnessSleep, let soreness = wellnessSoreness,
              let fatigue = wellnessFatigue, let stress = wellnessStress,
              let mood = wellnessMood else { return nil }
        return WellnessCheckIn(sleepRating: sleep, soreness: soreness,
                               fatigue: fatigue, stress: stress, mood: mood)
    }
}
