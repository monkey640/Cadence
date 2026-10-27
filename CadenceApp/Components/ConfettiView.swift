import SwiftUI

/// A brief PR-celebration burst — custom particles in brand red + white, no
/// library. Purely decorative: hidden from VoiceOver, skipped under Reduce
/// Motion (the caller shows the PR text either way; information is never
/// gated behind the animation).
struct ConfettiView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Particle {
        let x: CGFloat          // launch x, as a fraction of width
        let vx: CGFloat         // horizontal drift, points/s
        let vy: CGFloat         // initial upward velocity, points/s (negative = up)
        let size: CGFloat
        let spin: Double        // radians/s
        let isBrand: Bool
    }

    /// @State so a parent re-render can't reshuffle particles mid-flight.
    @State private var particles: [Particle] = (0..<44).map { i in
        Particle(
            x: CGFloat.random(in: 0.15...0.85),
            vx: CGFloat.random(in: -80...80),
            vy: CGFloat.random(in: -520 ... -260),
            size: CGFloat.random(in: 5...9),
            spin: Double.random(in: -6...6),
            isBrand: i % 3 != 0)   // ~2/3 brand red, 1/3 white
    }

    /// @State so a parent re-render can't restart the burst.
    @State private var start = Date()
    private let lifetime: Double = 1.8

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSince(start)
                    guard t < lifetime else { return }
                    let gravity: CGFloat = 900
                    for p in particles {
                        let x = p.x * size.width + p.vx * t
                        let y = size.height * 0.45 + p.vy * t + 0.5 * gravity * t * t
                        guard y < size.height + 20 else { continue }
                        let fade = max(0, 1 - t / lifetime)
                        var rect = context
                        rect.translateBy(x: x, y: y)
                        rect.rotate(by: Angle(radians: p.spin * t))
                        rect.opacity = fade
                        rect.fill(
                            Path(CGRect(x: -p.size / 2, y: -p.size / 2,
                                        width: p.size, height: p.size * 0.6)),
                            with: .color(p.isBrand ? Theme.brand : .white))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
