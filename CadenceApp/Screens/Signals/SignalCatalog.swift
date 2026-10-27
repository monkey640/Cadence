import Foundation
import CadenceCore

/// Static descriptions of every readiness signal: grouping, icon, units, and
/// the honest one-sentence reads per band. Copy names the actual signal and
/// what it means — coach-like, never vague.
struct SignalDescriptor: Identifiable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case wearable = "Wearable signals"
        case subjective = "Subjective check-in"
        case phoneTests = "Phone tests"
    }

    let id: String
    let label: String
    let icon: String
    let group: Group
    /// Formats a raw value ("52 ms"); nil when the signal has no raw unit
    /// (subscores only). @Sendable so the static catalog is concurrency-safe —
    /// these closures are pure formatters and capture nothing.
    let format: (@Sendable (Double) -> String)?
    let goodRead: String
    let steadyRead: String
    let lowRead: String
    /// Shown when the signal has no data today.
    let missingRead: String

    static let all: [SignalDescriptor] = [
        SignalDescriptor(
            id: "hrv", label: "HRV", icon: "waveform.path.ecg", group: .wearable,
            format: { "\(Int($0.rounded())) ms" },
            goodRead: "Your HRV is at or above your baseline — your nervous system looks recovered.",
            steadyRead: "Your HRV is close to your baseline — normal day-to-day variation.",
            lowRead: "Your HRV is lower than usual, which suggests your nervous system is still recovering. This pulled your score down.",
            missingRead: "Not available — no Apple Watch data. Connect a wearable in Settings to unlock this signal."),
        SignalDescriptor(
            id: "sleep", label: "Sleep duration", icon: "bed.double.fill", group: .wearable,
            format: { String(format: "%.1f h", $0 / 3600) },
            goodRead: "You slept at or above your usual — recovery had the time it needed.",
            steadyRead: "Sleep was close to your usual.",
            lowRead: "You slept less than usual. Short sleep is the most common reason a score drops.",
            missingRead: "Not available — no sleep data in Apple Health. A watch or sleep tracking unlocks this signal."),
        SignalDescriptor(
            id: "sleepQuality", label: "Sleep quality", icon: "moon.stars.fill", group: .wearable,
            format: { String(format: "%.1f h deep + REM", $0 / 3600) },
            goodRead: "Deep and REM sleep were at or above your usual — good quality rest.",
            steadyRead: "Sleep quality was around your usual mix.",
            lowRead: "Less deep and REM sleep than usual — the restorative stages came up short.",
            missingRead: "Not available — needs a wearable that records sleep stages."),
        SignalDescriptor(
            id: "rhr", label: "Resting heart rate", icon: "heart.fill", group: .wearable,
            format: { "\(Int($0.rounded())) bpm" },
            goodRead: "Resting heart rate is at or below your baseline — a good recovery sign.",
            steadyRead: "Resting heart rate is near your baseline.",
            lowRead: "Resting heart rate is elevated vs your baseline — your body is still working on something.",
            missingRead: "Not available — no Apple Watch data. Connect a wearable in Settings to unlock this signal."),
        SignalDescriptor(
            id: "respiratory", label: "Breathing rate", icon: "lungs.fill", group: .wearable,
            format: { String(format: "%.1f /min", $0) },
            goodRead: "Overnight breathing rate is normal for you.",
            steadyRead: "Overnight breathing rate is near your baseline.",
            lowRead: "Breathing rate ran above your baseline overnight — sometimes an early strain or illness sign.",
            missingRead: "Not available — needs an Apple Watch that records respiratory rate."),
        SignalDescriptor(
            id: "wristTemp", label: "Wrist temperature", icon: "thermometer.medium", group: .wearable,
            format: { String(format: "%.1f °C", $0) },
            goodRead: "Wrist temperature is in your normal range.",
            steadyRead: "Wrist temperature is close to your baseline.",
            lowRead: "Wrist temperature deviated from your baseline — worth watching alongside how you feel.",
            missingRead: "Not available — needs Apple Watch Series 8 or later, worn during sleep."),
        SignalDescriptor(
            id: "load", label: "Training load", icon: "figure.run", group: .wearable,
            format: nil,
            goodRead: "Recent training load is in a healthy range vs your last month.",
            steadyRead: "Training load is steady vs your last month.",
            lowRead: "Recent load ramped up fast vs your last month — recovery matters more this week.",
            missingRead: "No workout history yet — load kicks in once sessions are logged."),
        SignalDescriptor(
            id: "wellness", label: "Morning check-in", icon: "checklist", group: .subjective,
            format: nil,
            goodRead: "Your check-in reads well — you told us you're ready, and that counts.",
            steadyRead: "Your check-in reads mixed — some freshness, some fatigue.",
            lowRead: "Your check-in flagged fatigue or soreness — that pulled the score toward caution.",
            missingRead: "No check-in today — five questions in the morning flow unlock this signal."),
        SignalDescriptor(
            id: "tap", label: "Tap test", icon: "hand.tap.fill", group: .phoneTests,
            format: { "\(Int($0.rounded())) taps" },
            goodRead: "Tap speed at or above your baseline — your nervous system is firing.",
            steadyRead: "Tap speed near your baseline.",
            lowRead: "Tap speed below your baseline — a common sign your nervous system is still tired after hard sprint work.",
            missingRead: "Not taken today — it's 10 seconds inside the morning check-in."),
        SignalDescriptor(
            id: "jump", label: "Jump test", icon: "arrow.up.circle.fill", group: .phoneTests,
            format: { String(format: "%.1f cm", $0) },
            goodRead: "Jump height at or above your baseline — legs are ready.",
            steadyRead: "Jump height near your baseline.",
            lowRead: "Jump height below your baseline — your legs haven't fully bounced back.",
            missingRead: "Not taken today — the jump test is optional in the morning check-in."),
    ]

    /// The five morning check-in questions, as individual signals. Kept OUT of
    /// `all` (so the grouped breakdown list stays a clean overview with one
    /// "Morning check-in" row) but resolvable by id, so tapping a subjective lane
    /// on Today deep-links to *that question's* detail — not the composite.
    static let subjectiveQuestions: [SignalDescriptor] = [
        subjective("subjSleep", "Sleep (self-rated)", "bed.double.fill",
                   good: "You rated your sleep well — recovery had what it needed.",
                   steady: "You rated your sleep about average.",
                   low: "You rated your sleep poorly — the most common reason to hold back."),
        subjective("subjSoreness", "Soreness", "figure.walk",
                   good: "Legs feel fresh — no soreness flag.",
                   steady: "A little soreness, nothing unusual.",
                   low: "You flagged real soreness — that pulled the score toward caution."),
        subjective("subjFatigue", "Fatigue", "bolt.fill",
                   good: "You feel energized — a good sign to train.",
                   steady: "Middling energy today.",
                   low: "You flagged fatigue — worth respecting with a lighter day."),
        subjective("subjStress", "Stress", "brain.head.profile",
                   good: "You feel calm — low stress helps recovery.",
                   steady: "Some stress, around your normal.",
                   low: "You flagged high stress — it competes with training for recovery."),
        subjective("subjMood", "Mood", "face.smiling.fill",
                   good: "Good mood — often tracks with readiness.",
                   steady: "Mood is about average.",
                   low: "Low mood today — sometimes an early under-recovery signal."),
    ]

    /// Builder for a 1–5 self-rated check-in question (higher = better).
    private static func subjective(_ id: String, _ label: String, _ icon: String,
                                   good: String, steady: String, low: String) -> SignalDescriptor {
        SignalDescriptor(
            id: id, label: label, icon: icon, group: .subjective,
            format: { "\(Int($0.rounded())) / 5" },
            goodRead: good, steadyRead: steady, lowRead: low,
            missingRead: "Not answered today — it's one tap in the morning check-in.")
    }

    static func by(id: String) -> SignalDescriptor? {
        all.first { $0.id == id } ?? subjectiveQuestions.first { $0.id == id }
    }
}
