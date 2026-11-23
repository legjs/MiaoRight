import AppKit
import MiaoRightShared
import SwiftUI
import UniformTypeIdentifiers

enum ClipboardPanelPreferences {
    static let keepOpenKey = "clipPanelKeepOpen"
}

extension Notification.Name {
    static let clipPanelShown = Notification.Name("com.miaoright.clipPanelShown")
    /// 搜索确认或开始列表导航后,同步释放 SwiftUI 的搜索焦点。
    static let clipPanelSearchEnded = Notification.Name("com.miaoright.clipPanelSearchEnded")
    /// Panel 层截获的按键(keyCode),内容侧消费
    static let clipPanelKey = Notification.Name("com.miaoright.clipPanelKey")
}

/// 可接收键盘的 borderless 面板(↑↓ 导航/数字快选/回车确认/esc 收起)。
/// nonactivating:成为 key window 的同时不激活本 App,
/// 用户当前 App 的输入焦点不丢,选完 ⌘V 直接贴。
final class ClipboardSlidePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// SwiftUI 的 TextField 不保证使用 isFieldEditor=true 的 NSTextView。
    /// 同步显式焦点,避免把搜索输入误当成列表快捷键。
    private(set) var searchIsFocused = false

    func setSearchFocused(_ focused: Bool) {
        searchIsFocused = focused
        if !focused, firstResponder is NSTextInputClient {
            makeFirstResponder(nil)
        }
    }

    private func finishSearch() {
        setSearchFocused(false)
        NotificationCenter.default.post(name: .clipPanelSearchEnded, object: self)
    }

    /// 键盘路由(sendEvent 层,最先经过窗口):
    /// 搜索聚焦时,空格/数字/回车交给文本输入;回车仅提交搜索。
    /// 输入法组词时全部放行;其余时候保留方向键导航和 Esc 收起。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let editing = searchIsFocused

            // 输入法组词中(有 marked text):一切按键归输入法
            if hasMarkedText {
                super.sendEvent(event)
                return
            }

            switch Int(event.keyCode) {
            case 53: // Esc:组词已被上面排除,此处直接关面板
                if editing { makeFirstResponder(nil) } // 先收起编辑态
                ClipboardFloatingPanel.shared.slideOut()
                return
            case 36, 76: // Return / 小键盘 Enter:先确认搜索,下次回车才复制记录
                if editing {
                    finishSearch()
                    return
                }
                NotificationCenter.default.post(
                    name: .clipPanelKey, object: nil,
                    userInfo: ["keyCode": 36, "shifted": false]
                )
                return
            case 49, // 空格:编辑中=输入空格(上面未拦截的组合态同理);否则=勾选
                 18, 19, 20, 21, 23, 22, 26, 28, 25, 29: // 数字:编辑中=输入;否则=快选
                if editing {
                    super.sendEvent(event)
                    return
                }
                NotificationCenter.default.post(
                    name: .clipPanelKey, object: nil,
                    userInfo: ["keyCode": Int(event.keyCode), "shifted": false]
                )
                return
            case 125, 126: // ↑↓:退出搜索输入,将键盘操作权交给列表
                if editing { finishSearch() }
                NotificationCenter.default.post(
                    name: .clipPanelKey, object: nil,
                    userInfo: ["keyCode": Int(event.keyCode),
                               "shifted": event.modifierFlags.contains(.shift)]
                )
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    /// 输入法是否组词中(marked text)
    private var hasMarkedText: Bool {
        (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }
}

/// 窗口固定在目标屏幕内,只在裁剪容器中滑动内容。
/// 相邻屏幕共享桌面坐标,不能把「目标屏幕外」当作不可见区域。
final class ClipboardSlideViewport: NSView {
    let slidingContent: NSView

    init(content: NSView) {
        slidingContent = content
        super.init(frame: content.frame)
        wantsLayer = true
        layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    required init?(coder: NSCoder) { nil }

    func setRevealed(_ revealed: Bool, animated: Bool) {
        let origin = NSPoint(x: revealed ? 0 : bounds.width, y: 0)
        if animated {
            slidingContent.animator().setFrameOrigin(origin)
        } else {
            slidingContent.setFrameOrigin(origin)
        }
    }
}

/// 剪贴板面板:右缘全高、呼出滑入/选择滑出。
/// 快捷键(默认 ⇧⌘V,设置可改)或菜单栏开关呼出;
/// 打开自动聚焦第一项,↑↓ 移动、回车/数字确认,选中项弹簧动画上浮。
@MainActor
public final class ClipboardFloatingPanel: NSObject, NSWindowDelegate {
    public static let shared = ClipboardFloatingPanel()

    private var panel: ClipboardSlidePanel?
    private let width: CGFloat = 320
    private var isAnimating = false
    private var isClosing = false
    private var closeAfterOpening = false
    private var afterClose: [() -> Void] = []
    private var pasteTarget: pid_t?
    private weak var targetWindow: NSWindow?
    private lazy var pasteDelivery = ClipboardPasteDelivery(environment: .live(panelHasKey: { [weak self] in self?.panel?.isKeyWindow == true }))
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var menuObservers: [NSObjectProtocol] = []
    private var trackingMenus = 0
    private var isSavingRecord = false

    private var isPinned: Bool {
        AppGroup.standardDefaults.bool(forKey: ClipboardPanelPreferences.keepOpenKey)
    }
    /// 呼出时锁定的屏幕(鼠标所在屏):多屏下停靠位置不再漂移
    private var targetScreen: NSScreen?

    override private init() {
        super.init()
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func toggle() {
        isVisible ? slideOut() : slideIn()
    }

    // MARK: - 滑入 / 滑出

    public func slideIn() {
        guard !AppGroup.isIsolated else { return }
        guard !isAnimating else { return }
        pasteDelivery.cancel()
        pasteTarget = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetWindow = NSApp.keyWindow === panel ? nil : NSApp.keyWindow
        ClipboardHistoryService.shared.reloadStorage()
        targetScreen = screenUnderMouse() ?? NSScreen.main
        let p = panel ?? makePanel()
        panel = p
        guard let viewport = p.contentView as? ClipboardSlideViewport else { return }
        p.setFrame(dockedFrame(), display: false)
        viewport.setRevealed(false, animated: false)
        p.hasShadow = false
        isAnimating = true
        closeAfterOpening = false
        p.setSearchFocused(false)
        NotificationCenter.default.post(name: .clipPanelShown, object: nil)
        p.makeKeyAndOrderFront(nil) // 键盘与置前一并完成(nonactivating 不激活 App)
        startDismissMonitoring()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            viewport.setRevealed(true, animated: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                p.hasShadow = true
                self?.isAnimating = false
                if self?.closeAfterOpening == true {
                    self?.closeAfterOpening = false
                    self?.slideOut()
                    return
                }
                self?.accelerateScrolling()
            }
        })
    }

    public func slideOut(completion: (() -> Void)? = nil) {
        guard !AppGroup.isIsolated else { return }
        guard let p = panel, p.isVisible else { completion?(); return }
        if let completion { afterClose.append(completion) }
        guard !isClosing else { return }
        if isAnimating {
            closeAfterOpening = true // 呼出动画尚未结束时也不能丢掉关闭请求
            return
        }
        guard let viewport = p.contentView as? ClipboardSlideViewport else { return }
        stopDismissMonitoring()
        isAnimating = true
        isClosing = true
        p.hasShadow = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            viewport.setRevealed(false, animated: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                p.orderOut(nil)
                self?.isAnimating = false
                self?.isClosing = false
                let callbacks = self?.afterClose ?? []
                self?.afterClose.removeAll()
                callbacks.forEach { $0() }
            }
        })
    }

    // MARK: - 临时面板与固定模式

    private func dismissAutomatically() {
        guard !isPinned, !isSavingRecord, NSApp.modalWindow == nil else { return }
        slideOut()
    }

    private func closeAfterUse() {
        guard !AppGroup.isIsolated else { return }
        let autoPaste = AppGroup.standardDefaults.object(forKey: ClipboardHistoryService.autoPasteKey) as? Bool ?? true
        guard autoPaste else { if !isPinned { slideOut() }; return }
        let target = pasteTarget
        let version = NSPasteboard.general.changeCount
        pasteDelivery.cancel()
        let restoreAndPaste = { [weak self] in
            guard let self else { return }
            self.panel?.setSearchFocused(false)
            if self.isPinned {
                // 收回 nonactivating panel 借用的键盘焦点，再以非 key 方式保留固定面板。
                self.panel?.orderOut(nil)
                self.panel?.orderFrontRegardless()
            }
            if target == ProcessInfo.processInfo.processIdentifier { self.targetWindow?.makeKey() }
            Task { @MainActor in
                let outcome = await self.pasteDelivery.deliver(to: target, clipboardVersion: version)
                if outcome != .pasted && outcome != .cancelled {
                    ClipboardHistoryService.shared.reportFailure(L10n.text("已复制；未能恢复目标输入框，请按 ⌘V 粘贴。", "Copied. The target input could not be restored; press ⌘V to paste."))
                }
            }
        }
        if isPinned { restoreAndPaste() }
        else { slideOut(completion: restoreAndPaste) }
    }

    private func saveRecord(_ item: ClipboardItem) async {
        guard !AppGroup.isIsolated, !isSavingRecord else { return }
        let history = ClipboardHistoryService.shared
        guard let payload = history.payload(for: item) else { return }
        isSavingRecord = true
        defer { isSavingRecord = false }
        do {
            let export = try await Task.detached { try ClipboardExport(payload: payload) }.value
            guard isVisible else { return }
            NSApp.activate()
            guard let destination = await saveDestination(for: export) else { return }
            try await Task.detached { try export.write(to: destination) }.value
        } catch {
            history.reportFailure(L10n.text("无法完成保存。\(error.localizedDescription)", "Could not finish saving. \(error.localizedDescription)"))
        }
    }

    private func saveDestination(for export: ClipboardExport) async -> URL? {
        let picker: NSSavePanel
        switch export {
        case let .document(name, type, _):
            picker = NSSavePanel()
            picker.nameFieldStringValue = name
            picker.allowedContentTypes = [type]
        case .files:
            let folderPicker = NSOpenPanel()
            folderPicker.canChooseFiles = false
            folderPicker.canChooseDirectories = true
            folderPicker.allowsMultipleSelection = false
            picker = folderPicker
        }
        picker.title = L10n.text("保存剪贴板记录", "Save Clipboard Record")
        picker.prompt = L10n.text("保存", "Save")
        picker.canCreateDirectories = true
        return await picker.begin() == .OK ? picker.url : nil
    }

    private func startDismissMonitoring() {
        stopDismissMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.trackingMenus == 0 else { return }
                // 子窗口/弹出菜单的操作属于侧边栏,不能算作点击外部。
                var window = event.window
                while let current = window {
                    if current === self.panel { return }
                    window = current.parent
                }
                self.dismissAutomatically()
            }
            return event // 保留原点击,不影响用户继续操作其他窗口
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissAutomatically() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let activatedOtherApp = app?.processIdentifier != ProcessInfo.processInfo.processIdentifier
            MainActor.assumeIsolated {
                if activatedOtherApp, self?.isPinned == true {
                    self?.pasteTarget = app?.processIdentifier
                    self?.targetWindow = nil
                }
                if activatedOtherApp { self?.dismissAutomatically() }
            }
        }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackingMenus += 1 }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.trackingMenus = max(0, self.trackingMenus - 1)
                }
            }
        ]
    }

    private func stopDismissMonitoring() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers = []
        trackingMenus = 0
    }

    // MARK: - 布局

    /// 鼠标当前所在屏幕(多屏呼出定位)
    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    /// 停靠位置:锁定屏幕的右缘,全高(visibleFrame,避开菜单栏/程序坞)
    private func dockedFrame() -> NSRect {
        guard let screen = targetScreen ?? NSScreen.main else {
            return NSRect(x: 0, y: 0, width: width, height: 600)
        }
        let visible = screen.visibleFrame
        return NSRect(x: visible.maxX - width, y: visible.minY, width: width, height: visible.height)
    }

    /// 滚轮加速:找到 SwiftUI 内部的 NSScrollView,调大一档位移
    /// (lineScroll 即滚轮每格的基础步长;↑↓ 键盘导航自管理不受影响)
    private func accelerateScrolling() {
        guard let content = panel?.contentView else { return }
        Self.findScrollViews(in: content).forEach {
            $0.verticalLineScroll = 72
            $0.verticalPageScroll = 400
        }
    }

    private static func findScrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scroll = view as? NSScrollView { result.append(scroll) }
        for sub in view.subviews {
            result.append(contentsOf: findScrollViews(in: sub))
        }
        return result
    }

    // MARK: - 构建

    private func makePanel() -> ClipboardSlidePanel {
        // 窗口始终停在屏幕内,由内容容器裁剪滑入/滑出动画。
        let initial = dockedFrame()
        let panel = ClipboardSlidePanel(
            contentRect: initial,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.title = "MiaoRight Clipboard"
        panel.isMovable = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.delegate = self
        let hostingView = NSHostingView(
            rootView: ClipboardPanelContent(
                service: ClipboardHistoryService.shared,
                onClose: { [weak self] in self?.slideOut() },
                onUse: { [weak self] in self?.closeAfterUse() },
                onSave: { [weak self] item in Task { await self?.saveRecord(item) } },
                onSearchFocusChanged: { [weak panel] focused in
                    panel?.setSearchFocused(focused)
                }
            )
        )
        hostingView.frame = NSRect(origin: .zero, size: initial.size)
        let viewport = ClipboardSlideViewport(content: hostingView)
        viewport.setRevealed(false, animated: false)
        panel.contentView = viewport
        return panel
    }
}

// MARK: - 面板内容

struct ClipboardPanelContent: View {
    @State var service: ClipboardHistoryService
    let onClose: () -> Void
    let onUse: () -> Void
    let onSave: (ClipboardItem) -> Void
    @AppStorage(ClipboardPanelPreferences.keepOpenKey) private var keepOpen = false
    let onSearchFocusChanged: (Bool) -> Void
    @AppStorage(ClipboardHistoryService.autoPasteKey) private var autoPasteEnabled = true
    @State private var pasteAuthorized = AutoPaste.isAuthorized()
    private var reuseBehavior: ClipboardReuseBehavior { .resolve(autoPaste: autoPasteEnabled, authorized: pasteAuthorized) }
    @State private var refreshEpoch = 0
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var kindFilter: ClipboardKind?
    @State private var timeFilter: TimeFilter = .all
    @State private var recognizedImageText: [String: String] = [:]
    /// 键盘导航:面板打开聚焦第一项,↑↓ 移动,回车确认
    @State private var navigation = ClipboardListState()
    private var selection: Int {
        get { navigation.selection }
        nonmutating set { navigation.selection = newValue }
    }
    /// 多选:勾选的条目(空格/⇧方向/⌘点击),回车合并粘贴
    private var picked: [UUID] {
        get { navigation.picked }
        nonmutating set { navigation.picked = newValue }
    }
    @State private var mergeError: String?
    /// 搜索框焦点:聚焦时回车=确认搜索(焦点移回列表),空格=输入
    @FocusState private var searchFocused: Bool

    init(service: ClipboardHistoryService, onClose: @escaping () -> Void, onUse: @escaping () -> Void,
         onSave: @escaping (ClipboardItem) -> Void = { _ in },
         onSearchFocusChanged: @escaping (Bool) -> Void, favoritesOnly: Bool = false) {
        _service = State(initialValue: service)
        self.onClose = onClose; self.onUse = onUse; self.onSearchFocusChanged = onSearchFocusChanged
        self.onSave = onSave
        _favoritesOnly = State(initialValue: favoritesOnly)
    }

    /// 自定义时段天数(持久记忆上次输入)
    static let customDaysKey = "clipTimeCustomDays"

    enum TimeFilter: Hashable {
        case all
        case today
        case threeDays
        case custom(days: Int)

        static var allCases: [TimeFilter] {
            [.all, .today, .threeDays, .custom(days: customDays)]
        }
        static var customDays: Int {
            let stored = AppGroup.standardDefaults.integer(forKey: customDaysKey)
            return stored > 0 ? stored : 7
        }

        var title: String {
            switch self {
            case .all: L10n.text("全部时间", "All")
            case .today: L10n.text("今天", "Today")
            case .threeDays: L10n.text("三天内", "3 Days")
            case .custom(let days): L10n.text("\(days) 天内", "\(days) days")
            }
        }

        func matches(_ date: Date) -> Bool {
            switch self {
            case .all: true
            case .today: Calendar.current.isDateInToday(date)
            case .threeDays: Date().timeIntervalSince(date) < 3 * 86400
            case .custom(let days): Date().timeIntervalSince(date) < Double(days) * 86400
            }
        }
    }

    private var searchKeyword: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var scopedItems: [ClipboardItem] {
        service.items.filter { item in
            if favoritesOnly && !item.isFavorite { return false }
            if let kindFilter, item.kind != kindFilter { return false }
            return timeFilter.matches(item.date)
        }
    }

    /// 搜索过滤后的可见条目(键盘与数字快选作用于该列表)
    private var visibleItems: [ClipboardItem] {
        let keyword = searchKeyword
        guard !keyword.isEmpty else { return scopedItems }
        return scopedItems.filter { item in
            service.previewText(item).localizedCaseInsensitiveContains(keyword)
                || (item.kind == .image && recognizedImageText[item.content]?.localizedCaseInsensitiveContains(keyword) == true)
        }
    }

    private var imagesToSearch: Set<String> {
        guard !searchKeyword.isEmpty else { return [] }
        return Set(scopedItems.filter { $0.kind == .image }.map(\.content))
    }

    private var isSearchingImages: Bool {
        imagesToSearch.contains { recognizedImageText[$0] == nil }
    }

    private func indexImages(_ names: Set<String>) async {
        for item in scopedItems where item.kind == .image && names.contains(item.content) {
            guard !Task.isCancelled else { return }
            guard recognizedImageText[item.content] == nil else { continue }
            let url = ClipboardStore.originalImageURL(name: item.content)
            let text = await Task.detached(priority: .utility) {
                (try? NativeActionExecutor.recognizeText(in: url, languages: ["zh-Hans", "zh-Hant", "en-US"]).joined(separator: " ")) ?? ""
            }.value
            guard !Task.isCancelled else { return }
            let focusedID = visibleItems.indices.contains(selection) ? visibleItems[selection].id : nil
            recognizedImageText[item.content] = text
            if let focusedID, let index = visibleItems.firstIndex(where: { $0.id == focusedID }) {
                selection = index
            }
        }
    }

    // MARK: 键盘

    private func moveSelection(_ delta: Int) -> Bool {
        let count = visibleItems.count
        guard count > 0 else { return false }
        selection = max(0, min(count - 1, selection + delta))
        return true
    }

    private func confirmSelection() -> Bool {
        if !picked.isEmpty {
            return mergePicked()
        }
        let list = visibleItems
        guard selection >= 0, selection < list.count else { return false }
        guard service.reuse(list[selection]) else { return false }
        onUse()
        return true
    }

    /// 勾选/取消当前项
    private func togglePick() {
        let list = visibleItems
        guard selection >= 0, selection < list.count else { return }
        let id = list[selection].id
        if let index = picked.firstIndex(of: id) {
            picked.remove(at: index)
        } else {
            picked.append(id)
        }
    }

    /// ⇧ 方向:移动并顺路勾选
    private func moveAndPick(_ delta: Int) {
        let list = visibleItems
        guard moveSelection(delta), selection < list.count else { return }
        let id = list[selection].id
        if !picked.contains(id) { picked.append(id) }
    }

    /// 合并勾选项(按显示顺序)并粘贴:文本/文件路径换行拼接,图片跳过
    private func mergePicked() -> Bool {
        let pickedSet = Set(picked)
        let chosen = visibleItems.filter { pickedSet.contains($0.id) }
        guard !chosen.isEmpty else { return false }
        guard chosen.allSatisfy({ $0.kind != .image }) else {
            mergeError = L10n.text("图片无法与其他记录合并，请单独选择图片。", "Images cannot be merged with other records. Select an image on its own.")
            return false
        }
        mergeError = nil
        let parts = chosen.map { item -> String? in
            switch item.kind {
            case .text: item.content
            case .files: item.content // 路径按行
            case .image: nil
            }
        }.compactMap { $0 }
        guard !parts.isEmpty else { return false }

        let merged = parts.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(merged, forType: .string)
        picked = []
        onUse()
        return true
    }

    /// 数字键 → 选择条目并收起(1-9 对应前 9 项,0 对应第 10 项)
    private func handleKey(_ key: String) -> Bool {
        guard let digit = key.first, digit.isNumber, digit.isASCII else { return false }
        let list = visibleItems
        let index: Int? = digit == "0" ? 9 : digit.wholeNumberValue.map { $0 - 1 }
        guard let index, index >= 0, index < list.count else { return false }
        guard service.reuse(list[index]) else { return false }
        onUse()
        return true
    }

    // MARK: 视图

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Picker(L10n.text("记录范围", "History Scope"), selection: $favoritesOnly) {
                Text(L10n.text("全部", "All")).tag(false)
                Text(L10n.text("收藏", "Favorites")).tag(true)
            }.labelsHidden().pickerStyle(.segmented).padding(.horizontal, 14).padding(.bottom, 8)
            if !service.recordingEnabled {
                Text(L10n.text("历史记录已暂停", "History recording paused")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            if autoPasteEnabled, !pasteAuthorized {
                HStack(alignment: .top, spacing: 8) {
                    Text(L10n.text("直接粘贴需要辅助功能权限。未授权时先复制，再按 ⌘V。", "Direct paste needs Accessibility permission. Until then, select to copy and press ⌘V."))
                    Button(L10n.text("授权", "Authorize")) { AutoPaste.openAuthorizationSettings() }.buttonStyle(.borderless)
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 8)
            }
            if let feedback = mergeError ?? service.feedback {
                Text(feedback).font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 14).padding(.bottom, 8)
            }
            Divider()
            if service.items.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text(service.recordingEnabled
                         ? L10n.text("复制内容会自动出现在这里", "Copied items appear here")
                         : L10n.text("在主窗口的剪贴板设置中开启记录", "Enable history in the main window’s Clipboard settings"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                listBody
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultAppStorage(AppGroup.standardDefaults)
        .background { FrostedWindowBackground() }
        .tint(.blue)
        .id(refreshEpoch)
        .task(id: imagesToSearch) { await indexImages(imagesToSearch) }
        .onChange(of: Set(service.items.filter { $0.kind == .image }.map(\.content))) { _, names in
            recognizedImageText = recognizedImageText.filter { names.contains($0.key) }
        }
        .onAppear {
            searchFocused = false // 默认操作选中记录;点击搜索框才进入文本输入
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipPanelSearchEnded)) { _ in
            searchFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipPanelShown)) { _ in
            navigation.beginPresentation()
            mergeError = nil
            searchFocused = false
            onSearchFocusChanged(false)
            pasteAuthorized = AutoPaste.isAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            pasteAuthorized = AutoPaste.isAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageChangedNotification)) { _ in
            refreshEpoch += 1
        }
        .onChange(of: query) { _, _ in selection = 0; mergeError = nil }
        .onChange(of: favoritesOnly) { _, _ in selection = 0; picked.removeAll(); mergeError = nil }
        .onChange(of: picked) { _, _ in mergeError = nil }
        .onChange(of: kindFilter) { _, _ in selection = 0 }
        .onChange(of: timeFilter) { _, _ in selection = 0 }
        .onChange(of: searchFocused, initial: true) { _, focused in
            onSearchFocusChanged(focused)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipPanelKey)) { note in
            guard let code = note.userInfo?["keyCode"] as? Int else { return }
            let shifted = note.userInfo?["shifted"] as? Bool ?? false
            switch code {
            case 53: onClose()
            case 49: // 空格:勾选/取消当前项
                togglePick()
            case 125: // ↓(kVK_DownArrow=125)
                if shifted { moveAndPick(1) } else { _ = moveSelection(1) }
            case 126: // ↑(kVK_UpArrow=126)
                if shifted { moveAndPick(-1) } else { _ = moveSelection(-1) }
            case 36: _ = confirmSelection()
            default:
                // ANSI 数字键位 → 字符
                let digitMap = [18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
                                22: "6", 26: "7", 28: "8", 25: "9", 29: "0"]
                if let ch = digitMap[code] {
                    picked = [] // 数字快贴清空多选
                    _ = handleKey(ch)
                }
            }
        }
    }

    /// 列表主体:单列大卡片,滚动按行对齐,键盘选择滚动跟随
    @ViewBuilder
    private var listBody: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                let list = visibleItems
                if list.isEmpty {
                    Text(isSearchingImages ? L10n.text("正在搜索图片文字…", "Searching text in images…") : favoritesOnly && query.isEmpty
                         ? L10n.text("还没有收藏。切换到“全部”，在记录的“…”菜单中选择“收藏”。", "No favorites yet. Switch to All, then choose Favorite from a record’s … menu.")
                         : L10n.text("没有匹配的条目", "No matches"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 3) {
                        ForEach(list.indices, id: \.self) { index in
                            ClipCard(
                                item: list[index],
                                badge: badgeText(index),
                                isCurrent: service.items.first?.id == list[index].id,
                                isSelected: selection == index,
                                isPicked: picked.contains(list[index].id),
                                preview: service.previewText(list[index]),
                                thumbnail: service.thumbnail(for: list[index]),
                                timeText: timeText(list[index].date),
                                reuseBehavior: reuseBehavior,
                                onReuse: {
                                    if service.reuse(list[index]) { onUse() }
                                },
                                onDelete: {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        service.remove(list[index])
                                    }
                                    refreshEpoch += 1
                                },
                                onToggleFavorite: { service.toggleFavorite(list[index]) },
                                onSave: { onSave(list[index]) },
                                onCmdTap: {
                                    searchFocused = false
                                    onSearchFocusChanged(false)
                                    selection = index
                                    let id = list[index].id
                                    if let i = picked.firstIndex(of: id) {
                                        picked.remove(at: i)
                                    } else {
                                        picked.append(id)
                                    }
                                }
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, newValue in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clipPanelShown)) { _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.text("剪贴板", "Clipboard"))
                .font(.system(size: 13, weight: .heavy))
            if !service.items.isEmpty {
                Text("\(service.items.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            Spacer()
            Button {
                keepOpen.toggle()
            } label: {
                Image(systemName: keepOpen ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(keepOpen ? Color.blue : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(keepOpen
                  ? L10n.text("取消固定,点击外部自动收起", "Unpin; hide when clicking outside")
                  : L10n.text("固定侧边栏,保持展开", "Pin sidebar to keep it open"))
            .accessibilityLabel(L10n.text("固定侧边栏", "Pin sidebar"))
            .accessibilityValue(keepOpen ? L10n.text("已固定", "Pinned") : L10n.text("未固定", "Unpinned"))
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(L10n.text("收起", "Hide") + " (" + HotkeyCenter.shared.currentDisplay + ")")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            TextField(L10n.text("搜索记录或图片文字…", "Search history or image text…"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .onSubmit {
                    // 仅确认搜索并移回列表,本次回车不复用任何记录。
                    searchFocused = false
                    onSearchFocusChanged(false)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            kindMenu
            timeMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// 类别过滤(小图标菜单,尽量少占宽)
    private var kindMenu: some View {
        Menu {
            Button(L10n.text("全部类别", "All")) { kindFilter = nil }
            Divider()
            Button(L10n.text("文字", "Text")) { kindFilter = .text }
            Button(L10n.text("图片", "Image")) { kindFilter = .image }
            Button(L10n.text("文件", "File")) { kindFilter = .files }
        } label: {
            Image(systemName: kindFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(kindFilter == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.blue))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 22, height: 18)
    }

    /// 时间过滤(小图标菜单;含自定义天数)
    private var timeMenu: some View {
        Menu {
            ForEach(TimeFilter.allCases, id: \.self) { filter in
                Button(timeFilter == filter ? "✓ \(filter.title)" : filter.title) {
                    timeFilter = filter
                }
            }
            Divider()
            Button(L10n.text("自定义天数…", "Custom Days…")) {
                if let days = askCustomDays(), days > 0 {
                    AppGroup.standardDefaults.set(days, forKey: ClipboardPanelContent.customDaysKey)
                    timeFilter = .custom(days: days)
                }
            }
        } label: {
            Image(systemName: timeFilter == .all ? "clock" : "clock.fill")
                .font(.system(size: 10))
                .foregroundStyle(timeFilter == .all ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.blue))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 22, height: 18)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if !picked.isEmpty { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
            Text(reuseBehavior.footer(pickedCount: picked.count))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }

    /// 自定义时段输入:天数(取消返回 nil)
    private func askCustomDays() -> Int? {
        let alert = NSAlert()
        alert.messageText = L10n.text("查询最近多少天内的记录?", "How many days back?")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        field.stringValue = String(TimeFilter.customDays)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("好", "OK"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let days = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), days > 0
        else { return nil }
        return min(days, 3650)
    }

    /// 前 10 项的数字角标文本(1-9、0)
    private func badgeText(_ index: Int) -> String? {
        guard index < 10 else { return nil }
        return index == 9 ? "0" : String(index + 1)
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = L10n.isEnglish ? "h:mm" : "HH:mm"
        } else {
            formatter.dateFormat = L10n.isEnglish ? "M/d" : "M月d日"
        }
        return formatter.string(from: date)
    }
}

// MARK: - 历史记录行

private struct ClipCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let item: ClipboardItem
    let badge: String?
    let isCurrent: Bool
    let isSelected: Bool
    var isPicked = false
    let preview: String
    let thumbnail: NSImage?
    let timeText: String
    let reuseBehavior: ClipboardReuseBehavior
    let onReuse: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    let onSave: () -> Void
    var onCmdTap: (() -> Void)? = nil

    private var kindText: String {
        switch item.kind {
        case .text: L10n.text("文字", "Text")
        case .image: L10n.text("图片", "Image")
        case .files: L10n.text("文件", "Files")
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Toggle(L10n.text("勾选记录", "Pick Record"), isOn: Binding(get: { isPicked }, set: { _ in onCmdTap?() }))
                .labelsHidden().toggleStyle(.checkbox).controlSize(.small).padding(.top, 3)
            Button {
                if NSEvent.modifierFlags.contains(.command) { onCmdTap?() }
                else { onReuse() }
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    if item.kind == .image, let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 100, alignment: .leading)
                    } else {
                        Text(preview).font(.system(size: 13)).foregroundStyle(.primary)
                            .lineLimit(3).multilineTextAlignment(.leading)
                    }
                    HStack(spacing: 6) {
                        Text(kindText)
                        Text(timeText)
                        if item.isFavorite { Image(systemName: "star.fill").accessibilityLabel(L10n.text("已收藏", "Favorite")) }
                        if isSelected { Text(L10n.text("已选中", "Selected")).foregroundStyle(Color.primary).fontWeight(.medium) }
                        else if isCurrent { Text(L10n.text("当前", "Current")) }
                        Spacer(minLength: 0)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            VStack(spacing: 12) {
                if let badge {
                    Text(badge).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .frame(width: 22, height: 20)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isSelected ? Color.blue : Color.primary.opacity(0.15), lineWidth: isSelected ? 1 : 0.5))
                        .help(L10n.text("按 \(badge) 使用此记录", "Press \(badge) to use this record"))
                        .accessibilityLabel(L10n.text("快捷键 \(badge)", "Shortcut \(badge)"))
                }
            Menu {
                Button(reuseBehavior.menuTitle, action: onReuse)
                Button(L10n.text("保存…", "Save…"), action: onSave)
                Button(item.isFavorite ? L10n.text("取消收藏", "Remove Favorite") : L10n.text("收藏", "Favorite"), action: onToggleFavorite)
                Button(L10n.text("删除记录", "Delete Record"), role: .destructive, action: onDelete)
            } label: { Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18)
                .accessibilityLabel(L10n.text("记录操作", "Record Actions"))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .background(isSelected ? Color.blue.opacity(colorScheme == .dark ? 0.26 : 0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isSelected ? Color.blue.opacity(contrast == .increased ? 1 : 0.75) : Color.clear, lineWidth: 1))
        .overlay(alignment: .leading) {
            if isSelected { Capsule().fill(Color.blue).frame(width: 3).padding(.vertical, 11).padding(.leading, 1) }
        }
        .accessibilityElement(children: .contain)
    }
}
