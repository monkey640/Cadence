import SwiftUI
import SwiftData
import CadenceCore

/// The morning ritual: five wellness questions → tap test → jump test → score
/// reveal. Full-screen and dark throughout — a pre-race sequence, not a form.
struct CheckInFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = CheckInFlowModel()

    /// Called after the reveal's "See today's session" tap, so Today can reload.
    var onComplete: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            if model.step != .reveal && model.step != .computing {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .cadenceBackground()
        .preferredColorScheme(Theme.scheme)
        .onAppear { model.loadTapBaseline(context: context) }
        .gesture(
            DragGesture(minimumDistance: 40).onEnded { value in
                if value.translation.width > 60 { withAnimation(step) { model.goBack() } }
            })
    }

    private var step: Animation { .easeOut(duration: 0.25) }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .question(let index):
            WellnessQuestionView(
                question: WellnessQuestion.all[index],
                value: $model.answers[index],
                onCommitted: { withAnimation(step) { model.advanceFromQuestion(index) } })
            .id("q\(index)")
            .transition(slide)
        case .tapTest:
            TapTestView(
                baseline: model.tapBaseline,
                onFinish: { count in withAnimation(step) { model.finishTapTest(count: count) } })
            .transition(slide)
        case .jumpTest:
            JumpTestView(
                onFinish: { height in
                    withAnimation(step) { model.finishJumpTest(heightCm: height, context: context) }
                })
            .transition(slide)
        case .computing:
            VStack(spacing: 16) {
                ProgressView().tint(Theme.brand)
                Text("Reading your morning…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .transition(.opacity)
        case .reveal:
            if let output = model.output {
                ScoreRevealView(
                    output: output,
                    completionSeconds: model.completionSeconds,
                    onSeeSession: { onComplete(); dismiss() })
                .transition(.opacity)
            } else {
                revealFallback
            }
        }
    }

    /// Compute failed outright (no HealthKit *and* engine error) — never trap
    /// the athlete in the flow. The check-in itself is already saved.
    private var revealFallback: some View {
        VStack(spacing: 16) {
            Text("Check-in saved")
                .font(.displayBlack(28))
                .foregroundStyle(Theme.textPrimary)
            Text(model.computeError ?? "Your score will compute next time the app loads your data.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { onComplete(); dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(32)
    }

    /// A visible back affordance (not just the swipe / dots) + centered progress.
    private var topBar: some View {
        ZStack {
            progressDots
            HStack {
                Button { withAnimation(step) { model.goBack() } } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Theme.card)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Back")
                .opacity(model.progressIndex > 0 ? 1 : 0)
                .disabled(model.progressIndex == 0)
                Spacer()
            }
        }
    }

    /// Progress dots double as back-navigation to revise an earlier answer.
    private var progressDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<model.progressCount, id: \.self) { index in
                Button {
                    withAnimation(step) { model.jumpToQuestion(index) }
                } label: {
                    Circle()
                        .fill(index <= model.progressIndex ? Theme.brand : Theme.laneLine)
                        .frame(width: 7, height: 7)
                }
                .buttonStyle(.plain)
                .disabled(index >= model.progressIndex)
            }
        }
        .accessibilityLabel("Step \(model.progressIndex + 1) of \(model.progressCount)")
    }

    private var slide: AnyTransition {
        model.movingForward
            ? .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                          removal: .move(edge: .leading).combined(with: .opacity))
            : .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                          removal: .move(edge: .trailing).combined(with: .opacity))
    }
}
