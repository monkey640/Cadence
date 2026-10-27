import SwiftUI
import CadenceCore

/// A coach's-note review card for a personalization proposal. Tentative language
/// throughout (the signal includes a subjective "faded late" tap), keeps the
/// draft notice visible, and never changes anything until the user taps Apply.
struct PersonalizationCard: View {
    let proposal: AdjustmentProposal
    let isDraft: Bool
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb").foregroundStyle(Theme.accent)
                Text("Worth a look").font(.headline)
                Spacer()
                if isDraft {
                    Text("DRAFT").font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.hairline).clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            // The WHY, in plain tentative language — this is the feature.
            Text(observation)
                .font(.subheadline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(suggestion)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("A draft suggestion from your own logged sessions — not coach-validated. Nothing changes unless you apply it, and you can undo anytime.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Button("Apply this", action: onApply).buttonStyle(PrimaryButtonStyle())
                Button("Not now", action: onDismiss)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.accent.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var increased: Quality? { proposal.changes.first { $0.deltaReps > 0 }?.quality }
    private var reduced: Quality? { proposal.changes.first { $0.deltaReps < 0 }?.quality }

    /// Tentative observation tied to the actual trigger — never a diagnosis.
    private var observation: String {
        let d = proposal.deficiency
        if d.contains("late_race") || d.contains("speed_endurance") || d.contains("special_endurance") {
            let q = increased?.displayName ?? "endurance"
            return "Your \(q) reps have felt like they're fading late over the last few sessions."
        }
        if d.contains("weak_top_speed") {
            return "Your top-end speed has looked like it's lagging your acceleration lately."
        }
        if d.contains("chronic") || d.contains("underrecovery") {
            return "Your readiness has been trending down over the last week or so."
        }
        return "A pattern's shown up across your recent sessions that's worth looking at."
    }

    private var suggestion: String {
        if proposal.kind == .reduce {
            return "Might be worth easing one hard session this week to let things bounce back."
        }
        if let inc = increased, let red = reduced {
            return "Consider shifting one session toward more \(inc.displayName) this week, easing slightly off \(red.displayName)."
        }
        if let inc = increased {
            return "Consider a touch more \(inc.displayName) this week."
        }
        return "Consider a small adjustment this week."
    }
}
