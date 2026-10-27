import SwiftUI
import UIKit

/// A 9:16 shareable "week in review" recap — stadium-scoreboard styling, the same
/// language as the PR card. Scheme-aware: every colour reads `Theme.current`.
/// Shares nothing sensitive: first name, a date range, the week's counts.
struct WeeklyRecapCard: View {
    let firstName: String
    let weekLabel: String        // "Aug 4–10"
    let trainedDays: Int
    let reps: Int
    let readinessAvg: Int?
    let prCount: Int

    /// 9:16, story-friendly.
    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WEEK IN REVIEW")
                .font(.system(size: 13, weight: .black)).tracking(2.5)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 52)
            Text(weekLabel)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 4)

            Spacer()

            recapStat("\(trainedDays)", trainedDays == 1 ? "SESSION" : "SESSIONS")
            recapStat("\(reps)", "REPS LOGGED")
            if let avg = readinessAvg { recapStat("\(avg)", "AVG READINESS") }
            if prCount > 0 {
                recapStat("\(prCount)", prCount == 1 ? "PERSONAL RECORD" : "PERSONAL RECORDS", accent: true)
            }

            Spacer()

            HStack {
                if !firstName.isEmpty {
                    Text(firstName.uppercased())
                        .font(.system(size: 15, weight: .bold)).tracking(1.5)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text("CADENCE")
                    .font(.system(size: 14, weight: .black)).tracking(3)
                    .foregroundStyle(Theme.brand)
            }
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 32)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.background)
    }

    private func recapStat(_ value: String, _ label: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 60, weight: .black).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(accent ? Theme.brand : Theme.textPrimary)
            Text(label)
                .font(.system(size: 12, weight: .bold)).tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 9)
    }
}

@MainActor
enum WeeklyRecapRenderer {
    /// Render the recap to a UIImage at 3× for a crisp story post.
    static func image(firstName: String, weekLabel: String, trainedDays: Int,
                      reps: Int, readinessAvg: Int?, prCount: Int) -> UIImage? {
        let renderer = ImageRenderer(content: WeeklyRecapCard(
            firstName: firstName, weekLabel: weekLabel, trainedDays: trainedDays,
            reps: reps, readinessAvg: readinessAvg, prCount: prCount))
        renderer.scale = 3
        return renderer.uiImage
    }
}
