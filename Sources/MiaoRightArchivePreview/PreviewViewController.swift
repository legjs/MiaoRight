import AppKit
import MiaoRightArchivePreviewKit
import MiaoRightShared
import OSLog
import QuickLookUI

final class PreviewViewController: NSViewController, QLPreviewingController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Row {
        let entry: ArchiveDirectory.Entry
        lazy var children = entry.children?.map(Row.init) ?? []
        init(_ entry: ArchiveDirectory.Entry) { self.entry = entry }
    }

    private let outline = NSOutlineView()
    private let logger = Logger(subsystem: "com.miaoright.app.ArchivePreview", category: "QuickLook")
    private let summary = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private var rows: [Row] = []
    private var reader: Task<ArchiveDirectory, Error>?
    private var revision = 0
    private let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 420))
        let title = NSTextField(labelWithString: L10n.text("妙右压缩包预览", "MiaoRight Archive Preview"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        summary.textColor = .secondaryLabelColor
        summary.font = .systemFont(ofSize: 12)
        summary.lineBreakMode = .byTruncatingTail
        message.textColor = .secondaryLabelColor
        message.alignment = .center

        let columns: [(String, String, CGFloat, CGFloat)] = [
            ("name", L10n.text("名称", "Name"), 280, 100),
            ("size", L10n.text("大小", "Size"), 85, 65),
            ("date", L10n.text("修改时间", "Modified"), 120, 95)
        ]
        for (key, label, width, minimum) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = label
            column.width = width
            column.minWidth = minimum
            column.resizingMask = key == "name" ? [.autoresizingMask, .userResizingMask] : [.userResizingMask]
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns.first
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.usesAlternatingRowBackgroundColors = true
        outline.style = .plain
        outline.rowHeight = 22
        outline.dataSource = self
        outline.delegate = self
        outline.setAccessibilityLabel(L10n.text("压缩包目录", "Archive Contents"))

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true

        for subview in [title, summary, scroll, message] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            summary.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            summary.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            scroll.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            message.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            message.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 14)
        ])
        view = container
        preferredContentSize = NSSize(width: 600, height: 420)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        _ = view
        reader?.cancel()
        revision += 1
        let currentRevision = revision
        rows = []
        outline.reloadData()
        summary.stringValue = L10n.text("正在读取目录…", "Reading archive…")
        message.stringValue = ""
        let worker = Task.detached(priority: .userInitiated) {
            let hasScope = url.startAccessingSecurityScopedResource()
            defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
            return try ArchiveDirectory.read(url)
        }
        reader = worker
        let outcome = await withTaskCancellationHandler {
            await worker.result
        } onCancel: {
            worker.cancel()
        }
        guard currentRevision == revision else { throw CancellationError() }
        reader = nil
        try Task.checkCancellation()
        switch outcome {
        case .success(let directory):
            logger.info("Prepared archive preview with \(directory.files, privacy: .public) files")
            rows = directory.entries.map(Row.init)
            let bytes = directory.files == 1 && directory.entries.first?.children == nil && directory.entries.first?.size == nil
                ? L10n.text("大小未知", "Size unknown") : sizeFormatter.string(fromByteCount: directory.bytes)
            summary.stringValue = L10n.text(
                "\(directory.files.formatted()) 个文件 · \(directory.folders.formatted()) 个文件夹 · \(bytes)",
                "\(directory.files.formatted()) files · \(directory.folders.formatted()) folders · \(bytes)"
            )
            if directory.isPartial {
                summary.stringValue = L10n.text("仅显示部分内容 · ", "Partial listing · ") + summary.stringValue
            }
            outline.reloadData()
            if rows.count == 1, let first = rows.first { outline.expandItem(first) }
            if rows.isEmpty {
                message.stringValue = directory.isPartial
                    ? L10n.text("未能在预览限制内列出内容。", "No entries could be listed within the preview limits.")
                    : L10n.text("压缩包为空。", "This archive is empty.")
            }
        case .failure(is CancellationError):
            throw CancellationError()
        case .failure(let error):
            logger.info("Archive preview is unavailable")
            summary.stringValue = L10n.text("无法显示目录", "Contents unavailable")
            if case ArchiveDirectory.ReadError.encrypted = error {
                message.stringValue = L10n.text("目录已加密。请在妙右中解压并输入密码。", "The directory is encrypted. Extract it in MiaoRight to enter the password.")
            } else {
                message.stringValue = L10n.text("无法读取此压缩包。文件可能已损坏、缺少分卷，或使用了不支持的格式。", "This archive could not be read. It may be damaged, missing volumes, or use an unsupported format.")
            }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Row)?.children.count ?? rows.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? Row)?.children ?? rows)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Row)?.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? Row, let key = tableColumn?.identifier.rawValue else { return nil }
        let label: NSTextField
        if key == "name" {
            label = NSTextField(labelWithString: row.entry.name)
            label.toolTip = row.entry.name
            label.lineBreakMode = .byTruncatingMiddle
            let symbol = row.entry.children == nil ? "doc" : "folder.fill"
            let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = row.entry.children == nil ? .secondaryLabelColor : .controlAccentColor
            icon.setAccessibilityElement(false)
            let stack = NSStackView(views: [icon, label])
            stack.spacing = 5
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
            icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            return stack
        }
        if key == "size" {
            label = NSTextField(labelWithString: row.entry.size.map { sizeFormatter.string(fromByteCount: $0) } ?? "—")
            label.alignment = .right
        } else {
            label = NSTextField(labelWithString: row.entry.modified.map { dateFormatter.string(from: $0) } ?? "—")
        }
        label.textColor = .secondaryLabelColor
        return label
    }
}
