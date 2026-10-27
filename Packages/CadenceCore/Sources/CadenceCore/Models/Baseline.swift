import Foundation

/// A rolling statistical baseline for a single physiological signal
/// (HRV, sleep, or resting heart rate), computed over a trailing window.
///
/// `sampleCount` is carried per-signal so cold-start can be decided
/// independently for each metric — HRV history and sleep history grow
/// at different rates.
public struct Baseline: Equatable, Sendable {
    public let mean: Double
    public let standardDeviation: Double
    public let sampleCount: Int

    public init(mean: Double, standardDeviation: Double, sampleCount: Int) {
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.sampleCount = sampleCount
    }

    /// z-score of a value against this baseline.
    /// Returns 0 (neutral) when the baseline has no spread, to avoid
    /// dividing by zero and to lean conservative rather than extreme.
    public func zScore(for value: Double) -> Double {
        guard standardDeviation > 0 else { return 0 }
        return (value - mean) / standardDeviation
    }
}
