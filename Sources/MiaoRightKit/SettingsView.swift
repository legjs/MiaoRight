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
                Button(L10n.text("重新检查连接", "Check Connection")) { Task { await refresh() } }.buttonStyle(.borderless)
                if status == .enabledNotRunning {
                    Button(L10n.text("打开 Finder", "Open Finder")) { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }.buttonStyle(.borderless)
                }
            }.font(.system(size: 12)).padding(.top, 12)
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
                    Text(L10n.text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")", "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.top, 24)
        }
    }
    private var extensionDetail: String {
        switch status {
        case .active: L10n.text("已连接，可在 Finder 中使用右键菜单", "Connected; actions are available in Finder")
        case .enabledNotRunning: L10n.text("已启用，等待 Finder 加载；打开文件夹后再次检查", "Enabled; waiting for Finder. Open a folder, then check again.")
        case .disabled: L10n.text("请在系统设置中启用“妙右 Finder 扩展”", "Enable “MiaoRight Finder Extension” in System Settings")
        case nil: L10n.text("正在检查…", "Checking…")
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
