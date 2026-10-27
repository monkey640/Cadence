import SwiftUI

/// Everything a contribution ring needs to draw and describe itself.
struct SignalRing: Identifiable, Equatable {
    let id: String            // stable signal key ("hrv", "sleep", …)
    let label: String         // "HRV", "Sleep", "Soreness"
    let score: Double         // the signal's 0–100 subscore vs baseline

    /// Short VoiceOver phrase, e.g. "strong, score 84 of 100". Derived from the
    /// same band as the visible color/word, so the two can never disagree.
    var accessibilityDetail: String {
        "\(bandWord), score \(Int(score.rounded())) of 100"
    }

    /// Band color, judged against the engine's baseline anchor (a subscore of 72
    /// = "at your usual"): clearly above lifts the score (green), around baseline
    /// is neutral (amber), meaningfully below is dragging it down (red).
    var color: Color {
        switch band {
        case .strong: return Theme.push
        case .steady: return Theme.hold
        case .low: return Theme.backOff
        }
    }

    enum Band { case strong, steady, low }
    var band: Band {
        if score >= 82 { return .strong }   // ~+0.5 SD or better
        if score >= 60 { return .steady }   // within ~0.6 SD of baseline
        return .low                          // meaningfully below baseline
    }

    var bandWord: String {
        switch band { case .strong: return "strong"; case .steady: return "steady"; case .low: return "low" }
    }
}

/// A custom-drawn partial arc (Path, not Charts) filled proportionally to the
/// signal's subscore. Fills with a spring on appear; callers stagger via `delay`.
struct ContributionRing: View {
    let ring: SignalRing
    var delay: Double = 0
    var size: CGFloat = 64

    @State private var fill: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Gauge spans 270°, opening at the bottom — reads like a dial, not a donut.
    private let gaugeSpan = 0.75

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                arc(to: gaugeSpan)
                    .stroke(Theme.laneLine, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                arc(to: gaugeSpan * fill / 100)
                    .stroke(ring.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Text("\(Int(ring.score.rounded()))")
                    .font(.timingBoard(18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: size, height: size)

            Text(ring.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .onAppear {
            if reduceMotion {
                fill = ring.score
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay)) {
                    fill = ring.score
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.label) contribution: \(ring.accessibilityDetail)")
    }

    /// 270° arc from the lower-left, clockwise to the lower-right.
    private func arc(to fraction: Double) -> Path {
        Path { path in
            let start = Angle(degrees: 135)
            path.addArc(
                center: CGPoint(x: size / 2, y: size / 2),
                radius: size / 2 - 3,
                startAngle: start,
                endAngle: start + Angle(degrees: 360 * fraction),
                clockwise: false)
        }
    }
}
