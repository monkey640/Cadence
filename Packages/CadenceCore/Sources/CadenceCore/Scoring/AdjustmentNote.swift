/// Coach-voice copy for the "Adjusted today" callout, built from the engine's
/// existing output — it names the real signal that drove the pullback (the
/// lowest available component) and frames the trade-off. No fabricated causes.
public enum AdjustmentNote {

    /// One-to-two sentence note for a scaled-down session, or nil if not adjusted.
    public static func text(for output: ReadinessOutput) -> String? {
        guard output.volumeMultiplier < 1.0 else { return nil }
        let pct = Int(((1.0 - output.volumeMultiplier) * 100).rounded())

        switch lowestDriver(output.components) {
        case .hrv:
            return "Dialed back \(pct)% — your HRV is down from your baseline. Pushing hard today would cost more than it pays back."
        case .sleep:
            return "Dialed back \(pct)% — short sleep is blunting your recovery. Easing off protects the quality of your next hard day."
        case .rhr:
            return "Dialed back \(pct)% — your resting heart rate is up, a sign you're not fully recovered. Lighter today is the smart trade."
        case .none:
            return "Dialed back \(pct)% to match today's readiness. Banking this recovery sets up your next real push."
        }
    }

    private enum Driver { case hrv, sleep, rhr, none }

    /// The available physiological component with the lowest sub-score — the
    /// biggest drag on readiness, i.e. what actually drove the pullback.
    private static func lowestDriver(_ c: ComponentScores) -> Driver {
        let candidates: [(Driver, Double?)] = [(.hrv, c.hrv), (.sleep, c.sleep), (.rhr, c.rhr)]
        let present = candidates.compactMap { d, s in s.map { (d, $0) } }
        guard let worst = present.min(by: { $0.1 < $1.1 }), worst.1 < 50 else { return .none }
        return worst.0
    }
}
