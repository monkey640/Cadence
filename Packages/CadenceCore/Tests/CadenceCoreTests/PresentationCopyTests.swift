import XCTest
@testable import CadenceCore

final class PresentationCopyTests: XCTestCase {

    private func output(mult: Double, hrv: Double?, sleep: Double?, rhr: Double?) -> ReadinessOutput {
        ReadinessOutput(score: 60, verdict: .hold, volumeMultiplier: mult, reason: "",
                        isBaselining: false, baselineSampleCount: 30,
                        components: ComponentScores(hrv: hrv, sleep: sleep, rhr: rhr, trainingLoad: 80))
    }

    // MARK: AdjustmentNote

    func testNoNoteWhenNotAdjusted() {
        XCTAssertNil(AdjustmentNote.text(for: output(mult: 1.0, hrv: 40, sleep: 40, rhr: 40)))
    }

    func testNoteNamesTheWorstSignal() {
        // HRV lowest → note mentions HRV and the real percentage.
        let note = AdjustmentNote.text(for: output(mult: 0.8, hrv: 30, sleep: 60, rhr: 65))
        XCTAssertNotNil(note)
        XCTAssertTrue(note!.contains("20%"))
        XCTAssertTrue(note!.localizedCaseInsensitiveContains("HRV"))
    }

    func testNoteFallsBackWhenNoClearDriver() {
        // All components healthy (>=50) but still trimmed (e.g. load) → generic note.
        let note = AdjustmentNote.text(for: output(mult: 0.9, hrv: 70, sleep: 70, rhr: 70))
        XCTAssertNotNil(note)
        XCTAssertTrue(note!.contains("10%"))
    }

    // MARK: WeeklyReport

    func testReturnsNilWithoutEnoughHistory() {
        XCTAssertNil(WeeklyReportBuilder.build(readinessThisWeek: [70], scaledMultipliers: [],
                                               hrvThisWeek: [], hrvPriorWeek: []))
    }

    func testCountsAndAveragesScaledSessions() {
        let r = WeeklyReportBuilder.build(
            readinessThisWeek: [72, 74, 73, 75],
            scaledMultipliers: [0.8, 0.7],          // 20% and 30% → avg 25%
            hrvThisWeek: [60, 61], hrvPriorWeek: [60, 60])
        XCTAssertEqual(r?.scaledSessions, 2)
        XCTAssertEqual(r?.avgReductionPct, 25)
    }

    func testReadinessTrendDirections() {
        XCTAssertEqual(WeeklyReportBuilder.build(readinessThisWeek: [50, 52, 70, 72],
            scaledMultipliers: [], hrvThisWeek: [], hrvPriorWeek: [])?.readinessTrend, .up)
        XCTAssertEqual(WeeklyReportBuilder.build(readinessThisWeek: [80, 78, 60, 58],
            scaledMultipliers: [], hrvThisWeek: [], hrvPriorWeek: [])?.readinessTrend, .down)
        XCTAssertEqual(WeeklyReportBuilder.build(readinessThisWeek: [70, 71, 70, 71],
            scaledMultipliers: [], hrvThisWeek: [], hrvPriorWeek: [])?.readinessTrend, .flat)
    }

    func testHRVBaselineTrend() {
        let up = WeeklyReportBuilder.build(readinessThisWeek: [70, 71],
            scaledMultipliers: [], hrvThisWeek: [70, 72], hrvPriorWeek: [60, 60])
        XCTAssertEqual(up?.hrvBaselineTrend, .up)
    }

    func testTakeawayIsNonEmptyCoachLine() {
        let r = WeeklyReportBuilder.build(readinessThisWeek: [60, 62, 74, 76],
            scaledMultipliers: [0.8], hrvThisWeek: [61, 62], hrvPriorWeek: [60, 60])
        XCTAssertFalse(r!.takeaway.isEmpty)
    }
}
