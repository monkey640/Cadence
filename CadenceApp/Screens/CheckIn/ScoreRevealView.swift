import SwiftUI
import CadenceCore

/// The signature moment: a race-clock count-up 0 → today's volume in ~0.9s,
/// verdict color bleeding in as it settles, then the verdict badge stamping in
/// with one strong haptic. Reduce Motion gets an instant crossfade — the
/// information is never gated behind the animation.
///
/// The number is the same one Today leads with — the share of the plan to run —
/// so "See today's session" lands on the number the athlete just watched, not a
/// different one. Readiness sits underneath as context.
struct ScoreRevealView: View {
    let output: ReadinessOutput
    let completionSeconds: Int?
    let onSeeSession: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownScore: Double = 0
    @State private var settled = false      // color bleed + badge stamp
    @State private var badgeVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("TODAY'S VOLUME")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 4)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                CountingText(value: shownScore)
                    .font(.timingBoard(96))
                Text("%")
                    .font(.timingBoard(40))
            }
            .foregroundStyle(settled ? output.verdict.color : Theme.textPrimary)
            .animation(.easeIn(duration: 0.3), value: settled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today's volume \(Int(volumePercent)) percent of plan. Readiness \(Int(output.score.rounded())) out of 100")

            Text("of plan · readiness \(Int(output.score.rounded()))")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
                .accessibilityHidden(true)

            if badgeVisible {
                VerdictBadge(verdict: output.verdict, large: true)
                    .transition(reduceMotion
                        ? .opacity
                        : .scale(scale: 1.5).combined(with: .opacity))
                    .padding(.top, 12)
            } else {
                // Reserve the badge's slot so the layout doesn't jump on stamp.
                VerdictBadge(verdict: output.verdict, large: true)
                    .hidden()
                    .padding(.top, 12)
            }

            Text(output.reason)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
                .padding(.top, 24)

            ConfidenceBadge(confidence: output.confidence)
                .padding(.top, 12)

            if output.isBaselining {
                Label(baseliningText, systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 12)
            }

            Spacer()

            Button("See today's session", action: onSeeSession)
                .buttonStyle(PrimaryButtonStyle(tint: output.verdict.color))
                .padding(.horizontal, 24)
                .opacity(badgeVisible ? 1 : 0)

            if let seconds = completionSeconds, seconds <= 90 {
                Text("Check-in: \(seconds)s")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10)
            }

            Spacer().frame(height: 24)
        }
        .onAppear(perform: reveal)
    }

    /// Same figure Today shows: the day's volume multiplier as a percentage.
    private var volumePercent: Double { (output.volumeMultiplier * 100).rounded() }

    private var baseliningText: String {
        // The engine stops baselining at `minBaselineDays`; counting down from
        // a hardcoded 14 told a day-2 athlete "12 days" when it was 5.
        let remaining = max(0, ReadinessConfig.standard.minBaselineDays - output.baselineSampleCount)
        return remaining > 0
            ? "Building your baseline — \(remaining) day\(remaining == 1 ? "" : "s") remaining. Score is provisional."
            : "Building your baseline. Score is provisional."
    }

    private func reveal() {
        if reduceMotion {
            shownScore = volumePercent
            settled = true
            badgeVisible = true
            Haptics.stamp()
            return
        }
        withAnimation(.easeOut(duration: 0.9)) { shownScore = volumePercent }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            settled = true
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { badgeVisible = true }
            Haptics.stamp()
        }
    }
}
