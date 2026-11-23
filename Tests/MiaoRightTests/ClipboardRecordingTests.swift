import AppKit
@testable import MiaoRightKit
import XCTest

@MainActor
final class ClipboardRecordingTests: XCTestCase {
    func testPauseAndRetentionUseIsolatedStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let previousPath = ProcessInfo.processInfo.environment["MIAORIGHT_CLIPBOARD_TEST_STORAGE"]
        setenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE", root.path, 1)
        let history = ClipboardHistoryService.shared
        let wasRecording = history.recordingEnabled
        let previousRetention = history.retentionDays
        history.setRecordingEnabled(false)
        history.reloadStorage()
        defer {
            if let previousPath { setenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE", previousPath, 1) }
            else { unsetenv("MIAORIGHT_CLIPBOARD_TEST_STORAGE") }
            history.reloadStorage()
            history.setRetentionDays(previousRetention)
            history.setRecordingEnabled(wasRecording)
            try? FileManager.default.removeItem(at: root)
        }
        history.setRetentionDays(0)
        let old = ClipboardItem(kind: .text, content: "Old sample", date: Date().addingTimeInterval(-45 * 86400))
        let recent = ClipboardItem(kind: .text, content: "Recent sample")
        ClipboardStore.shared.upsert(old)
        ClipboardStore.shared.upsert(recent)
        history.reloadStorage()
        XCTAssertEqual(history.items.count, 2)
        history.setRetentionDays(7)
        XCTAssertEqual(history.items.map(\.id), [recent.id])
        history.setRecordingEnabled(true)
        history.setRecordingEnabled(false)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(history.recordingEnabled)
        XCTAssertEqual(history.items.map(\.id), [recent.id])
    }
}
