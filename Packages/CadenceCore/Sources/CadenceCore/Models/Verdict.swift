import Foundation

/// The single, plain-English readiness call shown large at the top of Today.
public enum Verdict: String, Equatable, Sendable, CaseIterable {
    /// Body is ready — train as planned (or at full intensity).
    case push
    /// Proceed, but with a moderated session.
    case hold
    /// Recover today. Framed as protecting progress, never as failure.
    case backOff

    /// Human-facing label, reused by Today, History, and the morning notification.
    public var displayName: String {
        switch self {
        case .push: return "Push"
        case .hold: return "Hold"
        case .backOff: return "Back off"
        }
    }
}
