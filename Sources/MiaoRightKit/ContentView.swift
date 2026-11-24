import AppKit
import MiaoRightShared
import SwiftUI
import UniformTypeIdentifiers

enum PreferencePage: String, CaseIterable, Identifiable {
    case menu, clipboard, vault, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .menu: L10n.text("右键菜单", "Context Menu")
        case .clipboard: L10n.text("剪贴板", "Clipboard")
        case .vault: L10n.text("保险箱", "Vault")
        case .general: L10n.text("通用", "General")
        }
    }
    var icon: String {
        switch self {
        case .menu: "cursorarrow"
        case .clipboard: "doc.on.clipboard"
        case .vault: "lock.shield"
        case .general: "slider.horizontal.3"
        }
    }
}

public struct ContentView: View {
    @Environment(ScriptStore.self) private var store
    @State private var page: PreferencePage = .menu
    @State private var status: ExtensionStatus?
    @State private var languageEpoch = 0
    @State private var updateRequestID = 0
    @State private var presentation = ActionResultPresentation.shared
    @State private var fileTasks = FileTaskPresentation.shared
    @State private var vaultTasks = VaultTaskPresentation.shared
    public init() {}
    init(initialPage: PreferencePage) { _page = State(initialValue: initialPage) }

    @Namespace private var navigationSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                if status == .disabled {
                    HStack(alignment: .top, spacing: 10) {
                        Label(L10n.text("启用 Finder 扩展后，即可使用右键菜单。", "Enable the Finder extension to use your context menu."), systemImage: "info.circle")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.text("打开系统设置", "Open System Settings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") { NSWorkspace.shared.open(url) }
                        }.controlSize(.small)
                    }.padding(18)
                    Divider()
                }
                Group {
                    if let request = vaultTasks.request { VaultTaskView(request: request).id(request.id) }
                    else if let request = fileTasks.request { FileTaskView(request: request).id(request.id) }
                    else if page == .menu { QuickMenuPreferencesView() }
                    else if page == .vault { VaultPageView() }
                    else { SettingsView(page: page, updateRequestID: updateRequestID) }
                }
                if let result = presentation.result, fileTasks.request == nil, vaultTasks.request == nil {
                    Divider()
                    FileOperationResultView(result: result)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 540)
        .defaultAppStorage(AppGroup.standardDefaults)
        .background { MainWindowFrostedBackground() }
        .ignoresSafeArea(.container, edges: .top)
        .tint(.blue)
        .navigationTitle(L10n.text("妙右", "MiaoRight"))
        .id(languageEpoch)
        .onAppear {
            store.loadIfNeeded(); AppearanceManager.apply()
            if AppUpdateService.shared.consumePreferencesRequest() {
                page = .general
                updateRequestID = AppUpdateService.shared.preferencesRequestID
            } else if SettingsActionStorage.shared.consumeGeneralPageRequest() {
                page = .general
            }
        }
        .task { await refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            _ = SettingsActionStorage.shared.consumeGeneralPageRequest()
            page = .general
        }
        .onReceive(NotificationCenter.default.publisher(for: .showUpdatePreferences)) { _ in
            page = .general
            updateRequestID = AppUpdateService.shared.preferencesRequestID
            _ = AppUpdateService.shared.consumePreferencesRequest()
        }
        .onChange(of: page) { _, page in
            if page != .general { updateRequestID = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: L10n.languageChangedNotification)) { _ in languageEpoch += 1 }
    }

    private var header: some View {
        ZStack {
            HStack {
                Spacer()
                Button { fileTasks.request = nil; vaultTasks.request = nil; page = .general } label: {
                    Image(systemName: status == .active ? "checkmark.circle" : "puzzlepiece.extension")
                        .font(.system(size: 14)).foregroundStyle(status == .active ? Color.secondary : Color.orange)
                        .frame(width: 28, height: 28).contentShape(Circle())
                }.buttonStyle(.plain).disabled(fileTasks.isBusy || vaultTasks.isBusy).help(statusText).accessibilityLabel(statusText)
            }.padding(.trailing, 20)
            HStack(spacing: 2) {
                ForEach(PreferencePage.allCases) { entry in
                    Button { fileTasks.request = nil; vaultTasks.request = nil; page = entry } label: {
                        Label(entry.title, systemImage: entry.icon)
                            .font(.system(size: 12, weight: page == entry ? .semibold : .medium))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background {
                                if page == entry {
                                    Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency ? 1 : 0.85))
                                        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                        .matchedGeometryEffect(id: "selectedPreference", in: navigationSelection)
                                }
                            }
                            .foregroundStyle(page == entry ? Color.primary : Color.secondary)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).disabled(fileTasks.isBusy || vaultTasks.isBusy)
                    .accessibilityValue(page == entry ? L10n.text("当前页面", "Selected") : "")
                    .accessibilityAddTraits(page == entry ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1), value: page)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.text("设置页面", "Settings Pages"))
        }
        .frame(height: 64)
    }
    private var statusText: String {
        switch status {
        case .active: L10n.text("右键菜单已就绪", "Finder menu ready")
        case .enabledNotRunning: L10n.text("右键菜单等待访达加载", "Finder menu waiting to load")
        case .disabled: L10n.text("右键菜单需要启用 Finder 扩展", "Finder menu needs its extension")
        case nil: L10n.text("正在检查右键菜单…", "Checking the Finder menu…")
        }
    }
    private func refreshStatus() async {
        status = await Task.detached(priority: .utility) { ExtensionStatusService.checkStatus() }.value
    }
}

struct PreferenceHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 14)
    }
}

/// 折叠入口整行响应点击，避免只能瞄准小箭头。
struct PreferenceDisclosureStyle: DisclosureGroupStyle {
    let icon: String
    let summary: String

    func makeBody(configuration: Configuration) -> some View {
        PreferenceDisclosureBody(configuration: configuration, icon: icon, summary: summary)
    }
}

private struct PreferenceDisclosureBody: View {
    let configuration: DisclosureGroupStyleConfiguration
    let icon: String
    let summary: String
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                        Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                        .frame(width: 12).accessibilityHidden(true)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(hovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityValue(configuration.isExpanded ? L10n.text("已展开", "Expanded") : L10n.text("已折叠", "Collapsed"))
            if configuration.isExpanded {
                configuration.content.padding(.leading, 32).padding(.bottom, 8)
            } else {
                Divider()
            }
        }
    }
}

struct PreferenceRow<Control: View>: View {
    let title: String
    let icon: String
    var detail: String? = nil
    @ViewBuilder var control: Control
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let detail, !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                control.controlSize(.small)
            }
            .padding(.vertical, 16)
            Divider()
        }
    }
}

struct QuickMenuPreferencesView: View {
    @Environment(ScriptStore.self) private var store
    @State private var showingApps = false
    @State private var showingFeatures = false
    @State private var preview = false
    @State private var message: String?
    @State private var installedTerminals: [String] = []
    @State private var cutState = CutClipboard.load()

    private var enabledApps: [Script] { store.scripts.filter { $0.isEnabled && QuickMenuPlan.isApplication(name: $0.name, content: $0.content) } }
    private var extras: [Script] { store.scripts.filter { $0.isEnabled && !QuickAccessPreferences.isCore($0) } }
    private var appCandidates: [Script] {
        store.scripts.filter { script in
            guard QuickMenuPlan.isApplication(name: script.name, content: script.content) else { return false }
            return script.isEnabled || QuickAccessPreferences.applicationURL(for: script).map { FileManager.default.fileExists(atPath: $0.path) } == true
        }
    }
    private var terminalOptions: [String] {
        QuickMenuPlan.terminalNames.filter { installedTerminals.contains($0) || isEnabled($0) }
    }
    private var terminal: Binding<String> {
        Binding(get: { QuickMenuPlan.terminalNames.first(where: isEnabled) ?? "" }, set: { value in
            for name in QuickMenuPlan.terminalNames { QuickAccessPreferences.setEnabled(name, enabled: name == value, store: store) }
        })
    }

    var body: some View {
        Group {
            if showingFeatures {
                AddedFeaturePicker { showingFeatures = false }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    PreferenceHeader(title: L10n.text("右键菜单", "Context Menu"), subtitle: L10n.text("只保留你常用的操作。", "Keep the actions you use."))
                    PreferenceRow(title: L10n.text("复制文件路径", "Copy File Path"), icon: "link", detail: L10n.text("一键复制所选文件或文件夹的完整路径", "Copy the full path of selected files or folders")) {
                        Toggle(L10n.text("复制文件路径", "Copy File Path"), isOn: binding("复制路径")).labelsHidden().toggleStyle(.switch)
                    }
                    PreferenceRow(title: L10n.text("用应用打开", "Open with App"), icon: "app", detail: appSummary) {
                        Button { showingApps.toggle() } label: {
                            HStack(spacing: 4) {
                                Text(L10n.text("选择应用", "Choose Apps"))
                                Image(systemName: showingApps ? "chevron.down" : "chevron.right")
                            }.font(.system(size: 12))
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    if showingApps { applications }
                    PreferenceRow(title: L10n.text("在终端打开", "Open in Terminal"), icon: "terminal", detail: L10n.text("选中文件时打开所在文件夹", "For files, open their enclosing folder")) {
                        Picker(L10n.text("终端应用", "Terminal App"), selection: terminal) {
                            Text(L10n.text("不显示", "Hidden")).tag("")
                            ForEach(terminalOptions, id: \.self) { name in
                                Text(terminalTitle(name)).tag(name)
                            }
                        }.labelsHidden().fixedSize()
                    }
                    PreferenceRow(title: L10n.text("剪切与粘贴", "Cut and Paste"), icon: "scissors", detail: L10n.text("剪切后，在目标文件夹右键粘贴", "Cut, then right-click the destination folder to paste")) {
                        Toggle(L10n.text("剪切与粘贴", "Cut and Paste"), isOn: Binding(
                            get: { isEnabled(ActionID.cut) || isEnabled(ActionID.paste) },
                            set: { value in for name in [ActionID.cut, ActionID.paste] { QuickAccessPreferences.setEnabled(name, enabled: value, store: store) } }
                        )).labelsHidden().toggleStyle(.switch)
                    }
                    if let cut = cutState {
                        HStack {
                            Text(L10n.text("\(cut.paths.count) 项等待移动", "\(cut.paths.count) items ready to move")).font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.text("取消剪切", "Cancel Cut")) { CutClipboard.clear(); cutState = nil; message = L10n.text("已取消剪切。", "Cut cancelled.") }
                        }.padding(.vertical, 10)
                    }
                    QuickFilePreferencesView()
                    if !extras.isEmpty {
                        DisclosureGroup(L10n.text("其他已添加功能（\(extras.count)）", "Other Added Actions (\(extras.count))")) {
                            ForEach(extras) { script in
                                PreferenceRow(title: ActionNames.name(script.name), icon: script.icon, detail: ScriptLibrary.libraryScript(named: script.name).map { ActionNames.description($0.description) }) {
                                    Button(L10n.text("移除", "Remove")) { var updated = script; updated.isEnabled = false; store.updateScript(updated) }.buttonStyle(.borderless)
                                }
                            }
                        }.disclosureGroupStyle(PreferenceDisclosureStyle(icon: "list.bullet", summary: L10n.text("查看或移除已添加的附加操作", "Review or remove your extra actions"))).padding(.top, 12)
                    }
                    HStack {
                        Button { showingFeatures = true } label: { Label(L10n.text("添加功能", "Add Action"), systemImage: "plus") }
                        Spacer()
                        Button(L10n.text("预览右键菜单", "Preview Menu")) { preview.toggle() }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $preview, arrowEdge: .bottom) { QuickMenuPreview() }
                    }.padding(.top, 24)
                    if let message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 14).accessibilityAddTraits(.updatesFrequently) }
                    }.frame(maxWidth: 640, alignment: .leading).padding(28).frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { refreshApplications(); cutState = CutClipboard.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshApplications(); cutState = CutClipboard.load() }
        .onReceive(NotificationCenter.default.publisher(for: ScriptExecutor.executionCompletedNotification)) { _ in cutState = CutClipboard.load() }
    }

    private var appSummary: String {
        enabledApps.isEmpty ? L10n.text("添加本机常用应用，右键即可打开", "Choose installed apps for quick access")
            : enabledApps.map { QuickMenuPlan.applicationTitle(QuickAccessPreferences.model($0)) }.joined(separator: L10n.text("、", ", "))
    }
    private var applications: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(appCandidates) { script in
                let url = QuickAccessPreferences.applicationURL(for: script)
                HStack(spacing: 9) {
                    if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(QuickMenuPlan.applicationTitle(QuickAccessPreferences.model(script))).font(.system(size: 12))
                        if url.map({ FileManager.default.fileExists(atPath: $0.path) }) != true {
                            Text(L10n.text("未找到应用，请重新选择", "App missing; choose it again")).font(.system(size: 11)).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Toggle(QuickMenuPlan.applicationTitle(QuickAccessPreferences.model(script)), isOn: Binding(
                        get: { store.scripts.first(where: { $0.id == script.id })?.isEnabled ?? false },
                        set: { enabled in var value = script; value.isEnabled = enabled; store.updateScript(value) }
                    )).labelsHidden().toggleStyle(.checkbox)
                }
            }
            Button { chooseApplications() } label: { Label(L10n.text("添加应用…", "Add Apps…"), systemImage: "plus") }
            Text(L10n.text("也可以将 App 拖到这里。", "You can also drop apps here.")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 8)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in message = QuickAccessPreferences.addApplication(url, store: store) }
                }
            }
            return !providers.isEmpty
        }
    }
    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = L10n.text("添加", "Add")
        panel.message = L10n.text("选择常用的 Mac 应用", "Choose your frequently used Mac apps")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { if let error = QuickAccessPreferences.addApplication(url, store: store) { message = error } }
    }
    private func isEnabled(_ name: String) -> Bool { store.scripts.contains { $0.name == name && $0.isEnabled } }
    private func binding(_ name: String) -> Binding<Bool> { Binding(get: { isEnabled(name) }, set: { QuickAccessPreferences.setEnabled(name, enabled: $0, store: store) }) }
    private func refreshApplications() {
        installedTerminals = QuickMenuPlan.terminalNames.filter { name in
            (QuickAccessPreferences.bundles[name] ?? []).contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        }
    }
    private func terminalTitle(_ name: String) -> String {
        let title = name == "在终端中打开" ? L10n.text("终端", "Terminal") : QuickMenuPlan.applicationTitle(.init(id: UUID(), name: name, icon: "terminal"))
        return installedTerminals.contains(name) ? title : title + L10n.text("（未找到）", " (missing)")
    }
}

private enum AddedFeatureGroup: String, CaseIterable, Identifiable {
    case archives, files, sharing, images, development, utilities
    var id: String { rawValue }
    var title: String {
        switch self {
        case .archives: L10n.text("压缩与解压", "Compression and Extraction")
        case .files: L10n.text("新建与整理", "Create and Organize")
        case .sharing: L10n.text("复制与分享", "Copy and Share")
        case .images: L10n.text("图片与 PDF", "Images and PDF")
        case .development: L10n.text("开发工具", "Developer Tools")
        case .utilities: L10n.text("其他工具", "Other Tools")
        }
    }
    static func group(for entry: ScriptLibrary.LibraryScript) -> Self {
        if ["压缩…", "解压", "压缩为 ZIP", "解压到当前文件夹", "创建 TAR.GZ", "解压 TAR.GZ", "压缩为 7Z", "解压 7Z"].contains(entry.name) { return .archives }
        if entry.category == .media { return .images }
        if entry.name.hasPrefix("复制") || entry.category == .share || entry.name == ActionID.airdrop { return .sharing }
        switch entry.category {
        case .organize: return .files
        case .dev: return .development
        default: return .utilities
        }
    }
}

private struct AddedFeaturePicker: View {
    @Environment(ScriptStore.self) private var store
    let onBack: () -> Void
    @State private var search = ""
    @State private var selectedGroup: AddedFeatureGroup?

    private var matches: [ScriptLibrary.LibraryScript] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScriptLibrary.allScripts.filter { entry in
            !QuickAccessPreferences.isCore(entry.toScript())
                && (selectedGroup == nil || AddedFeatureGroup.group(for: entry) == selectedGroup)
                && (query.isEmpty || (ActionNames.name(entry.name) + " " + ActionNames.description(entry.description) + " " + entry.name + " " + entry.description).localizedCaseInsensitiveContains(query))
        }
    }
    private var groups: [AddedFeatureGroup] {
        AddedFeatureGroup.allCases.filter { group in matches.contains { AddedFeatureGroup.group(for: $0) == group } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button { onBack() } label: { Label(L10n.text("返回右键菜单", "Back to Context Menu"), systemImage: "chevron.left") }
                    .buttonStyle(.borderless).padding(.bottom, 18)
                PreferenceHeader(title: L10n.text("添加功能", "Add Action"), subtitle: L10n.text("浏览支持的功能，按需添加到右键菜单。", "Browse supported actions and add the ones you need."))
                HStack(spacing: 8) {
                    TextField(L10n.text("搜索功能名称或用途", "Search by name or purpose"), text: $search).textFieldStyle(.roundedBorder)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel(L10n.text("清除搜索", "Clear Search"))
                    }
                }
                HStack {
                    Picker(L10n.text("功能分类", "Action Category"), selection: $selectedGroup) {
                        Text(L10n.text("全部功能", "All Actions")).tag(Optional<AddedFeatureGroup>.none)
                        ForEach(AddedFeatureGroup.allCases) { group in Text(group.title).tag(Optional(group)) }
                    }.labelsHidden().fixedSize().controlSize(.small)
                    Spacer(minLength: 8)
                    Text(L10n.text("共 \(matches.count) 项", "\(matches.count) actions"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.top, 12)
                Text(L10n.text("复制路径、常用应用、终端和剪切粘贴在上一页设置。", "Set up paths, apps, terminals, and cut and paste on the previous page."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            .frame(maxWidth: 640, alignment: .leading).padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if matches.isEmpty {
                        Text(L10n.text("没有找到匹配的功能。试试其他关键词，或查看全部功能。", "No matching actions. Try another keyword or view all actions."))
                            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 24)
                        Button(L10n.text("查看全部功能", "View All Actions")) { search = ""; selectedGroup = nil }.padding(.top, 12)
                    }
                    ForEach(groups) { group in
                        Text(group.title).font(.system(size: 13, weight: .semibold)).padding(.top, 24).padding(.bottom, 4)
                        ForEach(matches.filter { AddedFeatureGroup.group(for: $0) == group }, id: \.name) { entry in resultRow(entry) }
                    }
                }
                .frame(maxWidth: 640, alignment: .leading).padding(.horizontal, 28).padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }
    private func resultRow(_ entry: ScriptLibrary.LibraryScript) -> some View {
        let enabled = store.scripts.contains { $0.name == entry.name && $0.isEnabled }
        return PreferenceRow(title: ActionNames.name(entry.name), icon: entry.icon, detail: ActionNames.description(entry.description)) {
            if enabled {
                Label(L10n.text("已添加", "Added"), systemImage: "checkmark").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Button(L10n.text("添加", "Add")) { store.setLibraryScript(entry, isEnabled: true) }
            }
        }
    }
}

private struct QuickMenuPreview: View {
    @Environment(ScriptStore.self) private var store
    @State private var folder = true
    private var sections: [QuickMenuSection] {
        let url = URL(fileURLWithPath: folder ? "/Example/" : "/Example.txt", isDirectory: folder)
        let applicable = store.scripts.filter {
            $0.isEnabled && QuickAccessPreferences.isAvailable($0) && $0.appliesTo != .container && $0.matchesSelectionCount(1) && $0.matchesFiles([url])
        }
        return QuickMenuPlan.sections(for: applicable.map(QuickAccessPreferences.model))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("右键菜单预览", "Context Menu Preview")).font(.headline)
            Picker(L10n.text("示例选择", "Sample Selection"), selection: $folder) {
                Text(L10n.text("文件夹", "Folder")).tag(true)
                Text(L10n.text("文件", "File")).tag(false)
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if sections.isEmpty { Text(L10n.text("当前选择没有适用的操作。", "No actions apply to this selection.")).foregroundStyle(.secondary) }
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        if let title = section.title {
                            Label(title, systemImage: section.icon).font(.system(size: 13, weight: .medium))
                        }
                        ForEach(section.actions, id: \.id) { item in
                            Label(section.title == L10n.text("用应用打开", "Open with App") ? QuickMenuPlan.applicationTitle(item) : QuickMenuPlan.title(item), systemImage: item.icon)
                                .font(.system(size: 12)).padding(.leading, section.title == nil ? 0 : 18)
                                .foregroundStyle(item.name == ActionID.paste && CutClipboard.load() == nil ? Color.secondary : Color.primary)
                        }
                    }
                    if SharedDefaults.showOpenMainWindowMenuItem() { Label(L10n.text("打开妙右设置…", "Open MiaoRight Settings…"), systemImage: "gearshape").font(.system(size: 12)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(18).frame(width: 300, height: 360)
    }
}
