import SwiftData

/// Single source of truth for the SwiftData schema, shared by the app's
/// `ModelContainer` and the background morning-check task (which opens the same
/// on-device store).
enum AppSchema {
    static let schema = Schema([
        AthleteProfile.self,
        TrainingSession.self,
        SessionSet.self,
        DailyReadiness.self,
        PersonalRecord.self,
        CheckIn.self,
        PlanAdjustment.self,
    ])
}
