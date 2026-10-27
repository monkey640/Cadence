import SwiftUI
import CadenceCore

/// The verdict word in heavy caps on its color. The word always accompanies the
/// color — the verdict is never conveyed by color alone.
struct VerdictBadge: View {
    let verdict: Verdict
    var large: Bool = false

    var body: some View {
        Text(verdict.badgeText)
            .font(.system(size: large ? 22 : 13, weight: .black))
            .tracking(1.2)
            .foregroundStyle(Theme.background)
            .padding(.horizontal, large ? 16 : 10)
            .padding(.vertical, large ? 8 : 4)
            .background(verdict.color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel("Verdict: \(verdict.displayName)")
    }
}

/// Small confidence pill shown with every readiness score.
struct ConfidenceBadge: View {
    let confidence: ReadinessConfidence

    var body: some View {
        Text(confidence.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.surfaceSecondary)
            .clipShape(Capsule())
    }
}

/// Session-type chip used on plan day cards and history rows.
struct SessionTypeBadge: View {
    let text: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
    }
}
