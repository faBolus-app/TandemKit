import XCTest
@testable import TandemLoopKit

final class NoticeTests: XCTestCase {
    func testNoticeStatesNotForRealInsulin() {
        let notice = TandemLoopKitNotice.text
        XCTAssertTrue(notice.contains("NOT for use with real insulin"))
        XCTAssertTrue(notice.contains("saline"))
        // The pump-is-authority safety thesis must be stated in the shipped notice.
        XCTAssertTrue(notice.contains("sole authority"))
    }
}
