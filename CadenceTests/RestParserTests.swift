import XCTest
@testable import Cadence

/// Every rest note in plans.json, with the seconds the rest timer should run.
/// The compound notes are the regression: the old parser averaged every number
/// in the string, so "30s / 3 min" became 16.5 minutes between tempo reps.
final class RestParserTests: XCTestCase {

    func testCompoundNotesUseTheBetweenRepsRest() {
        XCTAssertEqual(RestParser.seconds(from: "30s / 2-3 min"), 30)
        XCTAssertEqual(RestParser.seconds(from: "30s / 3 min"), 30)
        XCTAssertEqual(RestParser.seconds(from: "30s between reps / 2-3 min between sets"), 30)
    }

    func testSecondsNotes() {
        XCTAssertEqual(RestParser.seconds(from: "45s"), 45)
        XCTAssertEqual(RestParser.seconds(from: "60s"), 60)
        XCTAssertEqual(RestParser.seconds(from: "90 s"), 90)
    }

    func testMinuteNotesAndRanges() {
        XCTAssertEqual(RestParser.seconds(from: "3 min full"), 180)
        XCTAssertEqual(RestParser.seconds(from: "3-4 min full"), 210)
        XCTAssertEqual(RestParser.seconds(from: "10-12 min full"), 660)
        XCTAssertEqual(RestParser.seconds(from: "15-20 min full"), 1050)
    }

    func testNotesWithoutADurationFallBack() {
        XCTAssertNil(RestParser.seconds(from: "full"))
        XCTAssertNil(RestParser.seconds(from: nil))
        XCTAssertNil(RestParser.seconds(from: ""))
    }

    /// Guards the whole bundled library, not just the cases above: no rest in
    /// any plan should come out longer than the longest note actually written
    /// (20 min) or, for between-rep tempo work, longer than a few minutes.
    func testNoBundledRestIsAbsurd() throws {
        let library = try XCTUnwrap(PlanLibraryLoader.shared)
        var checked = 0
        for template in library.templates {
            for phase in template.phases {
                for day in phase.weeklyMicrocycle {
                        for block in day.blocks {
                            guard let seconds = RestParser.seconds(from: block.rest) else { continue }
                            checked += 1
                            XCTAssertLessThanOrEqual(seconds, 20 * 60,
                                "\(template.event) '\(block.name)' rest '\(block.rest ?? "")' parsed to \(seconds)s")
                            if block.rest?.contains("/") == true {
                                XCTAssertLessThanOrEqual(seconds, 180,
                                    "\(template.event) '\(block.name)' between-rep rest '\(block.rest ?? "")' parsed to \(seconds)s")
                            }
                        }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "no rest notes found — the plan walk is broken")
    }

    func testClockFormat() {
        XCTAssertEqual(SessionPlayerView.clock(0), "0:00")
        XCTAssertEqual(SessionPlayerView.clock(45), "0:45")
        XCTAssertEqual(SessionPlayerView.clock(90), "1:30")
        XCTAssertEqual(SessionPlayerView.clock(686), "11:26")
        XCTAssertEqual(SessionPlayerView.clock(-3), "0:00")
    }
}
