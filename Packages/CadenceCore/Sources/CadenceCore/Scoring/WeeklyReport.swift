/// A once-weekly recovery summary built purely from data the app already stores
/// (daily readiness scores + HRV snapshots + which sessions were scaled). Reads
/// like a coach's note, not a stats dump. All derivation, no new tracking.
public struct WeeklyReport: Equatable, Sendable {
    public enum Trend: String, Sendable { case up, down, flat }

    public let scaledSessions: Int
    public let avgReductionPct: Int
    public let readinessTrend: Trend
    public let hrvBaselineTrend: Trend
    public let takeaway: String

    public init(scaledSessions: Int, avgReductionPct: Int, readinessTrend: Trend,
                hrvBaselineTrend: Trend, takeaway: String) {
        self.scaledSessions = scaledSessions
        self.avgReductionPct = avgReductionPct
        self.readinessTrend = readinessTrend
        self.hrvBaselineTrend = hrvBaselineTrend
        self.takeaway = takeaway
    }
}

public enum WeeklyReportBuilder {

    /// - readinessThisWeek: daily readiness scores for the last 7 days, oldest→newest
    /// - scaledMultipliers: the volume multiplier of each *adjusted* session this week
    /// - hrvThisWeek / hrvPriorWeek: HRV (SDNN) snapshots for the two trailing weeks
    ///
    /// Returns nil when there isn't enough history to say anything honest.
    public static func build(
        readinessThisWeek: [Double],
        scaledMultipliers: [Double],
        hrvThisWeek: [Double],
        hrvPriorWeek: [Double]
    ) -> WeeklyReport? {
        guard readinessThisWeek.count >= 2 else { return nil }

        let readinessTrend = trend(readinessThisWeek, flatBand: 3)
        let hrvTrend = hrvBaselineTrend(thisWeek: hrvThisWeek, priorWeek: hrvPriorWeek)
        let scaled = scaledMultipliers.count
        let avgReduction = scaledMultipliers.isEmpty
            ? 0
            : Int((scaledMultipliers.reduce(0) { $0 + (1 - $1) } / Double(scaled) * 100).rounded())

        return WeeklyReport(
            scaledSessions: scaled,
            avgReductionPct: avgReduction,
            readinessTrend: readinessTrend,
            hrvBaselineTrend: hrvTrend,
            takeaway: takeaway(scaled: scaled, readiness: readinessTrend, hrv: hrvTrend))
    }

    // MARK: - Trend helpers

    private static func mean(_ v: ArraySlice<Double>) -> Double {
        v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
    }

    /// Compare the first half of the window to the second half.
    private static func trend(_ values: [Double], flatBand: Double) -> WeeklyReport.Trend {
        guard values.count >= 2 else { return .flat }
        let half = values.count / 2
        let first = mean(values[0..<half])
        let second = mean(values[(values.count - half)...])
        let diff = second - first
        if abs(diff) < flatBand { return .flat }
        return diff > 0 ? .up : .down
    }

    private static func hrvBaselineTrend(thisWeek: [Double], priorWeek: [Double]) -> WeeklyReport.Trend {
        guard !thisWeek.isEmpty, !priorWeek.isEmpty else { return .flat }
        let now = mean(thisWeek[...]), before = mean(priorWeek[...])
        let band = Swift.max(2.0, before * 0.03)   // 3% or 2ms, whichever larger
        let diff = now - before
        if abs(diff) < band { return .flat }
        return diff > 0 ? .up : .down
    }

    // MARK: - Coach takeaway (rule-based, never fabricated)

    private static func takeaway(scaled: Int, readiness: WeeklyReport.Trend, hrv: WeeklyReport.Trend) -> String {
        let s = scaled == 1 ? "session" : "sessions"
        switch (scaled > 0, readiness) {
        case (true, .up):
            return "You eased off \(scaled) \(s) this week and readiness still climbed — that's the recovery paying off, not lost training."
        case (true, .flat):
            return "A few smart pullbacks (\(scaled) \(s)) kept readiness steady through the week. The system's holding the line for you."
        case (true, .down):
            return "Readiness slipped this week even with \(scaled) \(s) eased back — leaning further into recovery now protects the weeks ahead."
        case (false, .up):
            return "Strong, consistent week — no pullbacks needed and readiness trending up. Keep the rhythm."
        case (false, .flat):
            return "Steady week — you ran the plan as written and readiness stayed level. A solid base to build on."
        case (false, .down):
            return "No adjustments fired, but readiness drifted down — worth watching sleep and load over the next few days."
        }
    }
}
