import Foundation

/// The single source of truth for the not-medical-advice disclaimer.
/// Shown at onboarding, permanently in Settings, and as a footer on Today.
enum Disclaimer {
    static let short = "Cadence is a training-readiness tool, not medical advice."

    static let full = """
    Cadence estimates training readiness from your Apple Health data to help you \
    decide how hard to train. It is not a medical device and does not diagnose, \
    treat, or give medical advice. Persistent low readiness, unusual symptoms, or \
    pain warrant seeing a qualified professional. Always train within your limits.
    """
}
