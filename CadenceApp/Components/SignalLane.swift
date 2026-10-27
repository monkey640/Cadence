import SwiftUI

/// A signal shown as a lane — a horizontal bar in its track with a baseline
/// tick at the neutral anchor (72), plus a right-aligned status word. Replaces
/// the contribution ring on Today: more distinctive, and literally the track.
struct SignalLane: View {
    let ring: SignalRing
    var seasonBest: Bool = false
    /// Staggered entrance: the bar grows from 0 to its value after this delay,
    /// so the lanes fill in sequence on the score reveal. Ignored under Reduce Motion.
    var revealDelay: Double = 0
    /// When false, the bar renders full immediately (no entrance) — used when the
    /// day's reveal has already played, so opening Today again doesn't replay it.
    var animated: Bool = true

    /// The engine's neutral anchor — a subscore of 72 means "at your baseline".
    private let baselineAnchor: Double = 72

    /// 0→1 fill fraction, driven on appear so the bar animates in.
    @State private var fill: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(ring.label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                if seasonBest {
                    Text("season best")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.push)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.push.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Spacer()
                Text(ring.bandWord)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(ring.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceSecondary).frame(height: 6)
                    Capsule().fill(ring.color)
                        .frame(width: geo.size.width * CGFloat(max(0, min(100, ring.score)) / 100) * fill, height: 6)
                    // baseline tick — where "your usual" sits
                    Rectangle().fill(Theme.textSecondary)
                        .frame(width: 1.5, height: 12)
                        .offset(x: geo.size.width * CGFloat(baselineAnchor / 100))
                        .opacity(0.7)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.label): \(ring.accessibilityDetail)\(seasonBest ? ", season best" : "")")
        .onAppear {
            if reduceMotion || !animated {
                fill = 1
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(revealDelay)) {
                    fill = 1
                }
            }
        }
    }
}
