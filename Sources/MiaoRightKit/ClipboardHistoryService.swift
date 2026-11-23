import AppKit
import ApplicationServices
import MiaoRightShared
import Observation

/// 剪贴板条目类型
public enum ClipboardKind: String, Codable {
    case text
    case image
    case files
}

/// 剪贴板条目(元数据存 SQLite;图片缩略图/原图存缓存目录 thumbs/)
public struct ClipboardItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var kind: ClipboardKind
    public var content: String
    public var date: Date
    public var isFavorite: Bool
    /// image 专用:本次会话内的原图内存缓存(不持久化)
    public var sourceImage: Data?

    public init(id: UUID = UUID(), kind: ClipboardKind, content: String, date: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.kind = kind
        self.content = content
        self.date = date
        self.isFavorite = isFavorite
    }

    public enum CodingKeys: String, CodingKey {
        case id, kind, content, date, isFavorite
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ClipboardKind.self, forKey: .kind)
        content = try c.decode(String.self, forKey: .content)
        date = try c.decode(Date.self, forKey: .date)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(content, forKey: .content)
        try c.encode(date, forKey: .date)
        try c.encode(isFavorite, forKey: .isFavorite)
    }
}

/// 剪贴板历史:0.5s 轮询系统粘贴板,文本/图片/文件三类自动入列(SQLite 持久化)。
/// 规则:最新置顶;点选条目=写回系统剪贴板并上浮首位(可配自动粘贴回输入框);
/// 条目不随使用清除;上限与缓存目录可在设置页调整。
@MainActor
@Observable
public final class ClipboardHistoryService {
    public static let shared = ClipboardHistoryService()

    private static let maxImageBytes = 5 * 1024 * 1024

    public private(set) var items: [ClipboardItem] = []
    private var lastChangeCount: Int
    private var timer: Timer?
    private var pastingPreviousItem = false

    public static let autoPasteKey = "clipboardAutoPaste"
    public static let recordingEnabledKey = "clipboardRecordingEnabled"
    public static let retentionDaysKey = "clipboardRetentionDays"
    public private(set) var recordingEnabled: Bool
    public private(set) var retentionDays: Int
    public private(set) var feedback: String?

    public func setRecordingEnabled(_ enabled: Bool) {
        recordingEnabled = enabled
        AppGroup.standardDefaults.set(enabled, forKey: Self.recordingEnabledKey)
        if enabled { startMonitoring() }
        else { timer?.invalidate(); timer = nil }
    }

    public func reloadStorage() {
        items = ClipboardStore.shared.loadAll()
        feedback = nil
        purgeExpiredItems()
    }

    public func setRetentionDays(_ days: Int) {
        retentionDays = [0, 7, 30].contains(days) ? days : 0
        AppGroup.standardDefaults.set(retentionDays, forKey: Self.retentionDaysKey)
        purgeExpiredItems()
    }

    private func purgeExpiredItems() {
        guard retentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        for item in items.filter({ !$0.isFavorite && $0.date < cutoff }) { remove(item) }
    }

    private init() {
        lastChangeCount = AppGroup.isIsolated ? 0 : NSPasteboard.general.changeCount
        let hadHistoryStore = FileManager.default.fileExists(atPath: ClipboardStore.databaseURL.path)
        ClipboardStore.migrateLegacyJSONIfNeeded()
        let loadedItems = ClipboardStore.shared.loadAll()
        items = loadedItems
        let defaults = AppGroup.standardDefaults
        // 保留已有用户的采集与历史;首次使用需主动启用记录。
        recordingEnabled = defaults.object(forKey: Self.recordingEnabledKey) as? Bool ?? (hadHistoryStore || !loadedItems.isEmpty)
        retentionDays = defaults.object(forKey: Self.retentionDaysKey) as? Int ?? (hadHistoryStore || !loadedItems.isEmpty ? 0 : 7)
        defaults.set(recordingEnabled, forKey: Self.recordingEnabledKey)
        defaults.set(retentionDays, forKey: Self.retentionDaysKey)
        purgeExpiredItems()
    }

    /// 开始监听(幂等;主 App 启动时调用)
    public func startMonitoring() {
        guard !AppGroup.isIsolated, recordingEnabled, timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollOnce() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 写回系统剪贴板并上浮置顶；面板在交还焦点后统一完成自动粘贴。
    @discardableResult
    public func reuse(_ item: ClipboardItem, pasteboard: NSPasteboard = .general) -> Bool {
        guard let payload = payload(for: item) else { return false }
        pasteboard.clearContents()
        let written = payload.write(to: pasteboard)
        lastChangeCount = pasteboard.changeCount // 自己的写入不重复入列
        guard written else { return false }
        moveToTop(item)

        return true
    }

    func pastePreviousItem() async {
        guard !AppGroup.isIsolated, !pastingPreviousItem else { return }
        guard AutoPaste.isAuthorized(),
              let target = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              target != ProcessInfo.processInfo.processIdentifier else {
            NSSound.beep()
            return
        }
        if recordingEnabled { pollOnce() }
        guard items.count >= 2, let payload = payload(for: items[1]) else {
            NSSound.beep()
            return
        }
        pastingPreviousItem = true
        defer { pastingPreviousItem = false }
        let posted = await ClipboardTemporaryPaste.paste(payload, on: .general, observeWrite: { lastChangeCount = $0 }) {
            AutoPaste.paste(to: target)
        }
        if !posted { NSSound.beep() }
    }

    func payload(for item: ClipboardItem) -> ClipboardPayload? {
        feedback = nil
        switch item.kind {
        case .text:
            return .text(item.content)
        case .files:
            return .files(item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
        case .image:
            return imageData(for: item).map(ClipboardPayload.image)
        }
    }

    private func imageData(for item: ClipboardItem) -> Data? {
        let data = item.sourceImage ?? ClipboardStore.shared.originalData(name: item.content)
        if data == nil {
            feedback = L10n.text("这张图片的缓存已丢失，请重新复制图片。", "This image is no longer cached. Copy the original image again.")
        }
        return data
    }

    func reportFailure(_ message: String) { feedback = message }

    public func remove(_ item: ClipboardItem) {
        ClipboardStore.shared.delete(id: item.id)
        items.removeAll { $0.id == item.id }
        if item.kind == .image && !items.contains(where: { $0.kind == .image && $0.content == item.content }) {
            ClipboardStore.shared.removeThumbFiles(name: item.content)
        }
    }

    public func toggleFavorite(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let favorite = !items[index].isFavorite
        let refreshedDate = favorite ? nil : Date()
        guard ClipboardStore.shared.setFavorite(id: item.id, value: favorite, refreshedDate: refreshedDate) else {
            feedback = L10n.text("无法保存收藏，请检查记录保存位置。", "Could not save the favorite. Check the history storage location.")
            return
        }
        items[index].isFavorite = favorite
        if let refreshedDate {
            var item = items.remove(at: index); item.date = refreshedDate; items.insert(item, at: 0)
        }
        feedback = nil
        if !favorite { purgeExpiredItems(); enforceLimit() }
    }

    @discardableResult
    public func addFavoriteText(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 10_000 else {
            feedback = L10n.text("请输入 1 至 10000 字的常用文字。", "Enter between 1 and 10,000 characters.")
            return false
        }
        let saved = record(.init(kind: .text, content: text, isFavorite: true))
        if saved { feedback = nil }
        return saved
    }

    public func clearUnfavoritedHistory() {
        for item in items.filter({ !$0.isFavorite }) { remove(item) }
    }

    /// 清除全部缓存(设置页「清除缓存」)
    public func clearAll() {
        ClipboardStore.shared.clearAll()
        items = []
    }

    // MARK: - 监听

    private func pollOnce() {
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        let board = NSPasteboard.general
        // 遵守来源应用对保密、短暂和自动生成内容的声明。
        let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        guard !excluded.contains(where: { board.availableType(from: [NSPasteboard.PasteboardType($0)]) != nil }) else { return }

        // 优先级:文件 > 图片 > 文本(与 Finder 复制行为对齐)
        if let urls = board.readObjects(forClasses: [NSURL.self]) as? [URL],
           !urls.isEmpty,
           urls.allSatisfy({ $0.isFileURL }) {
            let content = urls.map(\.path).joined(separator: "\n")
            record(.init(kind: .files, content: content))
            return
        }
        if let data = board.data(forType: .png) ?? board.data(forType: .tiff),
           let image = NSImage(data: data) {
            guard data.count <= Self.maxImageBytes else { return }
            let thumbName = "thumb-\(UUID().uuidString).png"
            if saveThumb(image: image, name: thumbName),
               ClipboardStore.shared.saveOriginal(data, name: thumbName) {
                var item = ClipboardItem(kind: .image, content: thumbName)
                item.sourceImage = data
                record(item)
            }
            return
        }
        if let text = board.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record(.init(kind: .text, content: String(text.prefix(10_000))))
        }
    }

    @discardableResult
    private func record(_ newItem: ClipboardItem) -> Bool {
        // 同内容去重:上浮 + 刷新时间
        if let index = items.firstIndex(where: { key($0) == key(newItem) && $0.kind == newItem.kind }) {
            var refreshed = items[index]
            refreshed.date = Date()
            refreshed.sourceImage = newItem.sourceImage ?? refreshed.sourceImage
            refreshed.isFavorite = refreshed.isFavorite || newItem.isFavorite
            guard ClipboardStore.shared.upsert(refreshed) else { return recordingFailed() }
            items.remove(at: index)
            items.insert(refreshed, at: 0)
            return true
        }
        guard ClipboardStore.shared.upsert(newItem) else { return recordingFailed() }
        items.insert(newItem, at: 0)

        // 条数上限裁剪(设置页可调)
        enforceLimit()
        return true
    }

    private func recordingFailed() -> Bool {
        feedback = L10n.text("无法保存记录，请检查记录保存位置。", "Could not save the record. Check the history storage location.")
        return false
    }

    private func enforceLimit() {
        let limit = ClipboardStore.maxItems
        let history = items.filter { !$0.isFavorite }
        if history.count > limit {
            let dropped = Array(history.suffix(history.count - limit))
            let ids = Set(dropped.map(\.id))
            items.removeAll { ids.contains($0.id) }
            dropped.forEach { item in
                ClipboardStore.shared.delete(id: item.id)
                if item.kind == .image && !items.contains(where: { $0.kind == .image && $0.content == item.content }) {
                    ClipboardStore.shared.removeThumbFiles(name: item.content)
                }
            }
        }
    }

    private func key(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .text: "t:" + item.content
        case .files: "f:" + item.content
        case .image: "i:" + item.content
        }
    }

    private func moveToTop(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var entry = items.remove(at: index)
        entry.date = Date()
        items.insert(entry, at: 0)
        ClipboardStore.shared.upsert(entry)
    }

    // MARK: - 缩略图与预览

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        switch item.kind {
        case .text:
            return nil
        case .files:
            let first = item.content.split(separator: "\n").first.map(String.init) ?? ""
            return NSWorkspace.shared.icon(forFile: first)
        case .image:
            if let url = ClipboardStore.shared.thumbURL(name: item.content) {
                return NSImage(contentsOf: url)
            }
            return nil
        }
    }

    func previewText(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            return item.content.replacingOccurrences(of: "\n", with: " ⏎ ")
        case .files:
            let lines = item.content.split(separator: "\n")
            let first = lines.first.map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? ""
            return lines.count > 1 ? "\(first) 等 \(lines.count) 项" : first
        case .image:
            return L10n.text("图片", "Image")
        }
    }

    private func saveThumb(image: NSImage, name: String) -> Bool {
        let side: CGFloat = 96
        let size = image.size
        let scale = min(side / max(size.width, 1), side / max(size.height, 1), 1)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        thumb.unlockFocus()
        guard let tiff = thumb.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return false }
        return ClipboardStore.shared.saveThumbPNG(png, name: name)
    }
}

/// 自动粘贴:选条目后模拟 ⌘V,把内容直接贴进聚焦的输入框。
/// 合成键盘事件需要「辅助功能」授权;未授权时静默跳过(复制仍生效)。
@MainActor
enum AutoPaste {
    /// 辅助功能授权状态
    static func isAuthorized() -> Bool {
        !AppGroup.isIsolated && AXIsProcessTrusted()
    }

    /// 打开系统设置的「隐私与安全性 → 辅助功能」
    static func openAuthorizationSettings() {
        guard !AppGroup.isIsolated else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 已恢复的目标应用单独收取事件，避免粘贴落入侧边栏或其他应用。
    static func paste(to process: pid_t) -> Bool {
        guard !AppGroup.isIsolated, isAuthorized(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == process else { return false }
        let source = CGEventSource(stateID: .privateState)
        let keyCodeV: CGKeyCode = 9 // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false) else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(process)
        keyUp.postToPid(process)
        return true
    }
}
