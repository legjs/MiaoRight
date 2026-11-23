import AppKit
import ImageIO

enum ClipboardPayload: Sendable {
    case text(String)
    case files([URL])
    case image(Data)

    func write(to board: NSPasteboard) -> Bool {
        switch self {
        case let .text(text):
            return board.setString(text, forType: .string)
        case let .files(urls):
            return board.writeObjects(urls as [NSURL])
        case let .image(data):
            let imageType = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
            return board.setData(data, forType: .init(imageType ?? NSPasteboard.PasteboardType.png.rawValue))
        }
    }
}

@MainActor
enum ClipboardTemporaryPaste {
    static func paste(
        _ payload: ClipboardPayload,
        on board: NSPasteboard,
        observeWrite: (Int) -> Void,
        pause: () async -> Void = { try? await Task.sleep(for: .milliseconds(350)) },
        postPaste: () -> Bool
    ) async -> Bool {
        let originalVersion = board.changeCount
        guard let original = snapshot(board), board.changeCount == originalVersion else { return false }

        board.clearContents()
        let wrotePayload = payload.write(to: board)
        let temporaryVersion = board.changeCount
        observeWrite(temporaryVersion)
        let posted = wrotePayload && postPaste()
        // 合成事件只表示已投递。给目标应用留出读取粘贴板的时间。
        if posted { await pause() }
        if board.changeCount == temporaryVersion {
            board.clearContents()
            if !original.isEmpty { board.writeObjects(original) }
            observeWrite(board.changeCount)
        }
        return posted
    }

    private static func snapshot(_ board: NSPasteboard) -> [NSPasteboardItem]? {
        let protected = [NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
                         NSPasteboard.PasteboardType("org.nspasteboard.TransientType")]
        guard board.availableType(from: protected) == nil else { return nil }
        var items: [NSPasteboardItem] = []
        for item in board.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), copy.setData(data, forType: type) else { return nil }
            }
            items.append(copy)
        }
        return items
    }
}
