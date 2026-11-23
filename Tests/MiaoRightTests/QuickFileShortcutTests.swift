import Foundation
import MiaoRightShared
import XCTest
@testable import MiaoRightKit

final class QuickFileShortcutTests: XCTestCase {
    func testShortcutRoundTripAndLegacyActionsStaySeparate() throws {
        let shortcut = QuickFileShortcut(kind: .copy, targetPath: "/tmp/中文 ' folder", title: "项目")
        XCTAssertEqual(QuickFileShortcut(content: shortcut.encoded()), shortcut)
        let action = try XCTUnwrap(ComposedAction.decode(shortcut.encoded()))
        XCTAssertEqual(action.steps.first?.op, "file.copy")
        XCTAssertNil(QuickFileShortcut(content: ComposedAction(steps: [.init(op: "file.copy", params: ["folder": "/tmp"])]).encoded()))
        XCTAssertNil(QuickFileShortcut(content: "{}"))
        let multiple = ComposedAction(steps: action.steps + action.steps).encoded()
        XCTAssertNil(QuickFileShortcut(content: multiple))
    }

    func testShortcutMenuGroupsKeepCoreOrderAndEveryAction() {
        let shortcuts = QuickFileShortcut.Kind.allCases.map { kind in
            QuickMenuAction(id: UUID(), name: "Saved action", icon: kind.icon, content: QuickFileShortcut(kind: kind, targetPath: "/tmp", title: "Project").encoded())
        }
        let core = QuickMenuAction(id: UUID(), name: "复制路径", icon: "link")
        let other = QuickMenuAction(id: UUID(), name: "Other", icon: "app")
        let plan = QuickMenuPlan.sections(for: shortcuts + [other, core])
        XCTAssertEqual(plan.first?.actions.map(\.id), [core.id])
        XCTAssertEqual(plan.dropFirst().dropLast().flatMap(\.actions).map(\.id), shortcuts.map(\.id))
        XCTAssertEqual(plan.last?.actions.map(\.id), [other.id])
        XCTAssertEqual(QuickMenuPlan.title(shortcuts[0]), "Project")
        let unavailable = QuickMenuAction(id: UUID(), name: "Missing", icon: "folder", content: QuickFileShortcut(kind: .openFolder, targetPath: "/nonexistent/\(UUID())", title: "Missing").encoded())
        XCTAssertFalse(QuickMenuPlan.isAvailable(unavailable, resolveBundleID: { _ in nil }))
    }
}

@MainActor
final class QuickFilePreferencesTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-QuickFiles-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testFavoriteFoldersKeepThreeIndependentActionsAndConfirmMoves() throws {
        XCTAssertTrue(AppGroup.isIsolated)
        let store = ScriptStore.shared
        store.loadIfNeeded()
        let root = try directory()
        try QuickFilePreferences.addFolder(root, store: store)
        let folder = try XCTUnwrap(QuickFilePreferences.folders(in: store).first { $0.url == root })
        defer { QuickFilePreferences.removeFolder(folder, store: store) }
        XCTAssertEqual(folder.actions.count, 3)
        XCTAssertTrue(try XCTUnwrap(folder.actions[.move]).confirmBeforeRun)
        XCTAssertTrue(ComposedAction.decode(try XCTUnwrap(folder.actions[.move]).content)?.destructiveStepTitles.isEmpty == false)
        try QuickFilePreferences.addFolder(root, store: store)
        XCTAssertEqual(QuickFilePreferences.folders(in: store).filter { $0.url == root }.count, 1)
        for script in folder.actions.values { XCTAssertTrue(QuickAccessPreferences.isCore(script)) }
    }

    func testTemplateSnapshotAndNewCopiesKeepOriginalData() throws {
        let store = ScriptStore.shared
        store.loadIfNeeded()
        let root = try directory()
        let source = root.appendingPathComponent("报价单.txt")
        try Data("Template version 1".utf8).write(to: source)
        let oldIDs = Set(store.scripts.map(\.id))
        try QuickFilePreferences.addTemplate(source, store: store)
        let script = try XCTUnwrap(QuickFilePreferences.templates(in: store).first { !oldIDs.contains($0.id) })
        defer { QuickFilePreferences.removeTemplate(script, store: store) }
        let shortcut = try XCTUnwrap(QuickFileShortcut(content: script.content))
        let snapshot = URL(fileURLWithPath: shortcut.targetPath)
        XCTAssertTrue(snapshot.path.hasPrefix(QuickFilePreferences.templateRoot().path))
        try Data("Source changed".utf8).write(to: source)
        let first = try QuickFileOperations.createFromTemplate(snapshot, in: root)
        let second = try QuickFileOperations.createFromTemplate(snapshot, in: root)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, source)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "Template version 1")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "Source changed")
        XCTAssertEqual(try String(contentsOf: snapshot, encoding: .utf8), "Template version 1")
    }
}
