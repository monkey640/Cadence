/// Pure check-in streak math over integer day-indices (the app converts dates
/// to day numbers via Calendar). Foundation-free so it's unit-tested directly.
///
/// Design notes tied to the requirements:
///  - **Rest days count**: the day set is every day with a *completed* check-in,
///    regardless of whether the athlete trained — so rest days on which the
///    athlete still checked in are ordinary members of the set.
///  - **Sync errors never wipe the streak**: this only ever reads the recorded
///    set; it cannot delete anything, and the streak stays "alive" through
///    yesterday even before today's check-in lands.
public enum StreakCalculator {

    /// Length of the consecutive run ending at `today` (if checked in) or, if
    /// today isn't recorded yet, at yesterday — so the streak doesn't read 0
    /// before the athlete checks in today.
    public static func currentStreak(checkInDays days: Set<Int>, today: Int) -> Int {
        var cursor: Int
        if days.contains(today) { cursor = today }
        else if days.contains(today - 1) { cursor = today - 1 }
        else { return 0 }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor -= 1
        }
        return streak
    }

    /// Longest consecutive run anywhere in the recorded history (personal best).
    public static func longestStreak(checkInDays days: Set<Int>) -> Int {
        var best = 0
        for day in days where !days.contains(day - 1) {   // only run starts
            var cursor = day, run = 0
            while days.contains(cursor) { run += 1; cursor += 1 }
            best = max(best, run)
        }
        return best
    }
}
