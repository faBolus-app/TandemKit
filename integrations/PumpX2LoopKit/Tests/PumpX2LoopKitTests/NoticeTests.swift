import XCTest
@testable import PumpX2LoopKit

final class NoticeTests: XCTestCase {
    func testNoticeStatesNotForRealInsulin() {
        let notice = PumpX2LoopKitNotice.text
        XCTAssertTrue(notice.contains("NOT for use with real insulin"))
        XCTAssertTrue(notice.contains("saline"))
        // The pump-is-authority safety thesis must be stated in the shipped notice.
        XCTAssertTrue(notice.contains("sole authority"))
    }
}
