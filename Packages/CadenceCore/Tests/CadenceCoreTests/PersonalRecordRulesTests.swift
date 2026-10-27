import XCTest
@testable import CadenceCore

final class PersonalRecordRulesTests: XCTestCase {
    func testFirstEverTimeIsAlwaysAPR() {
        XCTAssertTrue(PersonalRecordRules.isImprovement(new: 7.2, over: nil))
    }
    func testFasterTimeIsAPR() {
        XCTAssertTrue(PersonalRecordRules.isImprovement(new: 6.9, over: 7.2))
    }
    func testSlowerOrEqualIsNotAPR() {
        XCTAssertFalse(PersonalRecordRules.isImprovement(new: 7.5, over: 7.2))
        XCTAssertFalse(PersonalRecordRules.isImprovement(new: 7.2, over: 7.2))
    }
}
