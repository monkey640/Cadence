import Foundation

/// A neutral, framework-free representation of a training session, so the
/// scaler can operate without depending on the app's SwiftData models or its
/// template catalog. The app maps its content to/from these value types.
public struct PlannedSession: Equatable, Sendable {
    public let title: String
    public let blocks: [TrainingBlock]

    public init(title: String, blocks: [TrainingBlock]) {
        self.title = title
        self.blocks = blocks
    }
}

public struct TrainingBlock: Equatable, Sendable {
    public let name: String          // e.g. "60m sprints", "Tempo 1000m"
    public let sets: Int             // number of sets/reps of the effort
    public let distanceMeters: Double?
    public let durationSeconds: Double?

    public init(name: String, sets: Int, distanceMeters: Double? = nil, durationSeconds: Double? = nil) {
        self.name = name
        self.sets = sets
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}

/// The result of scaling a `PlannedSession` by a readiness multiplier.
public struct ScaledSession: Equatable, Sendable {
    public let title: String
    public let blocks: [TrainingBlock]
    public let multiplier: Double
    /// True when scaling actually reduced volume — drives the "Adjusted today" callout.
    public let wasAdjusted: Bool

    public init(title: String, blocks: [TrainingBlock], multiplier: Double, wasAdjusted: Bool) {
        self.title = title
        self.blocks = blocks
        self.multiplier = multiplier
        self.wasAdjusted = wasAdjusted
    }
}
