import XCTest
@testable import CadenceCore

final class PlanSchedulerTests: XCTestCase {

    private func block(reps: Int?, distance: Int?) -> PlanBlock {
        PlanBlock(name: "Accelerations", type: reps == nil ? nil : .accel,
                  sets: reps == nil ? nil : 1, reps: reps, distanceM: distance,
                  rest: nil, target: nil, detail: reps == nil ? "20 min" : nil)
    }

    private func makeTemplate() -> PlanTemplate {
        let d1 = PlanDay(day: 1, load: .high, name: "Acceleration",
                         blocks: [block(reps: nil, distance: nil), block(reps: 6, distance: 30)])
        let d7 = PlanDay(day: 7, load: .rest, name: "Rest", blocks: [block(reps: nil, distance: nil)])
        return PlanTemplate(id: "t", event: "100m", durationWeeks: 12,
            primaryQualities: [], secondaryQualities: [], summary: "",
            phases: [
                PlanPhase(name: "GPP", weeks: "1-3", rationale: "", progression: "", weeklyMicrocycle: [d1, d7]),
                PlanPhase(name: "SPP", weeks: "4-7", rationale: "", progression: "", weeklyMicrocycle: [d1, d7]),
            ])
    }

    func testWeekRangeParsing() {
        XCTAssertEqual(PlanScheduler.weekRange("1-3"), 1...3)
        XCTAssertEqual(PlanScheduler.weekRange("8-10"), 8...10)
        XCTAssertNil(PlanScheduler.weekRange("nope"))
        XCTAssertNil(PlanScheduler.weekRange("5-2"))   // reversed
    }

    func testSelectsCorrectPhaseAndDay() {
        let t = makeTemplate()
        XCTAssertEqual(PlanScheduler.selectDay(in: t, week: 1, dayInWeek: 1)?.phase.name, "GPP")
        XCTAssertEqual(PlanScheduler.selectDay(in: t, week: 5, dayInWeek: 1)?.phase.name, "SPP")
        XCTAssertEqual(PlanScheduler.selectDay(in: t, week: 1, dayInWeek: 7)?.day.load, .rest)
    }

    func testPastPlanReturnsNil() {
        XCTAssertNil(PlanScheduler.selectDay(in: makeTemplate(), week: 13, dayInWeek: 1))
    }

    func testScalableSessionUsesOnlyTrackwork() {
        let day = PlanScheduler.selectDay(in: makeTemplate(), week: 1, dayInWeek: 1)!.day
        XCTAssertEqual(day.trackworkBlocks.count, 1)
        XCTAssertEqual(day.descriptiveBlocks.count, 1)
        let session = day.scalableSession()
        XCTAssertEqual(session.blocks.count, 1)
        XCTAssertEqual(session.blocks[0].sets, 6)            // reps → sets
        XCTAssertEqual(session.blocks[0].distanceMeters, 30)
        XCTAssertEqual(session.blocks[0].name, "Accelerations — 30m")
    }
}
