import XCTest
@testable import CadenceCore

final class SessionScalerTests: XCTestCase {

    private let session = PlannedSession(title: "Sprint day", blocks: [
        TrainingBlock(name: "60m sprints", sets: 6, distanceMeters: 60),
        TrainingBlock(name: "120m strides", sets: 4, distanceMeters: 120),
    ])

    func testFullMultiplierLeavesSessionUnchanged() {
        let scaled = SessionScaler.scale(session, by: 1.0)
        XCTAssertFalse(scaled.wasAdjusted)
        XCTAssertEqual(scaled.blocks.map(\.sets), [6, 4])
    }

    func testHalfMultiplierHalvesVolume() {
        let scaled = SessionScaler.scale(session, by: 0.5)
        XCTAssertTrue(scaled.wasAdjusted)
        XCTAssertEqual(scaled.blocks.map(\.sets), [3, 2])
    }

    func testNeverReducesBelowOneSet() {
        let tiny = PlannedSession(title: "x", blocks: [TrainingBlock(name: "single", sets: 1)])
        let scaled = SessionScaler.scale(tiny, by: 0.5)
        XCTAssertEqual(scaled.blocks[0].sets, 1, "never recommend zero")
    }

    func testNeverExceedsPlannedEvenIfMultiplierAboveOne() {
        let scaled = SessionScaler.scale(session, by: 1.5)  // defensive: should clamp to 1.0
        XCTAssertEqual(scaled.blocks.map(\.sets), [6, 4])
        XCTAssertFalse(scaled.wasAdjusted)
    }

    func testPreservesDistanceMetadata() {
        let scaled = SessionScaler.scale(session, by: 0.75)
        XCTAssertEqual(scaled.blocks[0].distanceMeters, 60)
    }
}
