import Foundation
import SwiftData
import CadenceCore

/// Bridges logged SwiftData sessions → CadenceCore `SessionObservation`s for the
/// personalization engine. Thin and dormant: nothing calls it from the UI yet
/// (engine→UI hookup is deferred). It exists so the engine *can read* the new
/// fade marker + stress flag once we choose to surface proposals.
@MainActor
enum PersonalizationInputs {

    /// Build detection observations from logged sessions (any order; sorted here).
    /// - lowReadinessDays: start-of-day dates the readiness verdict was "back off".
    static func observations(
        from sessions: [TrainingSession],
        profile: EventAdjustmentProfile,
        lowReadinessDays: Set<Date>
    ) -> [SessionObservation] {
        sessions.sorted { $0.date < $1.date }.map { session in
            let fadedEndurance: Set<Quality> = Set(session.sets.compactMap { set in
                guard set.fadeMarker == .faded,
                      let quality = set.qualityRaw.flatMap(Quality.init(rawValue:)),
                      quality.isEndurance else { return nil }
                return quality
            })
            let completedAll = session.sets.allSatisfy { $0.completedSets >= $0.plannedSets }
            let day = Calendar.current.startOfDay(for: session.date)

            return DeficiencySignalMapper.observation(
                profile: profile,
                phaseName: session.title,
                isLowReadiness: lowReadinessDays.contains(day),
                flaggedExternalStress: session.flaggedExternalStress,
                completedPrescribedReps: completedAll,
                fadedEnduranceQualities: fadedEndurance)
        }
    }
}
