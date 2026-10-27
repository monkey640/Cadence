import Foundation
import CadenceCore

/// Hardcoded, event-specific session templates. These are *content*, not
/// scoring logic, so they live in the app layer. The readiness multiplier
/// scales them via `CadenceCore.SessionScaler`.
///
/// Not a plan generator (out of MVP scope): we rotate through a small set by
/// weekday so the day's session varies through the week without scheduling.
enum SessionTemplates {

    static func todaysSession(for event: Event, on date: Date = .now) -> PlannedSession {
        let options = sessions(for: event)
        let weekday = Calendar.current.component(.weekday, from: date) // 1...7
        return options[weekday % options.count]
    }

    static func sessions(for event: Event) -> [PlannedSession] {
        switch event {
        case .sprint100, .relay:
            return [
                PlannedSession(title: "Acceleration", blocks: [
                    TrainingBlock(name: "30m start", sets: 8, distanceMeters: 30),
                    TrainingBlock(name: "flying 20m", sets: 4, distanceMeters: 20),
                ]),
                PlannedSession(title: "Max velocity", blocks: [
                    TrainingBlock(name: "60m sprint", sets: 6, distanceMeters: 60),
                    TrainingBlock(name: "40m build-up", sets: 4, distanceMeters: 40),
                ]),
                PlannedSession(title: "Speed endurance", blocks: [
                    TrainingBlock(name: "120m sprint", sets: 4, distanceMeters: 120),
                    TrainingBlock(name: "150m run", sets: 2, distanceMeters: 150),
                ]),
                PlannedSession(title: "Tempo", blocks: [
                    TrainingBlock(name: "100m stride", sets: 8, distanceMeters: 100),
                ]),
            ]
        case .sprint200:
            return [
                PlannedSession(title: "Speed", blocks: [
                    TrainingBlock(name: "60m sprint", sets: 6, distanceMeters: 60),
                    TrainingBlock(name: "flying 30m", sets: 4, distanceMeters: 30),
                ]),
                PlannedSession(title: "Speed endurance", blocks: [
                    TrainingBlock(name: "150m sprint", sets: 4, distanceMeters: 150),
                    TrainingBlock(name: "200m run", sets: 2, distanceMeters: 200),
                ]),
                PlannedSession(title: "Special endurance", blocks: [
                    TrainingBlock(name: "250m run", sets: 3, distanceMeters: 250),
                ]),
                PlannedSession(title: "Tempo", blocks: [
                    TrainingBlock(name: "120m stride", sets: 8, distanceMeters: 120),
                ]),
            ]
        case .sprint400:
            return [
                PlannedSession(title: "Speed endurance", blocks: [
                    TrainingBlock(name: "200m sprint", sets: 4, distanceMeters: 200),
                ]),
                PlannedSession(title: "Special endurance", blocks: [
                    TrainingBlock(name: "300m run", sets: 3, distanceMeters: 300),
                    TrainingBlock(name: "150m run", sets: 2, distanceMeters: 150),
                ]),
                PlannedSession(title: "Speed", blocks: [
                    TrainingBlock(name: "60m sprint", sets: 6, distanceMeters: 60),
                ]),
                PlannedSession(title: "Tempo", blocks: [
                    TrainingBlock(name: "200m stride", sets: 6, distanceMeters: 200),
                ]),
            ]
        case .hurdles:
            return [
                PlannedSession(title: "Hurdle rhythm", blocks: [
                    TrainingBlock(name: "5-hurdle run", sets: 6, distanceMeters: 50),
                    TrainingBlock(name: "hurdle mobility", sets: 3),
                ]),
                PlannedSession(title: "Acceleration", blocks: [
                    TrainingBlock(name: "3-hurdle start", sets: 8, distanceMeters: 30),
                ]),
                PlannedSession(title: "Speed endurance", blocks: [
                    TrainingBlock(name: "8-hurdle run", sets: 4, distanceMeters: 90),
                ]),
                PlannedSession(title: "Tempo", blocks: [
                    TrainingBlock(name: "100m stride", sets: 8, distanceMeters: 100),
                ]),
            ]
        }
    }
}
