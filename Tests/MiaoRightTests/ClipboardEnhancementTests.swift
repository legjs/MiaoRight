import AppKit
import ImageIO
@testable import MiaoRightKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ClipboardEnhancementTests: XCTestCase {
    func testTemporaryPasteRestoresAllRepresentations() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("https://example.com", forType: .string)
        original.setString("<b>example</b>", forType: .html)
        XCTAssertTrue(board.writeObjects([original]))
        var writes: [Int] = []

        let posted = await ClipboardTemporaryPaste.paste(.text("Earlier title"), on: board, observeWrite: {
            writes.append($0)
        }, pause: {}) {
            XCTAssertEqual(board.string(forType: .string), "Earlier title")
            return true
        }

        XCTAssertTrue(posted)
        XCTAssertEqual(board.string(forType: .string), "https://example.com")
        XCTAssertEqual(board.string(forType: .html), "<b>example</b>")
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.last, board.changeCount)
    }

    func testTemporaryPasteKeepsAConcurrentCopy() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Original", forType: .string)
        var writes: [Int] = []
        let posted = await ClipboardTemporaryPaste.paste(.text("Earlier title"), on: board, observeWrite: {
            writes.append($0)
        }, pause: {
            board.clearContents()
            board.setString("New copy", forType: .string)
        }) { true }

        XCTAssertTrue(posted)
        XCTAssertEqual(board.string(forType: .string), "New copy")
        XCTAssertEqual(writes.count, 1)
        XCTAssertNotEqual(writes.last, board.changeCount)
    }

    func testTemporaryPasteDoesNotReplaceConcealedClipboard() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("Concealed test value", forType: .string)
        original.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        XCTAssertTrue(board.writeObjects([original]))
        let originalVersion = board.changeCount

        let posted = await ClipboardTemporaryPaste.paste(.text("Earlier title"), on: board, observeWrite: { _ in
            XCTFail("The protected clipboard was changed")
        }, pause: {}) {
            XCTFail("A paste event was posted")
            return true
        }

        XCTAssertFalse(posted)
        XCTAssertEqual(board.changeCount, originalVersion)
    }

    func testClipboardImageExportsFromHistoryAsPNGAndSupportsOCR() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = NSImage(size: NSSize(width: 800, height: 180), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            ("Permission denied" as NSString).draw(at: NSPoint(x: 32, y: 48), withAttributes: [
                .font: NSFont.systemFont(ofSize: 64, weight: .regular),
                .foregroundColor: NSColor.black
            ])
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let item = ClipboardItem(kind: .image, content: "export-test-\(UUID().uuidString).png")
        XCTAssertTrue(ClipboardStore.shared.saveOriginal(tiff, name: item.content))
        defer { ClipboardStore.shared.removeThumbFiles(name: item.content) }
        let payload = try XCTUnwrap(ClipboardHistoryService.shared.payload(for: item))
        let export = try ClipboardExport(payload: payload)
        let output = folder.appendingPathComponent("Selected Clipboard Image.png")
        try export.write(to: output)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        let text = try NativeActionExecutor.recognizeText(in: output, languages: ["zh-Hans", "zh-Hant", "en-US"])
        XCTAssertTrue(text.joined(separator: " ").localizedCaseInsensitiveContains("permission denied"))
        XCTAssertEqual(ClipboardStore.shared.originalData(name: item.content), tiff)
    }

    func testClipboardTextExportsAsUTF8() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: output) }
        let content = "两行文字\nhttps://example.com"
        let item = ClipboardItem(kind: .text, content: content)
        let payload = try XCTUnwrap(ClipboardHistoryService.shared.payload(for: item))
        let export = try ClipboardExport(payload: payload)
        guard case let .document(_, type, _) = export else { return XCTFail("Expected a document") }
        XCTAssertEqual(type.preferredFilenameExtension, "txt")
        try export.write(to: output)
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), content)
    }

    func testClipboardFilesKeepOriginalsAndUseUniqueNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceFolder = root.appendingPathComponent("资料", isDirectory: true)
        let destination = root.appendingPathComponent("导出", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("名字 有空格.txt")
        let contents = Data("source".utf8)
        try contents.write(to: file)
        try contents.write(to: sourceFolder.appendingPathComponent("笔记.txt"))
        let existing = destination.appendingPathComponent(file.lastPathComponent)
        try Data("existing".utf8).write(to: existing)
        let item = ClipboardItem(kind: .files, content: [file.path, sourceFolder.path].joined(separator: "\n"))
        let payload = try XCTUnwrap(ClipboardHistoryService.shared.payload(for: item))
        let export = try ClipboardExport(payload: payload)

        try export.write(to: destination)

        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("名字 有空格 2.txt")), contents)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("资料/笔记.txt")), contents)
        XCTAssertEqual(try Data(contentsOf: file), contents)
        XCTAssertThrowsError(try export.write(to: sourceFolder))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFolder.appendingPathComponent(file.lastPathComponent).path))
    }

    func testClipboardFileExportChecksMissingSourcesBeforeCopying() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Existing.txt")
        try Data("source".utf8).write(to: source)
        let missing = folder.appendingPathComponent("Missing.txt")
        let export = try ClipboardExport(payload: .files([source, missing]))

        XCTAssertThrowsError(try export.write(to: destination))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }
}
