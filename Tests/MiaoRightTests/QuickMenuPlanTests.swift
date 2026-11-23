import Foundation
import MiaoRightShared
import XCTest

final class QuickMenuPlanTests: XCTestCase {
    private func action(_ name: String, content: String = "") -> QuickMenuAction {
        .init(id: UUID(), name: name, icon: "app", content: content)
    }
    func testEveryEnabledActionIsReachableExactlyOnce() {
        let input = [action("保留的自定义操作"), action("在 VS Code 中打开"), action(ActionID.paste), action("复制路径"), action("在终端中打开"), action(ActionID.cut), action("彻底删除")]
        let sections = QuickMenuPlan.sections(for: input)
        let rendered = sections.flatMap(\.actions)
        XCTAssertEqual(Set(rendered.map(\.id)), Set(input.map(\.id)))
        XCTAssertEqual(rendered.count, input.count)
        XCTAssertEqual(sections.first?.actions.first?.name, "复制路径")
        XCTAssertEqual(sections.last?.actions.map(\.name), ["保留的自定义操作", "彻底删除"])
    }
    func testTerminalOrderDoesNotDependOnUsageOrInputOrder() {
        let sections = QuickMenuPlan.sections(for: [action("在 Warp 中打开"), action("在终端中打开"), action("在 iTerm2 中打开")])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].actions.map(\.name), QuickMenuPlan.terminalNames)
        XCTAssertNotNil(sections[0].title)
    }
    func testCustomApplicationSupportsSpacesAndQuotes() {
        let path = "/Applications/Example \"Editor\".app"
        let data = try! JSONSerialization.data(withJSONObject: ["steps": [["op": "file.openWith", "params": ["appPath": path]]]])
        let entry = action("用编辑器打开", content: String(data: data, encoding: .utf8)!)
        XCTAssertEqual(QuickMenuPlan.applicationPath(in: entry.content), path)
        XCTAssertTrue(QuickMenuPlan.isApplication(name: entry.name, content: entry.content))
        XCTAssertEqual(QuickMenuPlan.applicationTitle(entry), "Example \"Editor\"")
        XCTAssertNotNil(QuickMenuPlan.sections(for: [entry])[0].title)
    }
    func testMultiStepActionIsNotMistakenForApplicationShortcut() {
        let data = try! JSONSerialization.data(withJSONObject: ["steps": [
            ["op": "file.openWith", "params": ["appPath": "/Applications/Preview.app"]],
            ["op": "file.move", "params": ["folder": "/tmp/archive"]]
        ]])
        XCTAssertNil(QuickMenuPlan.applicationPath(in: String(data: data, encoding: .utf8)!))
        XCTAssertTrue(QuickMenuPlan.sections(for: []).isEmpty)
    }
}

extension QuickMenuPlanTests {
    func testMissingApplicationIsNotAdvertised() {
        let terminal = QuickMenuAction(id: UUID(), name: "在终端中打开", icon: "terminal")
        XCTAssertFalse(QuickMenuPlan.isAvailable(terminal, resolveBundleID: { _ in nil }))
        XCTAssertTrue(QuickMenuPlan.isAvailable(terminal, resolveBundleID: { _ in URL(fileURLWithPath: "/Applications/Terminal.app") }))
        let custom = QuickMenuAction(id: UUID(), name: "示例", icon: "app", content: "{\"steps\":[{\"op\":\"file.openWith\",\"params\":{\"appPath\":\"/nonexistent/Unavailable.app\"}}]}")
        XCTAssertFalse(QuickMenuPlan.isAvailable(custom, resolveBundleID: { _ in nil }))
    }
}
