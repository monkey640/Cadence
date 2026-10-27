import XCTest
import CadenceCore
@testable import Cadence

/// Guards the rule that the event picker only ever offers events we can put a
/// real vetted plan behind — and that an athlete who already chose an unplanned
/// event (Hurdles/Relay, offered before the plans shipped) keeps their choice.
final class PlanLibraryLoaderTests: XCTestCase {

    func testPlannedEventsOnlyIncludesEventsWithATemplate() {
        let planned = PlanLibraryLoader.plannedEvents
        XCTAssertFalse(planned.isEmpty, "plans.json failed to load from the test bundle")
        for event in planned {
            XCTAssertNotNil(PlanLibraryLoader.template(for: event),
                            "\(event.rawValue) is offered in the picker but has no template")
        }
        for event in Event.allCases where !planned.contains(event) {
            XCTAssertNil(PlanLibraryLoader.template(for: event),
                         "\(event.rawValue) has a template but isn't offered in the picker")
        }
    }

    /// The migration case: existing Hurdles/Relay profiles must still render in
    /// the Settings picker, or SwiftUI shows a blank selection.
    func testSelectableEventsAlwaysContainsTheCurrentEvent() {
        for event in Event.allCases {
            XCTAssertTrue(PlanLibraryLoader.selectableEvents(including: event).contains(event),
                          "\(event.rawValue) would render blank in the Settings picker")
        }
    }

    /// An unplanned current event is appended, not substituted — the athlete can
    /// still switch to any planned event from Settings.
    func testUnplannedCurrentEventIsAppendedToThePlannedOnes() throws {
        let unplanned = try XCTUnwrap(
            Event.allCases.first { PlanLibraryLoader.template(for: $0) == nil },
            "no unplanned event left to test — every event now has a plan, delete this test")
        let options = PlanLibraryLoader.selectableEvents(including: unplanned)
        XCTAssertEqual(options.count, PlanLibraryLoader.plannedEvents.count + 1)
        XCTAssertEqual(options.last, unplanned)
    }
}
