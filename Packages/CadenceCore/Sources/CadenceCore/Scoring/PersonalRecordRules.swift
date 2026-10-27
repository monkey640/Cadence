/// Pure rule for personal-record detection. For sprint efforts, lower time is
/// better, so a new time is a PR when there is no prior best or it beats it.
/// Kept separate and Foundation-free so the rule is unit-tested in isolation.
public enum PersonalRecordRules {
    public static func isImprovement(new: Double, over previous: Double?) -> Bool {
        guard let previous else { return true }
        return new < previous
    }
}
