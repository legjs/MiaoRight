import AppKit
import MiaoRightShared
import SwiftUI

/// 主窗口内的两组偏好;不再把所有设置堆在同一长页面。
struct SettingsView: View {
    var page: PreferencePage = .general
    var updateRequestID: Int = 0
    @Environment(MonitoredFolderService.self) private var folders
    @State private var history = ClipboardHistoryService.shared
    @State private var status: ExtensionStatus?
    @State private var authorized = AutoPaste.isAuthorized()
    @State private var appearance = AppearanceManager.current
    @State private var loginState = AppPolicies.loginItemState()
    @State private var loginError: String?
    @State private var updates = AppUpdateService.shared
    @State private var focusUpdateResult = false
    @State private var menuBarIcon = AppPreferences.showMenuBarIcon
    @State private var dockIcon = AppPreferences.showDockIcon
    @State private var allFolders = MonitoredFolders.monitorAllFoldersEnabled
    @State private var maxItems = ClipboardStore.maxItems
    @State private var confirmingClear = false
    @State private var error: String?
    @State private var checkingFinderStatus = false
    @State private var finderCheckMessage: String?
    @AppStorage(AppPreferences.showActionNotificationsKey) private var showNotifications = true
    @AppStorage(ClipboardHistoryService.autoPasteKey) private var autoPaste = true
    @AppStorage(SharedDefaults.showOpenMainWindowMenuItemKey, store: SharedDefaults.userDefaults) private var showSettingsItem = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if page == .clipboard { clipboard }
                    else { general }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).padding(.top, 14) }
                }.frame(maxWidth: 640, alignment: .leading).padding(28).frame(maxWidth: .infinity)
            }
            .task(id: updateRequestID) {
                guard page == .general, updateRequestID > 0 else { return }
                focusUpdateResult = true
                await Task.yield()
                proxy.scrollTo("software-update", anchor: .top)
            }
            .onChange(of: updates.isChecking) { _, isChecking in
                guard !isChecking, focusUpdateResult else { return }
                focusUpdateResult = false
                proxy.scrollTo("software-update", anchor: .top)
            }
        }
        .defaultAppStorage(AppGroup.standardDefaults)
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await refresh() } }
        .confirmationDialog(L10n.text("清除未收藏的剪贴板历史？", "Clear unfavorited clipboard history?"), isPresented: $confirmingClear) {
            Button(L10n.text("清除历史", "Clear History"), role: .destructive) { history.clearUnfavoritedHistory() }
            Button(L10n.text("取消", "Cancel"), role: .cancel) {}
        } message: { Text(L10n.text("未收藏的文字、图片和文件记录将被清除，收藏条目会保留。此操作无法撤销。", "Unfavorited text, image and file records will be removed. Favorites will be kept. This cannot be undone.")) }
    }

    private var clipboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreferenceHeader(title: L10n.text("剪贴板", "Clipboard"), subtitle: L10n.text("找回刚才复制的文字、图片和文件。", "Find recently copied text, images, and files."))
            PreferenceRow(title: L10n.text("记录剪贴板历史", "Record Clipboard History"), icon: "clock.arrow.circlepath", detail: L10n.text("仅保存在这台 Mac 上，可随时暂停", "Saved only on this Mac; pause at any time")) {
                Toggle(L10n.text("记录剪贴板历史", "Record Clipboard History"), isOn: Binding(get: { history.recordingEnabled }, set: { history.setRecordingEnabled($0) })).labelsHidden().toggleStyle(.switch)
            }
            PreferenceRow(title: L10n.text("呼出快捷键", "Toggle Shortcut"), icon: "keyboard") { HotkeyRecorderView() }
            PreferenceRow(title: L10n.text("粘贴倒数第二条", "Paste Second-Most-Recent Item"), icon: "doc.on.clipboard",
                          detail: L10n.text("粘贴后，⌘V 仍可粘贴原来的内容", "Afterward, ⌘V still pastes the original clipboard")) {
                HotkeyRecorderView(shortcut: .previousItem)
            }
            PreferenceRow(title: L10n.text("选中后直接粘贴", "Paste on Select"), icon: "return", detail: L10n.text("关闭时只复制，再按 ⌘V 粘贴", "When off, copy first, then press ⌘V to paste")) {
                Toggle(L10n.text("选中后直接粘贴", "Paste on Select"), isOn: $autoPaste).labelsHidden().toggleStyle(.switch)
            }
            if !authorized {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(L10n.text("直接粘贴需要辅助功能权限。仍可从面板复制后按 ⌘V。", "Direct paste needs Accessibility permission. You can still copy from the panel and press ⌘V.")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button(L10n.text("去授权", "Authorize")) { AutoPaste.openAuthorizationSettings() }.controlSize(.small)
                }.padding(.vertical, 13)
            }
            PreferenceRow(title: L10n.text("历史保留时间", "Keep History For"), icon: "calendar", detail: L10n.text("超出保留时间的记录会自动清除", "Older records are removed automatically")) {
                Picker(L10n.text("历史保留时间", "Keep History For"), selection: Binding(get: { history.retentionDays }, set: { history.setRetentionDays($0) })) {
                    Text(L10n.text("7 天", "7 Days")).tag(7)
                    Text(L10n.text("30 天", "30 Days")).tag(30)
                    Text(L10n.text("直到手动清理", "Until Cleared")).tag(0)
                }.labelsHidden().fixedSize()
            }
            Button(L10n.text("查看历史记录", "Show History")) { ClipboardFloatingPanel.shared.slideIn() }
                .buttonStyle(.borderedProminent).controlSize(.regular).padding(.top, 24)
            Text(history.recordingEnabled
                 ? L10n.text("面板关闭后仍会记录；关闭“记录剪贴板历史”才会暂停。", "Closing the panel keeps recording. Turn off “Record Clipboard History” to pause.")
                 : L10n.text("记录已暂停。再次开启时只记录新的复制内容。", "Recording paused. Resuming captures only new copies."))
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
            FavoriteSnippetsPreferencesView().padding(.top, 20)
            DisclosureGroup(L10n.text("存储与清理", "Storage and Cleanup")) {
                VStack(alignment: .leading, spacing: 0) {
                    PreferenceRow(title: L10n.text("记录条数上限", "Item Limit"), icon: "list.number", detail: L10n.text("收藏不计入上限，也不会自动过期", "Favorites do not count toward the limit and never expire automatically")) {
                        Stepper("\(maxItems)", value: $maxItems, in: 10...1000, step: 10).fixedSize()
                            .onChange(of: maxItems) { _, value in AppGroup.standardDefaults.set(value, forKey: ClipboardStore.maxItemsKey) }
                    }
                    PreferenceRow(title: L10n.text("保存位置", "Storage Location"), icon: "folder", detail: ClipboardStore.cacheDirectory.path) {
                        Button(L10n.text("更改…", "Change…")) { changeCacheDirectory() }
                    }
                    PreferenceRow(title: L10n.text("清除未收藏历史", "Clear Unfavorited History"), icon: "trash", detail: L10n.text("保留收藏条目，不影响原文件", "Keep favorites without changing original files")) {
                        Button(L10n.text("清除…", "Clear…"), role: .destructive) { confirmingClear = true }
                    }
                }
            }.disclosureGroupStyle(PreferenceDisclosureStyle(icon: "externaldrive", summary: L10n.text("记录上限、保存位置与历史清理", "History limit, storage location, and cleanup"))).padding(.top, 20)
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreferenceHeader(title: L10n.text("通用", "General"), subtitle: L10n.text("设置一次，之后随手使用。", "Set it up once, then keep it close at hand."))
            setupChecklist
            PreferenceRow(title: L10n.text("登录时启动", "Launch at Login"), icon: "power", detail: loginDetail) {
                Toggle(L10n.text("登录时启动", "Launch at Login"), isOn: Binding(get: { loginState.isRequested }, set: { setLoginEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            if loginState == .requiresApproval || loginError != nil {
                HStack(alignment: .top, spacing: 12) {
                    Text(loginError ?? L10n.text("还需要在系统设置中允许妙右登录时启动。", "Allow MiaoRight to launch at login in System Settings."))
                        .font(.system(size: 12)).foregroundStyle(loginError == nil ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(L10n.text("系统设置…", "System Settings…")) { AppPolicies.openLoginItemSettings() }.controlSize(.small)
                }.padding(.vertical, 12)
            }
            PreferenceRow(title: L10n.text("语言", "Language"), icon: "globe") {
                Picker(L10n.text("语言", "Language"), selection: Binding(
                    get: { AppLanguage(rawValue: AppGroup.userDefaults?.string(forKey: L10n.storageKey) ?? "") ?? .system },
                    set: { L10n.setLanguage($0) }
                )) { ForEach(AppLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) } }.labelsHidden().fixedSize()
            }
            PreferenceRow(title: L10n.text("外观", "Appearance"), icon: "circle.lefthalf.filled", detail: L10n.text("浅色与深色均保留半透明毛玻璃", "Translucent frosted glass in both light and dark appearances")) {
                Picker(L10n.text("外观", "Appearance"), selection: $appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.labelsHidden().fixedSize().onChange(of: appearance) { _, mode in AppearanceManager.current = mode }
            }
            PreferenceRow(title: L10n.text("生效范围", "Where to Show Actions"), icon: "folder") {
                Picker(L10n.text("生效范围", "Where to Show Actions"), selection: $allFolders) {
                    Text(L10n.text("所有文件夹", "All Folders")).tag(true)
                    Text(L10n.text("指定文件夹", "Selected Folders")).tag(false)
                }.labelsHidden().fixedSize().onChange(of: allFolders) { _, enabled in MonitoredFolders.monitorAllFoldersEnabled = enabled }
            }
            if !allFolders {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(folders.folders) { folder in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(folder.name).font(.system(size: 12))
                                Text(folder.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button(L10n.text("移除", "Remove")) { folders.removeFolder(folder) }.controlSize(.small)
                        }
                    }
                    Button(L10n.text("添加文件夹…", "Add Folder…")) { folders.addFolders() }
                    if let lastError = folders.lastError { Text(lastError).foregroundStyle(.red) }
                    if folders.folders.isEmpty { Text(L10n.text("添加文件夹后，右键菜单才会在其中出现。", "Add a folder so its context menu can show your actions.")).font(.system(size: 12)).foregroundStyle(.secondary) }
                }.padding(.vertical, 14)
            }
            PreferenceRow(title: L10n.text("Finder 扩展", "Finder Extension"), icon: "puzzlepiece.extension", detail: extensionDetail) {
                Button(L10n.text("系统设置…", "System Settings…")) { openExtensions() }
            }
            HStack {
                Button(checkingFinderStatus ? L10n.text("正在检查…", "Checking…") : L10n.text("重新检查右键菜单", "Check Finder Menu")) {
                    Task { await recheckFinderMenu() }
                }
                    .buttonStyle(.borderless)
                    .disabled(checkingFinderStatus)
                    .help(L10n.text("重新检查访达是否已加载妙右右键扩展，不会联网。", "Check whether Finder has loaded the MiaoRight extension. This does not use the network."))
                if status == .enabledNotRunning {
                    Button(L10n.text("打开 Finder", "Open Finder")) { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }.buttonStyle(.borderless)
                }
            }.font(.system(size: 12)).padding(.top, 12)
            if let finderCheckMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: finderCheckIcon).foregroundStyle(finderCheckColor)
                    Text(finderCheckMessage).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .padding(.top, 8)
            }
            DisclosureGroup(L10n.text("其他程序的右键菜单", "Other Apps’ Context Menus")) {
                ExtensionsManagementView()
            }.disclosureGroupStyle(PreferenceDisclosureStyle(icon: "puzzlepiece.extension", summary: L10n.text("管理其他 App 添加的菜单项", "Manage menu items added by other apps"))).padding(.top, 20)
            DisclosureGroup(L10n.text("更多偏好", "More Preferences")) {
                VStack(spacing: 0) {
                    PreferenceRow(title: L10n.text("显示菜单栏图标", "Show Menu Bar Icon"), icon: "menubar.rectangle") {
                        Toggle(L10n.text("显示菜单栏图标", "Show Menu Bar Icon"), isOn: Binding(get: { menuBarIcon }, set: { value in
                            let result = AppVisibilityCoordinator.setMenuBarIconVisible(value); menuBarIcon = result.showMenuBarIcon; dockIcon = result.showDockIcon
                        })).labelsHidden().toggleStyle(.switch)
                    }
                    PreferenceRow(title: L10n.text("显示 Dock 图标", "Show Dock Icon"), icon: "dock.rectangle") {
                        Toggle(L10n.text("显示 Dock 图标", "Show Dock Icon"), isOn: Binding(get: { dockIcon }, set: { value in
                            let result = AppVisibilityCoordinator.setDockIconVisible(value); menuBarIcon = result.showMenuBarIcon; dockIcon = result.showDockIcon
                        })).labelsHidden().toggleStyle(.switch)
                    }
                    PreferenceRow(title: L10n.text("操作完成通知", "Action Notifications"), icon: "bell") { Toggle(L10n.text("操作完成通知", "Action Notifications"), isOn: $showNotifications).labelsHidden().toggleStyle(.switch) }
                    PreferenceRow(title: L10n.text("在右键中显示设置入口", "Show Settings in Context Menu"), icon: "gearshape") { Toggle(L10n.text("在右键中显示设置入口", "Show Settings in Context Menu"), isOn: $showSettingsItem).labelsHidden().toggleStyle(.switch) }
                }
            }.disclosureGroupStyle(PreferenceDisclosureStyle(icon: "slider.horizontal.3", summary: L10n.text("菜单栏、Dock 与操作通知", "Menu bar, Dock, and action notifications")))
            AppUpdatePreferencesView().padding(.top, 20).id("software-update")
            HStack(spacing: 10) {
                if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon).resizable().frame(width: 36, height: 36).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("妙右", "MiaoRight")).font(.system(size: 13, weight: .medium))
                    Text(L10n.text("版本 \(AppUpdateService.currentVersion)", "Version \(AppUpdateService.currentVersion)"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.top, 24)
        }
    }

    @ViewBuilder
    private var setupChecklist: some View {
        if !setupItemsComplete {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("开始使用妙右", "Get MiaoRight Ready"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.text("完成下面几项后，右键菜单和剪贴板才会工作。", "Complete these items to enable the context menu and clipboard."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(setupProgressText).font(.system(size: 11)).foregroundStyle(.secondary)
                }

                if !isAtExpectedInstallLocation {
                    setupStep(
                        icon: "folder.badge.gearshape",
                        title: L10n.text("把妙右放进“应用程序”", "Move MiaoRight to Applications"),
                        detail: L10n.text("右键菜单需要从 /Applications/MiaoRight.app 运行。", "The Finder menu requires /Applications/MiaoRight.app."),
                        action: L10n.text("打开文件夹", "Open Folder")
                    ) { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true)) }
                }

                if status != .active {
                    setupStep(
                        icon: "cursorarrow.click",
                        title: L10n.text("启用 Finder 右键菜单", "Enable the Finder Menu"),
                        detail: status == .enabledNotRunning
                            ? L10n.text("扩展已开启，点一下让访达重新加载。", "The extension is on. Reload Finder to finish.")
                            : L10n.text("在系统设置的“访达”扩展中打开妙右。", "Turn on MiaoRight in Finder Extensions."),
                        action: status == .enabledNotRunning
                            ? L10n.text("重启访达", "Reload Finder")
                            : L10n.text("打开设置", "Open Settings")
                    ) {
                        if status == .enabledNotRunning {
                            FinderControl.restartFinder()
                            Task { await refresh() }
                        } else {
                            openExtensions()
                        }
                    }
                }

                if !history.recordingEnabled {
                    setupStep(
                        icon: "doc.on.clipboard",
                        title: L10n.text("开启剪贴板历史", "Turn On Clipboard History"),
                        detail: L10n.text("开启后，按 ⇧⌘V 就能找回刚才复制的内容。", "Then press ⇧⌘V to find what you copied."),
                        action: L10n.text("立即开启", "Turn On")
                    ) { history.setRecordingEnabled(true) }
                }

                if !authorized {
                    setupStep(
                        icon: "hand.raised",
                        title: L10n.text("允许直接粘贴", "Allow Direct Paste"),
                        detail: L10n.text("不开启也可以先从面板复制，再按 ⌘V。", "You can also copy from the panel and press ⌘V."),
                        action: L10n.text("去授权", "Authorize")
                    ) { AutoPaste.openAuthorizationSettings() }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.blue.opacity(0.18)))
            .padding(.bottom, 14)
        }
    }

    private var isAtExpectedInstallLocation: Bool {
        Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/MiaoRight.app"
    }

    private var setupCompletedCount: Int {
        [isAtExpectedInstallLocation, status == .active, history.recordingEnabled].filter { $0 }.count
    }

    private var setupItemsComplete: Bool { setupCompletedCount == 3 }

    private var setupProgressText: String {
        L10n.text("\(setupCompletedCount) / 3 已完成", "\(setupCompletedCount) of 3 complete")
    }

    private func setupStep(icon: String, title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.blue).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action, action: perform).controlSize(.small)
        }
    }
    private var extensionDetail: String {
        switch status {
        case .active: L10n.text("右键菜单已就绪，可在访达中使用", "The Finder menu is ready")
        case .enabledNotRunning: L10n.text("扩展已启用，访达尚未加载；打开文件夹后再次检查", "Enabled; Finder has not loaded it yet. Open a folder and check again.")
        case .disabled: L10n.text("请在系统设置中启用“妙右 Finder 扩展”", "Enable “MiaoRight Finder Extension” in System Settings")
        case nil: L10n.text("正在检查右键菜单…", "Checking the Finder menu…")
        }
    }
    private var loginDetail: String {
        switch loginState {
        case .requiresApproval: L10n.text("等待系统批准，批准后才会自动启动", "Waiting for approval before automatic launch")
        case .unavailable: L10n.text("系统尚未识别登录项，可尝试重新开启", "The login item is not registered; try enabling it again")
        default: L10n.text("登录这台 Mac 后自动启动妙右", "Start MiaoRight when you log in to this Mac")
        }
    }
    private func setLoginEnabled(_ enabled: Bool) {
        loginError = nil
        do { try AppPolicies.setLoginItemEnabled(enabled) }
        catch { loginError = L10n.text("无法更改登录启动：", "Could not change launch at login: ") + error.localizedDescription }
        loginState = AppPolicies.loginItemState()
    }
    private func refresh() async {
        authorized = AutoPaste.isAuthorized(); folders.refresh(); loginState = AppPolicies.loginItemState()
        status = await Task.detached(priority: .utility) { ExtensionStatusService.checkStatus() }.value
    }

    private func recheckFinderMenu() async {
        checkingFinderStatus = true
        finderCheckMessage = nil
        await refresh()
        checkingFinderStatus = false
        switch status {
        case .active:
            finderCheckMessage = L10n.text("检查完成，右键菜单已就绪。可以在访达中右键测试。", "Check complete. The Finder menu is ready; right-click in Finder to test it.")
        case .enabledNotRunning:
            finderCheckMessage = L10n.text("扩展已启用，但访达还没有加载它。可以点右侧的“打开 Finder”。", "The extension is enabled, but Finder has not loaded it. Open a Finder window to continue.")
        case .disabled:
            finderCheckMessage = L10n.text("Finder 扩展尚未启用。请点“系统设置…”打开它。", "The Finder extension is off. Use System Settings to enable it.")
        case nil:
            finderCheckMessage = L10n.text("暂时无法读取扩展状态，请稍后重试。", "Could not read the extension status. Try again shortly.")
        }
    }

    private var finderCheckIcon: String {
        switch status {
        case .active: "checkmark.circle.fill"
        case .enabledNotRunning: "clock.fill"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var finderCheckColor: Color {
        switch status {
        case .active: .green
        case .enabledNotRunning: .orange
        default: .red
        }
    }
    private func openExtensions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") { NSWorkspace.shared.open(url) }
    }
    private func changeCacheDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = L10n.text("选择新的记录位置。已有历史会保留在原位置。", "Choose a new history location. Existing history stays in its original location.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        AppGroup.standardDefaults.set(url.path, forKey: ClipboardStore.cacheDirKey)
        history.reloadStorage()
    }
}
