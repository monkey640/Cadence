import XCTest
@testable import CadenceCore

final class NotificationGateTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testDeliversWhenNeverDeliveredBefore() {
        XCTAssertTrue(NotificationGate.shouldDeliver(now: date(2026, 6, 16, 7), lastDelivered: nil, calendar: cal))
    }

    func testBlocksSecondDeliverySameDay() {
        let morning = date(2026, 6, 16, 7)
        let laterSameDay = date(2026, 6, 16, 11)
        XCTAssertFalse(NotificationGate.shouldDeliver(now: laterSameDay, lastDelivered: morning, calendar: cal))
    }

    func testDeliversNextDay() {
        let yesterday = date(2026, 6, 16, 7)
        let today = date(2026, 6, 17, 7)
        XCTAssertTrue(NotificationGate.shouldDeliver(now: today, lastDelivered: yesterday, calendar: cal))
    }
}
