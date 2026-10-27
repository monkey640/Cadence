import SwiftUI

/// CNS finger-tap test: 3-2-1 countdown, then 10 seconds of max tapping on a
/// big circle while a ring fills around it. Skip is always visible, never loud.
struct TapTestView: View {
    let baseline: Double?
    let onFinish: (Int?) -> Void      // nil = skipped

    private enum Phase: Equatable {
        case intro, countdown(Int), running, done
    }

    @State private var phase: Phase = .intro
    @State private var taps = 0
    @State private var progress: Double = 0     // 0...1 over the 10s window
    @State private var timerTask: Task<Void, Never>?

    private let duration: Double = 10

    var body: some View {
        VStack(spacing: 0) {
            Text(headline)
                .font(.displayBlack(26))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 32)

            Spacer()

            tapCircle

            Spacer()

            if phase == .done {
                Button("Continue") { onFinish(taps) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            Button("Skip") { timerTask?.cancel(); onFinish(nil) }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 24)
        }
        .onDisappear { timerTask?.cancel() }
    }

    private var headline: String {
        switch phase {
        case .intro, .countdown: return "Tap as fast as you can for 10 seconds."
        case .running: return "Go."
        case .done: return resultLine
        }
    }

    /// "42 taps — above your baseline" (±4% counts as "at").
    private var resultLine: String {
        guard let baseline, baseline > 0 else { return "\(taps) taps — building your baseline." }
        let ratio = Double(taps) / baseline
        let comparison = ratio > 1.04 ? "above" : (ratio < 0.96 ? "below" : "at")
        return "\(taps) taps — \(comparison) your baseline."
    }

    private var tapCircle: some View {
        ZStack {
            Circle()
                .stroke(Theme.laneLine, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.brand, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Theme.surfaceSecondary)
                .padding(18)

            centerContent
        }
        .frame(width: 260, height: 260)
        .contentShape(Circle())
        .onTapGesture { handleTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var centerContent: some View {
        switch phase {
        case .intro:
            Text("Tap to start")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
        case .countdown(let n):
            Text("\(n)")
                .font(.timingBoard(88))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
        case .running, .done:
            VStack(spacing: 2) {
                Text("\(taps)")
                    .font(.timingBoard(80))
                    .foregroundStyle(phase == .done ? Theme.brand : Theme.textPrimary)
                Text("taps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var accessibilityText: String {
        switch phase {
        case .intro: return "Tap test. Double-tap to start, then tap as fast as you can for ten seconds."
        case .countdown(let n): return "Starting in \(n)"
        case .running: return "\(taps) taps"
        case .done: return resultLine
        }
    }

    private func handleTap() {
        switch phase {
        case .intro:
            start()
        case .running:
            taps += 1
            Haptics.tick()
        default:
            break
        }
    }

    private func start() {
        timerTask = Task {
            for n in [3, 2, 1] {
                withAnimation(.easeOut(duration: 0.2)) { phase = .countdown(n) }
                Haptics.tick()
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            phase = .running
            Haptics.stamp()
            withAnimation(.linear(duration: duration)) { progress = 1 }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            Haptics.stamp()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { phase = .done }
        }
    }
}
