import Foundation

/// Computes rolling mean / standard deviation baselines from raw daily samples.
/// Pure and standalone so the statistics can be tested without HealthKit.
public enum BaselineCalculator {

    /// Build a `Baseline` from a window of daily values (e.g. the last 30 days).
    /// Uses the population standard deviation. Returns `nil` for an empty window.
    public static func baseline(from samples: [Double]) -> Baseline? {
        guard !samples.isEmpty else { return nil }
        let n = Double(samples.count)
        let mean = samples.reduce(0, +) / n
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return Baseline(mean: mean, standardDeviation: variance.squareRoot(), sampleCount: samples.count)
    }
}
