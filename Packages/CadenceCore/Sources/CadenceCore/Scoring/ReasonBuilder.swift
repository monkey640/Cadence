import Foundation

/// Generates the single plain-English sentence shown under the verdict.
/// Copy is deliberately positive — "back off" protects progress, it is never
/// framed as failure — and never offers medical guidance.
enum ReasonBuilder {

    static func reason(
        verdict: Verdict,
        isBaselining: Bool,
        missingCoreSignal: Bool,
        confidence: ReadinessConfidence,
        conflict: Bool,
        phoneTestOnly: Bool,
        wearablePresent: Bool,
        components: ComponentScores
    ) -> String {
        if isBaselining {
            return "Still building your baseline — keep logging mornings and your readiness will sharpen."
        }

        // Only the weak phone tests were available — be explicit and cautious,
        // and nudge toward the higher-evidence daily check-in.
        if phoneTestOnly {
            switch verdict {
            case .push, .hold:
                return "Today's read is from a quick phone test only, so we kept volume moderate — add a morning check-in for a sharper call."
            case .backOff:
                return "Your phone test came in low — easing off today protects your progress while we learn more about you."
            }
        }

        // If the verdict is driven by the subjective check-in (no wearable in the
        // mix), speak to that directly.
        let driver = dominantDriver(components)
        if !wearablePresent && driver == .wellness {
            let line: String
            switch verdict {
            case .push, .hold:
                line = "Your check-in looks solid — we'll train, holding volume a touch since it's your self-report alone."
            case .backOff:
                line = "Your check-in says you're run down — a lighter day now keeps you progressing."
            }
            return line + conflictTail(conflict)
        }

        switch verdict {
        case .push:
            switch driver {
            case .hrv:   return "Your HRV is well above baseline — your body is primed to train hard today."
            case .sleep: return "Strong sleep last night has you recovered — green light to push."
            case .rhr:   return "Resting heart rate is low and steady — you're ready for a full session."
            case .wellness, .none:
                return "Your signals are strong across the board — go train."
            }
        case .hold:
            let tail = missingCoreSignal
                ? " Some data was missing, so we kept today moderate to be safe."
                : ""
            switch driver {
            case .hrv:   return "HRV is near your normal — a solid, controlled session fits today." + tail + conflictTail(conflict)
            case .sleep: return "Sleep was a touch short of usual — train, but ease off the volume." + tail + conflictTail(conflict)
            case .rhr:   return "Resting heart rate is slightly up — moderate the session today." + tail + conflictTail(conflict)
            case .wellness, .none:
                return "You're in a normal range — train as planned at a measured effort." + tail + conflictTail(conflict)
            }
        case .backOff:
            switch driver {
            case .hrv:   return "HRV is well below baseline — easing off today protects the work you've already banked."
            case .sleep: return "Short sleep is blunting recovery — a lighter day now keeps you progressing."
            case .rhr:   return "Resting heart rate is elevated — backing off today is how you come back stronger."
            case .wellness, .none:
                return "Your recovery signals are low — rest today protects your progress."
            }
        }
    }

    /// Appended when signals genuinely disagree, to explain the conservative call.
    private static func conflictTail(_ conflict: Bool) -> String {
        conflict ? " Your signals disagreed today, so we played it safe." : ""
    }

    private enum Driver { case hrv, sleep, rhr, wellness, none }

    /// The available signal that deviates most from neutral (50). HRV/sleep/RHR
    /// are the primary color; the subjective check-in stands in when none of the
    /// wearable trio is present.
    private static func dominantDriver(_ c: ComponentScores) -> Driver {
        let candidates: [(Driver, Double?)] = [
            (.hrv, c.hrv), (.sleep, c.sleep), (.rhr, c.rhr), (.wellness, c.wellness),
        ]
        let scored = candidates.compactMap { driver, score -> (Driver, Double)? in
            guard let score else { return nil }
            return (driver, abs(score - 50))
        }
        return scored.max(by: { $0.1 < $1.1 })?.0 ?? .none
    }
}
