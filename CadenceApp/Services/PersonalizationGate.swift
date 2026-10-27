import Foundation
import CadenceCore

/// Loads the bundled adjustment-ranges file and gates the whole personalization
/// feature behind an off-by-default flag. This is a DRAFT dev/test feature for
/// known testers; the flag makes it trivial to disable later.
enum PersonalizationGate {

    private static let flagKey = "personalization.draftEnabled"

    /// Off by default — testers opt in via Settings.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: flagKey) }
        set { UserDefaults.standard.set(newValue, forKey: flagKey) }
    }

    /// The bundled ranges (decoded once). nil only if the resource is missing/corrupt.
    static let ranges: AdjustmentRanges? = {
        guard let url = Bundle.main.url(forResource: "adjustment_ranges", withExtension: "json") else {
            assertionFailure("adjustment_ranges.json missing from bundle"); return nil
        }
        do { return try JSONDecoder().decode(AdjustmentRanges.self, from: try Data(contentsOf: url)) }
        catch { assertionFailure("Failed to decode adjustment_ranges.json: \(error)"); return nil }
    }()

    /// True when the feature is enabled, the ranges loaded, AND the athlete's
    /// event actually has a profile (e.g. 800m has none → stays off).
    static func isAvailable(for event: Event) -> Bool {
        isEnabled && ranges?.profile(for: event.rawValue) != nil
    }

    /// Whether the loaded ranges are still a coach-review draft (drives the label).
    static var isDraft: Bool { ranges?.meta.isDraft ?? true }
}
