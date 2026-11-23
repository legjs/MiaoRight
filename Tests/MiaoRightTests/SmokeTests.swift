@testable import MiaoRightKit
@testable import MiaoRightShared
import XCTest

// 冒烟测试:内置动作库与共享模型的完整性
final class SmokeTests: XCTestCase {
    func testLibraryScriptNamesAreUnique() {
        let names = ScriptLibrary.allScripts.map(\.name)
        let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        XCTAssertTrue(duplicates.isEmpty, "动作名重复:\(duplicates)")
    }

    func testDefaultEnabledActionsExistInLibrary() {
        let names = Set(ScriptLibrary.allScripts.map(\.name))
        let missing = ScriptLibrary.defaultEnabledActions.subtracting(names)
        XCTAssertTrue(missing.isEmpty, "默认开启的动作不在动作库中:\(missing)")
    }

    func testScriptCategoryMatchesBuiltInMenuCategory() {
        XCTAssertEqual(
            Set(ScriptLibrary.ScriptCategory.allCases.map(\.rawValue)),
            Set(BuiltInMenuCategory.allCases.map(\.rawValue))
        )
    }

    func testActionIDsMatchLibrary() {
        let names = Set(ScriptLibrary.allScripts.map(\.name))
        [ActionID.cut, ActionID.paste, "移动到…", "复制到…", ActionID.airdrop, ActionID.deletePermanently]
            .forEach { XCTAssertTrue(names.contains($0), "缺少顶层动作:\($0)") }
    }
}
