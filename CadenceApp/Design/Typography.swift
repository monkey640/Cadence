import SwiftUI

/// The app's typographic signature: stadium-timing-board numerals.
/// Every number that updates live gets monospaced digits so nothing jitters.
extension Font {
    /// Timing-board numeral — ultra-bold with monospaced digits.
    /// Use for the readiness score, timers, rep counts, and PRs.
    static func timingBoard(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// Headline / verdict face: SF Pro, black weight. Pair with `.tracking(-0.5)`
    /// (tight) for headlines; verdicts additionally go uppercase at the call site.
    static func displayBlack(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black)
    }
}

extension View {
    /// Small all-caps monospaced section label ("READINESS", "WHAT SHAPED IT")
    /// — the broadcast/timing-board whisper that pairs with the shout-numbers.
    func sectionLabel() -> some View {
        self.font(.system(.caption2, design: .monospaced).weight(.semibold))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }
}
