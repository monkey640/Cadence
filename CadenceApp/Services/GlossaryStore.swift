import Foundation
import CadenceCore

/// Loads the bundled movement glossary once. `entry(for:)` returns nil when a
/// block has no matching movement — callers then fall back to the plan's own
/// detail and omit the glossary expander (never invent a description).
enum GlossaryStore {
    static let shared: MovementGlossary? = {
        guard let url = Bundle.main.url(forResource: "movement_glossary", withExtension: "json") else {
            assertionFailure("movement_glossary.json missing from bundle"); return nil
        }
        do { return try JSONDecoder().decode(MovementGlossary.self, from: try Data(contentsOf: url)) }
        catch { assertionFailure("Failed to decode movement_glossary.json: \(error)"); return nil }
    }()

    static func entry(for movementID: String?) -> MovementEntry? {
        guard let movementID else { return nil }
        return shared?.entry(id: movementID)
    }
}
