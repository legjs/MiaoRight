import XCTest
@testable import MiaoRightKit

final class ReleaseNotesParserTests: XCTestCase {
    private let notes = """
    ## 中文

    ### 新增
    - 新增双语更新说明。

    ### 修复
    - 修复重复窗口。

    ## English

    ### Added
    - Added bilingual release notes.

    ### Fixed
    - Fixed duplicate windows.
    """

    func testChineseSectionOnly() {
        let blocks = ReleaseNotesParser.blocks(from: notes, english: false)
        XCTAssertEqual(blocks.filter { $0.kind == .heading }.map(\.text), ["新增", "修复"])
        XCTAssertEqual(blocks.filter { $0.kind == .bullet }.map(\.text), ["新增双语更新说明。", "修复重复窗口。"])
    }

    func testEnglishSectionOnly() {
        let blocks = ReleaseNotesParser.blocks(from: notes, english: true)
        XCTAssertEqual(blocks.filter { $0.kind == .heading }.map(\.text), ["Added", "Fixed"])
        XCTAssertEqual(blocks.filter { $0.kind == .bullet }.map(\.text), ["Added bilingual release notes.", "Fixed duplicate windows."])
    }
}
