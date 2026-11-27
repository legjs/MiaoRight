import AppKit
import os.log
import MiaoRightShared

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private let logger = Logger(subsystem: "com.miaoright.app", category: "MenuBar")
    private var statusItem: NSStatusItem?
    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()
    private var updateItem: NSMenuItem?
    private var updateNotesItem: NSMenuItem?
    private var updateRefreshTimer: Timer?
    private var upToDateNoticeUntil: Date?

    override private init() {
        super.init()
    }

    func setEnabled(_ enabled: Bool) {
        guard !AppGroup.isIsolated else { return }
        if enabled {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = menuBarImage()
            image?.isTemplate = true
            button.image = image
            button.toolTip = "MiaoRight"
        }

        item.menu = menu
        statusItem = item
        rebuildMenu()
        logger.info("Menu bar icon enabled")
    }

    private func menuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "MiaoRight")
        }
        image.size = NSSize(width: 18, height: 18)
        if let retinaURL = Bundle.main.url(forResource: "MenuBarTemplate@2x", withExtension: "png"),
           let data = try? Data(contentsOf: retinaURL), let retina = NSBitmapImageRep(data: data) {
            retina.size = image.size
            image.addRepresentation(retina)
        }
        return image
    }

    private func removeStatusItem() {
        guard let item = statusItem else { return }
        stopUpdateRefresh()
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        logger.info("Menu bar icon disabled")
    }

    private func rebuildMenu() {
        updateItem = nil
        updateNotesItem = nil
        menu.removeAllItems()

        // 打开主窗口
        let openItem = NSMenuItem(title: L10n.text("打开 MiaoRight", "Open MiaoRight"), action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        // 剪贴板悬浮面板开关
        let clipPanel = NSMenuItem(
            title: L10n.text("剪贴板面板", "Clipboard Panel"),
            action: #selector(toggleClipboardPanel),
            keyEquivalent: ""
        )
        clipPanel.target = self
        clipPanel.state = ClipboardFloatingPanel.shared.isVisible ? .on : .off
        menu.addItem(clipPanel)

        if let result = ActionResultPresentation.shared.result {
            if !result.outputPaths.isEmpty {
                let item = NSMenuItem(title: L10n.text("打开上次结果的位置", "Show Last Result in Finder"), action: #selector(revealLastResult), keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            if let id = result.undoID, let receipt = FileOperationJournal.shared.receipt(id) {
                let item = NSMenuItem(title: L10n.text("撤销\(receipt.localizedTitle)", "Undo \(receipt.localizedTitle)"), action: #selector(undoLastOperation), keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: L10n.text("检查更新…", "Check for Updates…"),
            action: #selector(performUpdateAction),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)
        self.updateItem = updateItem

        let notesItem = NSMenuItem(
            title: "",
            action: #selector(showUpdateNotes),
            keyEquivalent: ""
        )
        notesItem.target = self
        notesItem.isHidden = true
        menu.addItem(notesItem)
        self.updateNotesItem = notesItem

        refreshUpdateItems()

        menu.addItem(.separator())

        // 重启 Finder
        let finderItem = NSMenuItem(title: L10n.text("重启 Finder", "Restart Finder"), action: #selector(restartFinder), keyEquivalent: "")
        finderItem.target = self
        menu.addItem(finderItem)

        menu.addItem(.separator())

        // 退出
        let quitItem = NSMenuItem(title: L10n.text("退出 MiaoRight", "Quit MiaoRight"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu() // 每次打开重建,确保语言切换后文字正确
        startUpdateRefresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopUpdateRefresh()
    }

    private func startUpdateRefresh() {
        stopUpdateRefresh()
        let timer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(timerDidFireForUpdateRefresh(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        updateRefreshTimer = timer
    }

    private func stopUpdateRefresh() {
        updateRefreshTimer?.invalidate()
        updateRefreshTimer = nil
    }

    @objc private func timerDidFireForUpdateRefresh(_ timer: Timer) {
        refreshUpdateItems()
    }

    private func refreshUpdateItems() {
        guard let updateItem, let updateNotesItem else { return }
        let previousTitle = updateItem.title
        let previousEnabled = updateItem.isEnabled
        let previousNotesTitle = updateNotesItem.title
        let previousNotesHidden = updateNotesItem.isHidden
        let updates = AppUpdateService.shared
        if updates.state == .upToDate, updates.consumeUpToDateNotice() {
            upToDateNoticeUntil = Date().addingTimeInterval(4)
        }
        updateNotesItem.isHidden = true

        switch updates.state {
        case .checking:
            upToDateNoticeUntil = nil
            updateItem.title = L10n.text("正在检查更新…", "Checking for Updates…")
            updateItem.isEnabled = false
        case .available(let release):
            upToDateNoticeUntil = nil
            updateNotesItem.isHidden = false
            updateNotesItem.title = L10n.text(
                "查看 \(release.tagName) 更新日志…",
                "View \(release.tagName) Release Notes…"
            )
            if updates.isInstalling {
                var title = L10n.text(
                    "正在更新到 \(release.tagName)…",
                    "Updating to \(release.tagName)…"
                )
                if let fraction = updates.downloadProgress {
                    title += " \(Int(fraction * 100))%"
                }
                updateItem.title = title
                updateItem.isEnabled = false
            } else if updates.canInstallInPlace {
                updateItem.title = L10n.text(
                    "更新到 \(release.tagName)…",
                    "Update to \(release.tagName)…"
                )
                updateItem.isEnabled = true
            } else {
                updateItem.title = L10n.text(
                    "查看 \(release.tagName) 更新…",
                    "View \(release.tagName) Update…"
                )
                updateItem.isEnabled = true
            }
        case .upToDate:
            if let until = upToDateNoticeUntil, Date() < until {
                updateItem.title = L10n.text("你的版本已最新", "You're Up to Date")
                updateItem.isEnabled = false
            } else {
                upToDateNoticeUntil = nil
                updateItem.title = L10n.text("检查更新…", "Check for Updates…")
                updateItem.isEnabled = true
            }
        case .failed:
            upToDateNoticeUntil = nil
            updateItem.title = L10n.text("检查更新失败，点按重试…", "Check Failed — Try Again…")
            updateItem.isEnabled = true
        case .idle, .noRelease:
            upToDateNoticeUntil = nil
            updateItem.title = L10n.text("检查更新…", "Check for Updates…")
            updateItem.isEnabled = true
        }

        if updateItem.title != previousTitle || updateItem.isEnabled != previousEnabled {
            updateItem.menu?.itemChanged(updateItem)
        }
        if updateNotesItem.title != previousNotesTitle || updateNotesItem.isHidden != previousNotesHidden {
            updateNotesItem.menu?.itemChanged(updateNotesItem)
        }
    }

    @MainActor
    @objc private func openApp() {
        WindowActionStorage.shared.showMainWindow()
    }

    @MainActor
    @objc private func toggleClipboardPanel() {
        ClipboardFloatingPanel.shared.toggle()
    }

    @objc private func revealLastResult() {
        guard !AppGroup.isIsolated, let result = ActionResultPresentation.shared.result else { return }
        let urls = result.outputPaths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    @objc private func undoLastOperation() {
        guard let previous = ActionResultPresentation.shared.result, let id = previous.undoID else { return }
        Task {
            let outcome = await Task.detached { () -> Result<[URL], ScriptError> in
                do { return .success(try FileOperationJournal.shared.undo(id)) }
                catch { return .failure(.executionFailed(error.localizedDescription)) }
            }.value
            switch outcome {
            case .success(let urls):
                ActionResultPresentation.shared.present(.success(scriptName: "已撤销", output: urls.map(\.path).joined(separator: "\n"), outputPaths: urls.map(\.path)))
            case .failure(let error):
                ActionResultPresentation.shared.present(.failure(scriptName: L10n.text("撤销失败", "Undo Failed"), error: error.localizedDescription, outputPaths: previous.outputPaths, undoID: id))
                WindowActionStorage.shared.showMainWindow()
            }
        }
    }

    @objc private func restartFinder() {
        FinderControl.restartFinder()
    }

    @objc private func performUpdateAction() {
        let updates = AppUpdateService.shared
        switch updates.state {
        case .available:
            updates.showAvailableUpdatePrompt()
        case .checking:
            break
        case .idle, .upToDate, .noRelease, .failed:
            updates.checkFromMenu()
        }
    }

    @objc private func showUpdateNotes() {
        AppUpdateService.shared.showAvailableUpdatePrompt()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
