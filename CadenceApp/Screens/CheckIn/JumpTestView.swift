import SwiftUI
import CoreMotion

/// Countermovement-jump measurement from the accelerometer — no camera.
///
/// Physics: the raw accelerometer magnitude reads ~1 g standing, spikes >1 g on
/// push-off, drops to ~0 g in free flight, and spikes again on landing. Height
/// comes from flight time T (time both feet are off the ground): the rise time
/// is T/2, so h = ½·g·(T/2)² = g·T²/8.
///
/// Detection is a four-phase state machine — settle → push-off spike → free
/// fall → landing — so a phone that's merely *lowered* or bobbled (no push-off
/// spike, or no clean free-fall window) can't fake a jump. Every threshold
/// lives in `Calibration` so on-device tuning is a one-place edit.
@MainActor
@Observable
final class JumpDetector {
    /// Every tunable number, in one place. Defaults are physics-derived starting
    /// points — refine `pushOffG` / `landingG` first on a real device (raw
    /// accelerometer noise and grip vary), then the flight bounds if needed.
    struct Calibration: Sendable {
        var sampleHz: Double = 100                 // accelerometer rate
        var settleSeconds: Double = 0.4            // ignore initial handling noise
        var pushOffG: Double = 1.6                 // upward push-off spike that arms a jump
        var freeFallG: Double = 0.35               // below this = airborne
        var freeFallSamples: Int = 2               // consecutive sub-threshold samples to confirm flight (debounce)
        var landingG: Double = 1.8                 // landing-impact spike that ends flight
        var minFlightSeconds: Double = 0.15        // ~2.8 cm floor — rejects twitches
        var maxFlightSeconds: Double = 0.95        // ~111 cm ceiling — rejects dropped phones
        var pushToFlightWindow: Double = 0.5       // push-off must be followed by flight within this, else re-arm
        var attemptTimeout: Double = 15            // give up gracefully after this

        static let `default` = Calibration()
    }

    enum State: Equatable {
        case idle
        case waiting            // updates running, athlete hasn't completed a jump
        case measured(Double)   // height, cm
        case failed(String)
    }

    /// The four phases of a jump, internal to detection (`State` stays UI-facing).
    private enum Phase {
        case ready                          // armed, watching for push-off
        case launched(deadline: TimeInterval)  // push-off seen, watching for free fall
        case airborne(since: TimeInterval)     // in flight, watching for landing
    }

    var calibration: Calibration = .default
    private(set) var state: State = .idle

    private let manager = CMMotionManager()
    private var phase: Phase = .ready
    private var startTimestamp: TimeInterval?
    private var flightStart: TimeInterval?
    private var freeFallCount = 0
    private var timeout: Task<Void, Never>?

    private let gravity = 9.81

    var isAvailable: Bool { manager.isAccelerometerAvailable }

    func start() {
        guard manager.isAccelerometerAvailable else {
            state = .failed("No accelerometer available on this device.")
            return
        }
        state = .waiting
        resetTracking()
        startTimestamp = nil
        manager.accelerometerUpdateInterval = 1.0 / calibration.sampleHz
        manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            MainActor.assumeIsolated { self.process(data) }
        }
        // One attempt, bounded: bow out gracefully if no clean jump is caught.
        timeout = Task { [attemptTimeout = calibration.attemptTimeout] in
            try? await Task.sleep(for: .seconds(attemptTimeout))
            guard !Task.isCancelled, self.state == .waiting else { return }
            self.stop()
            self.state = .failed("Didn't catch a jump — you can skip it today.")
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        timeout?.cancel()
    }

    /// Reset flight tracking without ending the attempt (a false start re-arms).
    private func resetTracking() {
        phase = .ready
        flightStart = nil
        freeFallCount = 0
    }

    private func process(_ data: CMAccelerometerData) {
        guard state == .waiting else { return }
        let t = data.timestamp
        if startTimestamp == nil { startTimestamp = t }
        // Ignore the first fraction of a second — pure handling noise as they set up.
        if t - (startTimestamp ?? t) < calibration.settleSeconds { return }

        let a = data.acceleration
        let g = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()   // magnitude, in g

        switch phase {
        case .ready:
            // A real jump begins with an upward push-off spike. Lowering or
            // bobbling the phone never produces this, so it can't false-trigger.
            if g > calibration.pushOffG {
                phase = .launched(deadline: t + calibration.pushToFlightWindow)
            }

        case .launched(let deadline):
            if g < calibration.freeFallG {
                freeFallCount += 1
                if freeFallCount == 1 { flightStart = t }           // stamp the first free-fall sample
                if freeFallCount >= calibration.freeFallSamples {
                    phase = .airborne(since: flightStart ?? t)
                }
            } else {
                // Not free fall — debounce, and if the push-off never leads to
                // flight it was a stomp/bump: re-arm and let them jump.
                freeFallCount = 0
                flightStart = nil
                if t > deadline { phase = .ready }
            }

        case .airborne(let since):
            if g > calibration.landingG {
                let flight = t - since
                if flight >= calibration.minFlightSeconds, flight <= calibration.maxFlightSeconds {
                    let heightCm = gravity * flight * flight / 8 * 100
                    stop()
                    state = .measured((heightCm * 10).rounded() / 10)
                } else {
                    resetTracking()   // implausible airtime — re-arm within the attempt window
                }
            } else if t - since > calibration.maxFlightSeconds + 0.3 {
                resetTracking()       // never landed / lost the signal
            }
        }
    }
}

/// The optional jump test screen: instructions, one attempt, always skippable.
struct JumpTestView: View {
    let onFinish: (Double?) -> Void   // nil = skipped

    @State private var detector = JumpDetector()
    /// One retry allowed after a miss — then it's skip-only (never a frustrating loop).
    @State private var retriedOnce = false

    var body: some View {
        VStack(spacing: 0) {
            Text(headline)
                .font(.displayBlack(26))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 32)

            Text(subline)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 12)

            Spacer()

            centerpiece

            Spacer()

            if case .measured = detector.state {
                Button("Continue") {
                    if case .measured(let h) = detector.state { onFinish(h) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            } else if detector.state == .idle {
                Button("I'm ready — start") { detector.start() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            } else if case .failed = detector.state, !retriedOnce {
                Button("Try again") { retriedOnce = true; detector.start() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            Button("Skip") { detector.stop(); onFinish(nil) }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 24)
        }
        .onDisappear { detector.stop() }
    }

    private var headline: String {
        switch detector.state {
        case .idle: return "Jump test"
        case .waiting: return "Hold the phone and jump."
        case .measured(let h): return String(format: "%.1f cm", h)
        case .failed: return "No jump detected"
        }
    }

    private var subline: String {
        switch detector.state {
        case .idle:
            return "Optional. Hold your phone firmly, stand still, then jump as high as you can — the accelerometer measures your hang time."
        case .waiting:
            return "Stand still for a beat, then jump. One attempt."
        case .measured:
            return "Logged — this builds your daily explosiveness baseline."
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder private var centerpiece: some View {
        ZStack {
            Circle().stroke(Theme.laneLine, lineWidth: 8)
            switch detector.state {
            case .waiting:
                Image(systemName: "figure.jumprope")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.brand)
                    .symbolEffect(.pulse)
            case .measured(let h):
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", h))
                        .font(.timingBoard(64))
                        .foregroundStyle(Theme.brand)
                    Text("cm")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            default:
                Image(systemName: "figure.jumprope")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 220, height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline)
    }
}
