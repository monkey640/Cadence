import Foundation
import CadenceCore

/// Loads the bundled, hand-authored `plans.json` once and caches it.
/// Static vetted data — never generated on-device.
enum PlanLibraryLoader {
    /// Decoded once, lazily. `nil` only if the resource is missing/corrupt.
    static let shared: PlanLibrary? = load()

    private static func load() -> PlanLibrary? {
        guard let url = Bundle.main.url(forResource: "plans", withExtension: "json") else {
            assertionFailure("plans.json missing from bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PlanLibrary.self, from: data)
        } catch {
            assertionFailure("Failed to decode plans.json: \(error)")
            return nil
        }
    }

    /// The template for an event, or nil if none exists (e.g. Hurdles/Relay).
    static func template(for event: Event) -> PlanTemplate? {
        shared?.templates.first { $0.event == event.rawValue }
    }

    /// Events we can actually put a vetted 12-week plan behind — derived from
    /// `plans.json`, never hardcoded, so the menu grows by itself the day a real
    /// Hurdles or Relay template lands in the file. Falls back to every event if
    /// the library failed to load, so a bad bundle can't leave the picker empty.
    static let plannedEvents: [Event] = {
        let planned = Event.allCases.filter { template(for: $0) != nil }
        return planned.isEmpty ? Event.allCases : planned
    }()

    /// `plannedEvents`, plus `current` if the athlete already picked an event we
    /// have no plan for. An existing Hurdles athlete keeps seeing (and keeping)
    /// their choice instead of the picker silently rendering blank.
    static func selectableEvents(including current: Event) -> [Event] {
        plannedEvents.contains(current) ? plannedEvents : plannedEvents + [current]
    }
}
