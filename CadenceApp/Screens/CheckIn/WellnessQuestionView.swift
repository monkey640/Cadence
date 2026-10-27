import SwiftUI

/// One wellness question: big text, a five-step selector with a haptic tick per
/// step, a subtle icon that reacts to the value, and auto-advance ~0.7s after a
/// pick — no "Next" button to tap five times.
struct WellnessQuestionView: View {
    let question: WellnessQuestion
    @Binding var value: Int?
    let onCommitted: () -> Void

    @State private var advanceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: question.icon)
                .font(.system(size: 44))
                .foregroundStyle(iconColor)
                .scaleEffect(value == nil ? 1 : 1.08)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
                .accessibilityHidden(true)
                .padding(.bottom, 28)

            Text(question.text)
                .font(.displayBlack(32))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            selector
                .padding(.horizontal, 24)

            HStack {
                Text(question.lowAnchor)
                Spacer()
                Text(question.highAnchor)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 28)
            .padding(.top, 12)

            Spacer()
        }
        .onDisappear { advanceTask?.cancel() }
    }

    /// Five fat steps — each a real tap target, filled up to the selection.
    private var selector: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { step in
                Button {
                    select(step)
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fillColor(for: step))
                        .frame(height: 64)
                        .overlay {
                            // Every step shows its number, faint until chosen, so
                            // the scale reads as 1–5 before anyone taps — five
                            // blank tiles looked unfinished and hid the order.
                            Text("\(step)")
                                .font(.timingBoard(22, weight: .bold))
                                .foregroundStyle(numberColor(for: step))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(step) of 5")
                .accessibilityAddTraits(value == step ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(question.text)
    }

    private func select(_ step: Int) {
        Haptics.tick()
        value = step
        // Re-picking restarts the window, so a quick correction never races the advance.
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            onCommitted()
        }
    }

    private func numberColor(for step: Int) -> Color {
        guard let value else { return Theme.textSecondary.opacity(0.55) }
        if step == value { return Theme.background }
        // Filled-but-not-chosen steps keep a quiet number; empty ones stay faint.
        return step < value ? Theme.background.opacity(0.35) : Theme.textSecondary.opacity(0.55)
    }

    private func fillColor(for step: Int) -> Color {
        guard let value else { return Theme.surfaceSecondary }
        return step <= value ? stepColor(value) : Theme.surfaceSecondary
    }

    /// The selection tints low → red-orange, mid → amber, high → green, so the
    /// selector itself reads like a readiness dial.
    private func stepColor(_ value: Int) -> Color {
        switch value {
        case 1, 2: return Theme.backOff
        case 3: return Theme.hold
        default: return Theme.push
        }
    }

    private var iconColor: Color {
        guard let value else { return Theme.textSecondary }
        return stepColor(value)
    }
}
