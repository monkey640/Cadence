import Foundation
import SwiftData
import CadenceCore

/// Applies PR detection when a session is completed: each block's logged best
/// time is compared (by distance) against the stored `PersonalRecord`, updating
/// the record and flagging the block when it's an improvement.
@MainActor
enum PersonalRecordTracker {

    /// Distance-based key, e.g. a 60m block → "60m".
    static func key(forDistance meters: Double) -> String { "\(Int(meters.rounded()))m" }

    static func apply(to session: TrainingSession, context: ModelContext) {
        for set in session.sets {
            guard let time = set.bestTimeSeconds, let distance = set.distanceMeters else {
                set.wasPR = false
                continue
            }
            let prKey = key(forDistance: distance)
            let descriptor = FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.key == prKey })
            let existing = try? context.fetch(descriptor).first

            if PersonalRecordRules.isImprovement(new: time, over: existing?.bestTimeSeconds) {
                set.wasPR = true
                set.previousBestSeconds = existing?.bestTimeSeconds
                if let existing {
                    existing.bestTimeSeconds = time
                    existing.achievedOn = session.date
                } else {
                    context.insert(PersonalRecord(key: prKey, bestTimeSeconds: time, achievedOn: session.date))
                }
            } else {
                set.wasPR = false
                set.previousBestSeconds = nil
            }
        }
        try? context.save()
    }
}
