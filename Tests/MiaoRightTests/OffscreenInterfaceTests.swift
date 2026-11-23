import AppKit
import MiaoRightShared
import SwiftUI
import XCTest
@testable import MiaoRightKit

@MainActor
final class OffscreenInterfaceTests: XCTestCase {
    func testNewInterfacesRenderWithoutVisibleOrActiveWindows() async throws {
        XCTAssertTrue(AppGroup.isIsolated)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-Offscreen-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let artifacts = ProcessInfo.processInfo.environment["MIAORIGHT_OFFSCREEN_ARTIFACTS"].map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("captures")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let originalLanguage = AppLanguage(rawValue: AppGroup.userDefaults?.string(forKey: L10n.storageKey) ?? "") ?? .system
        let store = ScriptStore.shared
        store.loadIfNeeded()
        let oldIDs = Set(store.scripts.map(\.id))
        let folder = root.appendingPathComponent("项目资料 Project Files", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try QuickFilePreferences.addFolder(folder, store: store)
        let quote = root.appendingPathComponent("报价单 Quote.txt")
        try Data("Example template".utf8).write(to: quote)
        try QuickFilePreferences.addTemplate(quote, store: store)
        let other = root.appendingPathComponent("Report.txt")
        try Data("Example report".utf8).write(to: other)
        let conflict = root.appendingPathComponent("new-Report.txt")
        try Data("Existing file".utf8).write(to: conflict)
        defer {
            for script in store.scripts where !oldIDs.contains(script.id) { store.deleteScript(script) }
            L10n.setLanguage(originalLanguage)
            try? FileManager.default.removeItem(at: root)
        }

        func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat, language: AppLanguage, dark: Bool) async throws {
            L10n.setLanguage(language)
            let window = NSWindow(contentRect: NSRect(x: -12000, y: -12000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let content = view.environment(\.colorScheme, dark ? .dark : .light).environment(store)
                .defaultAppStorage(AppGroup.standardDefaults).frame(width: width, height: height)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: content)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(window.isKeyWindow)
            XCTAssertFalse(NSApp.isActive)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 3000, "A blank render is not a useful interface check")
            try png.write(to: artifacts.appendingPathComponent(name + ".png"))
            window.close()
        }

        try await render(ScrollView { QuickFilePreferencesView(initiallyExpanded: true).padding(28) }, name: "quick-files-zh-light", width: 780, height: 600, language: .zhHans, dark: false)
        try await render(ScrollView { QuickFilePreferencesView(initiallyExpanded: true).padding(28) }, name: "quick-files-en-dark-min", width: 680, height: 540, language: .english, dark: true)
        let compression = FileTaskPresentation.Request(kind: .compress, urls: [quote, other])
        try await render(FileTaskView(request: compression), name: "compress-en-dark-min", width: 680, height: 540, language: .english, dark: true)
        let rename = FileTaskPresentation.Request(kind: .rename, urls: [other])
        try await render(FileTaskView(request: rename, initialRule: .init(mode: .affixes, prefix: "new-")), name: "rename-conflict-zh-light", width: 780, height: 600, language: .zhHans, dark: false)

        let history = ClipboardHistoryService.shared
        let previousClipPath = ProcessInfo.processInfo.environment["MIAORIGHT_CLIPBOARD_TEST_STORAGE"]
        defer {
            if let previousClipPath { setenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE", previousClipPath, 1) } else { unsetenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE") }
            history.reloadStorage()
        }
        setenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE", root.appendingPathComponent("clipboard").path, 1)
        history.reloadStorage()
        XCTAssertTrue(history.addFavoriteText("hello@example.test"))
        XCTAssertTrue(history.addFavoriteText("这是一段常用回复。This is an example reply."))
        let clipboard = ClipboardPanelContent(service: history, onClose: {}, onUse: {}, onSearchFocusChanged: { _ in }, favoritesOnly: true)
        try await render(clipboard, name: "clipboard-favorites-zh-light", width: 320, height: 600, language: .zhHans, dark: false)
        try await render(clipboard, name: "clipboard-favorites-en-dark", width: 320, height: 600, language: .english, dark: true)
        if let previousClipPath { setenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE", previousClipPath, 1) } else { unsetenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE") }
        history.reloadStorage()

        let moved = root.appendingPathComponent("Moved Report.txt"), id = UUID()
        let result = try FileTaskContext.$executionID.withValue(id) { () -> ScriptExecutionResult in
            _ = try FileOperationJournal.shared.perform([FileMove(source: other, destination: moved)], title: "移动")
            return .success(scriptName: "移动到…", output: moved.path, outputPaths: [moved.path], undoID: FileOperationJournal.shared.summary(for: id).undoID)
        }
        try await render(FileOperationResultView(result: result), name: "result-undo-en-dark", width: 680, height: 240, language: .english, dark: true)
    }
}
