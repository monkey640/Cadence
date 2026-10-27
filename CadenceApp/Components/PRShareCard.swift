import SwiftUI
import UIKit

/// Aspect-ratio variants for sharing to different surfaces. One layout, three
/// canvases — the giant time scales to fit each.
enum PRCardVariant: String, CaseIterable, Identifiable {
    case story     // 9:16 — Instagram/TikTok stories
    case square    // 1:1  — feed / grid
    case post      // 4:5  — portrait feed

    var id: String { rawValue }
    var label: String {
        switch self { case .story: "Story"; case .square: "Square"; case .post: "Post" }
    }
    /// Base render size (multiplied 3× by the renderer). Ratios: 9:16, 1:1, 4:5.
    var size: CGSize {
        switch self {
        case .story:  return CGSize(width: 360, height: 640)
        case .square: return CGSize(width: 400, height: 400)
        case .post:   return CGSize(width: 360, height: 450)
        }
    }
    /// Tighter vertical breathing room on the short square canvas.
    var verticalPadding: CGFloat { self == .square ? 30 : 44 }
    /// The time is the hero — scale it up on the roomier canvases.
    var timeFontSize: CGFloat { self == .square ? 78 : 92 }
}

/// The shareable PR card — styled like a stadium scoreboard photo: near-black
/// background, lane-line rules, giant monospaced timing digits, Cadence
/// wordmark in track red. Renders in the athlete's current colour scheme (all
/// colours read from `Theme.current`). Shares nothing sensitive: first name,
/// the PR, a date.
struct PRShareCard: View {
    let firstName: String
    let effortLabel: String     // "60m", "150m"
    let timeSeconds: Double
    let date: Date
    var variant: PRCardVariant = .post

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PERSONAL RECORD")
                .font(.system(size: 13, weight: .black))
                .tracking(2.5)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, variant.verticalPadding)

            Spacer()

            Text(effortLabel)
                .font(.system(size: 28, weight: .black))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)

            Text(timeText)
                .font(.system(size: variant.timeFontSize, weight: .black).monospacedDigit())
                .tracking(-2)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                .padding(.vertical, 18)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if !firstName.isEmpty {
                        Text(firstName.uppercased())
                            .font(.system(size: 15, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(date.formatted(.dateTime.month(.wide).day().year()))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("CADENCE")
                    .font(.system(size: 14, weight: .black))
                    .tracking(3)
                    .foregroundStyle(Theme.brand)
            }
            .padding(.bottom, variant.verticalPadding)
        }
        .padding(.horizontal, 32)
        .frame(width: variant.size.width, height: variant.size.height)
        .background(Theme.background)
    }

    /// Timing-board format: 6.72 under a minute, 1:12.4 above.
    private var timeText: String {
        if timeSeconds < 60 { return String(format: "%.2f", timeSeconds) }
        let minutes = Int(timeSeconds) / 60
        let rest = timeSeconds - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, rest)
    }
}

@MainActor
enum PRCardRenderer {
    /// Render a card variant to a UIImage at 3× for a crisp post.
    static func image(firstName: String, effortLabel: String, timeSeconds: Double,
                      date: Date, variant: PRCardVariant = .post) -> UIImage? {
        let renderer = ImageRenderer(content: PRShareCard(
            firstName: firstName, effortLabel: effortLabel,
            timeSeconds: timeSeconds, date: date, variant: variant))
        renderer.scale = 3
        return renderer.uiImage
    }
}
