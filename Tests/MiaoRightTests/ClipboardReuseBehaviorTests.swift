import MiaoRightShared
@testable import MiaoRightKit
import XCTest

final class ClipboardReuseBehaviorTests: XCTestCase {
    func testLabelsFollowPreferenceAndPermission() {
        XCTAssertEqual(ClipboardReuseBehavior.resolve(autoPaste: false, authorized: false), .copy)
        XCTAssertEqual(ClipboardReuseBehavior.resolve(autoPaste: false, authorized: true), .copy)
        XCTAssertEqual(ClipboardReuseBehavior.resolve(autoPaste: true, authorized: false), .copy)
        XCTAssertEqual(ClipboardReuseBehavior.resolve(autoPaste: true, authorized: true), .paste)
        XCTAssertEqual(ClipboardReuseBehavior.copy.menuTitle, L10n.text("复制", "Copy"))
        XCTAssertEqual(ClipboardReuseBehavior.paste.menuTitle, L10n.text("复制并粘贴", "Copy and Paste"))
        XCTAssertTrue(ClipboardReuseBehavior.copy.footer(pickedCount: 2).contains(L10n.text("合并复制", "merges & copies")))
        XCTAssertTrue(ClipboardReuseBehavior.paste.footer(pickedCount: 2).contains(L10n.text("合并粘贴", "merges & pastes")))
    }
}
