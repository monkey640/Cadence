/// Computes total covered sleep time from intervals that may overlap or be
/// exact duplicates — the realistic HealthKit failure mode when iPhone, Apple
/// Watch, and a third-party app all write the same night.
///
/// Naively summing each sample's duration double-counts overlaps. This merges
/// overlapping/duplicate `[start, end]` intervals so no second is counted twice.
/// Intervals are epoch seconds (Double) to keep this pure and unit-testable.
public enum SleepIntervalMerger {

    public static func totalDuration(of intervals: [(start: Double, end: Double)]) -> Double {
        let valid = intervals
            .filter { $0.end > $0.start }          // drop zero/negative-length junk
            .sorted { $0.start < $1.start }
        guard let first = valid.first else { return 0 }

        var total = 0.0
        var segmentStart = first.start
        var segmentEnd = first.end

        for interval in valid.dropFirst() {
            if interval.start <= segmentEnd {
                // Overlap or exact duplicate → extend the current segment.
                segmentEnd = Swift.max(segmentEnd, interval.end)
            } else {
                // Gap → close the current segment and start a new one.
                total += segmentEnd - segmentStart
                segmentStart = interval.start
                segmentEnd = interval.end
            }
        }
        total += segmentEnd - segmentStart
        return total
    }
}
