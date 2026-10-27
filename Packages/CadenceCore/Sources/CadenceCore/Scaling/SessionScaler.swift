import Foundation

/// Scales a planned session by the readiness volume multiplier.
///
/// Guardrails baked in, per the brief:
///  - never increases volume beyond what was planned (multiplier is ≤ 1.0),
///  - never reduces a block below a single set (never recommends zero).
public enum SessionScaler {

    public static func scale(_ session: PlannedSession, by multiplier: Double) -> ScaledSession {
        // Defensive clamp: the engine already bounds this, but the scaler must
        // not trust its caller to never push beyond planned volume.
        let m = min(1.0, max(0.0, multiplier))

        var adjusted = false
        let scaledBlocks = session.blocks.map { block -> TrainingBlock in
            let scaledSets = max(1, Int((Double(block.sets) * m).rounded()))
            if scaledSets != block.sets { adjusted = true }
            return TrainingBlock(
                name: block.name,
                sets: scaledSets,
                distanceMeters: block.distanceMeters,
                durationSeconds: block.durationSeconds)
        }

        return ScaledSession(
            title: session.title,
            blocks: scaledBlocks,
            multiplier: m,
            wasAdjusted: adjusted)
    }
}
