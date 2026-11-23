import MiaoRightShared
import SwiftUI

/// 动作库页的浏览范围(顶层 = 无场景归属的基础动作)
enum ActionLibraryFilter: Hashable {
    case all
    case top
    case scene(BuiltInMenuCategory)
}

/// 工作台:动作库浏览(场景筛选 + 磁贴墙)+ 右键菜单实时预览。
/// 开关任何动作,预览即时变化。
struct StudioView: View {
    @Environment(ScriptStore.self) private var scriptStore
    @Environment(MonitoredFolderService.self) private var monitoredFolderService

    @Binding var filter: ActionLibraryFilter
    @Binding var searchText: String

    let onOpenSettings: () -> Void
    let onNewComposed: () -> Void
    let onEditComposed: (Script) -> Void

    @State private var extensionStatus: ExtensionStatus?
    /// 菜单预览中已展开的子菜单(场景名)
    @State private var expandedMenus: Set<String> = []

    private static let frequentSeeds = ["复制路径", "剪切", "粘贴", "新建 TXT 文档"]

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            leftColumn
            menuPreviewColumn
                .frame(width: 350)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            extensionStatus = ExtensionStatusService.checkStatus()
        }
    }

    // MARK: - 左列:动作库浏览

    private var enabledNames: Set<String> {
        Set(scriptStore.scripts.filter(\.isEnabled).map(\.name))
    }

    private var allFoldersConfigured: Bool {
        MonitoredFolders.monitorAllFoldersEnabled || monitoredFolderService.monitoredFolderCount > 0
    }

    /// 分类 chips 固定,只有磁贴区滚动;右侧菜单预览固定
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !allFoldersConfigured {
                monitorHint
            }
            chipsRow
            // 拖拽创建的归宿是「快速打开」,入口只在其相关视图显示
            if showsDropZone {
                dropZoneBanner
            }
            tileGrid
        }
    }

    /// 拖拽横幅只在「全部 / 快速打开」视图显示(创建物均归快速打开体系)
    private var showsDropZone: Bool {
        switch filter {
        case .all: true
        case .top: false
        case .scene(let scene): scene == .quickOpen
        }
    }

    /// 拖拽快速创建:拖入 App 生成「用 XX 打开」,拖入文件夹生成「移动到 XX」
    private var dropZoneBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 12))
                .foregroundStyle(MiaoTheme.accent)
            Text(L10n.text("把 App 或文件夹拖到这里,快速创建菜单", "Drop an app or folder here to create an action"))
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MiaoTheme.accent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MiaoTheme.accent.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                createFromDroppedItem(url)
            }
        }
        return true
    }

    @MainActor
    private func createFromDroppedItem(_ url: URL) {
        let fm = FileManager.default
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let isApp = url.pathExtension.lowercased() == "app"
        let display = url.deletingPathExtension().lastPathComponent

        if isApp || isDirectory && !isApp {
            if isApp {
                let action = ComposedAction(steps: [
                    .init(op: "file.openWith", params: ["appPath": url.path]),
                ])
                scriptStore.addScript(Script(
                    name: L10n.text("用 \(display) 打开", "Open with \(display)"),
                    type: .composed, content: action.encoded(),
                    isEnabled: true, icon: "square.stack.3d.up",
                    appliesTo: .allItems, libraryCategory: BuiltInMenuCategory.quickOpen.rawValue
                ))
            } else {
                let action = ComposedAction(steps: [
                    .init(op: "file.move", params: ["folder": url.path]),
                ])
                scriptStore.addScript(Script(
                    name: L10n.text("移动到 \(display)", "Move to \(display)"),
                    type: .composed, content: action.encoded(),
                    isEnabled: true, icon: "square.stack.3d.up",
                    appliesTo: .allItems, libraryCategory: ScriptStore.topCategoryKey
                ))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.text("工作台", "Studio"))
                .font(.title2.weight(.bold))
            Spacer()
            Button {
                onNewComposed()
            } label: {
                Label(L10n.text("新建菜单", "New Action"), systemImage: "plus")
            }
            .buttonStyle(.miaoProminent)
            .fixedSize()
            let rows = tileItems
            let enabled = rows.filter(\.isEnabled).count
            Text(L10n.text("\(enabled)/\(rows.count) 已启用", "\(enabled)/\(rows.count) enabled"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.trailing, 10)
        }
    }

    private var monitorHint: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(MiaoTheme.accent)
            Text(L10n.text(
                "先在设置中添加监控文件夹(或开启「在所有文件夹生效」),动作才会出现在右键菜单。",
                "Add monitored folders in Settings (or enable all folders) for actions to appear in the context menu."
            ))
            .font(.system(size: 12))
            Spacer()
            Button(L10n.text("打开设置", "Settings")) {
                SettingsActionStorage.shared.showSettings()
            }
            .buttonStyle(.miaoSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MiaoTheme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(MiaoTheme.accent.opacity(0.25), lineWidth: 1))
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                MiaoChip(emoji: "⭐", title: L10n.text("全部", "All"), tint: MiaoTheme.accent, isSelected: filter == .all) {
                    filter = .all
                }
                MiaoChip(emoji: "✨", title: L10n.text("顶层", "Top-level"), tint: MiaoTheme.accentIndigo, isSelected: filter == .top) {
                    filter = .top
                }
                ForEach(BuiltInMenuCategory.allCases, id: \.self) { scene in
                    MiaoChip(
                        emoji: scene.emoji,
                        title: scene.rawValue,
                        tint: MiaoTheme.sceneColor(scene),
                        isSelected: filter == .scene(scene)
                    ) {
                        filter = .scene(scene)
                    }
                }
            }
        }
    }

    // MARK: - 磁贴墙

    /// 「顶层」归属的存储键(未知分类在右键菜单分组中自然落在顶层)
    private var topCategoryKey: String { ScriptStore.topCategoryKey }

    /// 动作的有效归属:用户改写值优先,否则跟随内置定义
    private func effectiveCategory(of definition: ScriptLibrary.LibraryScript,
                                   record: Script?) -> String? {
        record?.libraryCategory ?? definition.category?.rawValue
    }

    private var scopedBuiltins: [(script: ScriptLibrary.LibraryScript, effective: String?)] {
        let all = ScriptLibrary.allScripts
        let withEffective = all.map { definition -> (script: ScriptLibrary.LibraryScript, effective: String?) in
            let record = scriptStore.scripts.first { $0.name == definition.name }
            return (definition, effectiveCategory(of: definition, record: record))
        }
        switch filter {
        case .all:
            return withEffective
        case .top:
            return withEffective.filter { pair in
                guard let effective = pair.effective else { return true }
                return effective == topCategoryKey
            }
        case .scene(let scene):
            return withEffective.filter { $0.effective == scene.rawValue }
        }
    }

    // MARK: - 磁贴条目(内置定义 + 自建组合动作统一模型)

    struct TileItem {
        let name: String
        let isEnabled: Bool
        let disabledAt: Date?
        let effective: String?
        let builtin: ScriptLibrary.LibraryScript? // 非空 = 内置定义
        let custom: Script? // 非空 = 自建组合动作
    }

    private var tileItems: [TileItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        let recordsByName = Dictionary(uniqueKeysWithValues: scriptStore.scripts.map { ($0.name, $0) })

        var items: [TileItem] = scopedBuiltins.map { pair in
            let record = recordsByName[pair.script.name]
            return TileItem(
                name: pair.script.name,
                isEnabled: record?.isEnabled ?? false,
                disabledAt: record?.disabledAt,
                effective: pair.effective,
                builtin: pair.script,
                custom: nil
            )
        }
        // 自建组合动作:归属匹配当前筛选(顶层 = nil 或 __top__)
        for script in scriptStore.scripts where script.type == .composed {
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .top:
                matches = script.libraryCategory == nil || script.libraryCategory == ScriptStore.topCategoryKey
            case .scene(let scene): matches = script.libraryCategory == scene.rawValue
            }
            guard matches else { continue }
            items.append(TileItem(
                name: script.name,
                isEnabled: script.isEnabled,
                disabledAt: script.disabledAt,
                effective: script.libraryCategory ?? ScriptStore.topCategoryKey,
                builtin: nil,
                custom: script
            ))
        }

        return items
            .filter { item in
                guard !keyword.isEmpty else { return true }
                return item.name.localizedCaseInsensitiveContains(keyword)
            }
            .sorted { a, b in
                // 已启用在前(按名称);停用的按停用时间新→旧;无记录的最后
                if a.isEnabled != b.isEnabled { return a.isEnabled && !b.isEnabled }
                if a.isEnabled {
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                switch (a.disabledAt, b.disabledAt) {
                case (let x?, let y?):
                    if x != y { return x > y }
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    private var tileGrid: some View {
        let rows = tileItems
        // 固定三列:adaptive 会因滚动条出现/消失在每行 3~4 个之间跳动
        return ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
            if rows.isEmpty {
                Text(L10n.text("没有匹配的菜单 — 换个关键词,或切换其他场景看看。", "No matching actions — try another keyword or scene."))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .gridCellColumns(6)
                    .padding(.vertical, 46)
            } else {
                ForEach(rows.indices, id: \.self) { index in
                    libraryTile(rows[index])
                }
            }
        }
        }
    }

    private func libraryTile(_ item: TileItem) -> AnyView {
        let isTop = item.effective == nil || item.effective == ScriptStore.topCategoryKey
        let scene = isTop ? nil : item.effective.flatMap { BuiltInMenuCategory(rawValue: $0) }
        let tint = MiaoTheme.sceneColor(scene)
        let badgeTitle = scene?.rawValue ?? L10n.text("顶层", "Top-level")

        if let definition = item.builtin {
            return AnyView(ActionTile(
                emoji: ActionEmoji.emoji(for: definition.name) ?? ActionEmoji.sceneDefault(definition.category?.rawValue ?? ""),
                tint: tint,
                title: ActionNames.name(definition.name),
                subtitle: ActionNames.description(definition.description),
                badgeTitle: badgeTitle,
                onMoveCategory: { category in
                    scriptStore.setLibraryCategory(
                        actionName: definition.name,
                        category: category ?? ScriptStore.topCategoryKey
                    )
                },
                isOn: item.isEnabled
            ) {
                scriptStore.setLibraryScript(definition, isEnabled: !item.isEnabled)
            })
        } else if let script = item.custom {
            return AnyView(ActionTile(
                emoji: "🧩",
                tint: tint,
                title: script.name,
                subtitle: composedSubtitle(script),
                badgeTitle: badgeTitle,
                onMoveCategory: { category in
                    var updated = script
                    updated.libraryCategory = category ?? ScriptStore.topCategoryKey
                    scriptStore.updateScript(updated)
                },
                isOn: item.isEnabled,
                onEdit: { onEditComposed(script) }
            ) {
                var updated = script
                updated.isEnabled.toggle()
                scriptStore.updateScript(updated)
            })
        }
        return AnyView(EmptyView())
    }

    /// 自建动作的副标题:步骤摘要,如「转换图片格式 · 移动到文件夹」
    private func composedSubtitle(_ script: Script) -> String {
        guard let action = ComposedAction.decode(script.content) else {
            return L10n.text("组合菜单", "Composed action")
        }
        let titles = action.steps.compactMap { step -> String? in
            guard let op = AtomRegistry.operation(step.op) else { return nil }
            if op.id == "builtin.run", let name = step.params["name"], !name.isEmpty { return name }
            return op.title
        }
        return titles.isEmpty
            ? L10n.text("空菜单", "Empty action")
            : titles.joined(separator: " → ")
    }

    // MARK: - 右列:菜单实时预览

    private var menuPreviewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.text("我的右键菜单", "My Context Menu"))
                    .font(.system(size: 13, weight: .heavy))
                Text(L10n.text("● 实时", "● LIVE"))
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(MiaoTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(MiaoTheme.accent.opacity(0.12)))
                Spacer()
            }
            Text(L10n.text("在「下载」文件夹中右键 3 个文件时 —", "Right-clicking 3 files in \"Downloads\" —"))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            // 展开子菜单后内容可能超高:限高内部滚动,不撑破布局
            ScrollView(.vertical, showsIndicators: false) {
                MenuPreviewPanel(rows: menuRows()) { key in
                if key.hasPrefix("submenu:") {
                    let label = String(key.dropFirst("submenu:".count))
                    withAnimation(.easeOut(duration: 0.15)) {
                        if expandedMenus.contains(label) {
                            expandedMenus.remove(label)
                        } else {
                            expandedMenus.insert(label)
                        }
                    }
                } else if key.hasPrefix("child:") {
                    // 点二级动作条目:用该动作名作为筛选词
                    searchText = String(key.dropFirst("child:".count))
                }
            }
            }
            Text(L10n.text("↖ 点子菜单展开二级条目 · 开关后菜单即时变化", "Click a submenu to expand — toggles update live"))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            statusCard
        }
        .frame(width: 350).frame(maxHeight: .infinity, alignment: .top)
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    extensionPill
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text(L10n.text(
                        "监控 \(monitoredFolderService.monitoredFolderCount) 个文件夹",
                        "\(monitoredFolderService.monitoredFolderCount) folders monitored"
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    Spacer()
                    Button(L10n.text("重启 Finder", "Restart Finder")) {
                        FinderControl.restartFinder()
                    }
                    .buttonStyle(.miaoSecondary)
                    .fixedSize()
                    Button(L10n.text("设置", "Settings")) { onOpenSettings() }
                        .buttonStyle(.miaoSecondary)
                        .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var extensionPill: some View {
        switch extensionStatus {
        case .some(let status):
            StatusPill(color: status.tint, icon: status.icon, text: status.displayText)
        case nil:
            Text(L10n.text("检查扩展状态…", "Checking extension…"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 菜单预览模型(与 FinderSync 的菜单结构对应)

    private func menuRows() -> [MenuPreviewRow] {
        var rows: [MenuPreviewRow] = []
        let enabled = enabledNames

        // 常用置顶:使用频率 + 种子,危险动作不参与(与右键菜单逻辑一致)
        var frequent = ActionUsage.top(4)
        if frequent.isEmpty { frequent = Self.frequentSeeds }
        frequent = frequent.filter { enabled.contains($0) && $0 != ActionID.deletePermanently }
        if !frequent.isEmpty {
            rows.append(.group(L10n.text("常用", "Frequent")))
            frequent.forEach { name in
                rows.append(.action(id: "f-\(name)", emoji: ActionEmoji.emoji(for: name) ?? "🧩", label: ActionNames.name(name), red: false))
            }
            rows.append(.separator)
        }

        // 顶层基础动作(去重常用)
        let loose = ScriptLibrary.allScripts.filter {
            $0.category == nil && enabled.contains($0.name)
                && $0.name != ActionID.deletePermanently && !frequent.contains($0.name)
        }
        loose.forEach { script in
            rows.append(.action(id: script.name, emoji: ActionEmoji.emoji(for: script.name) ?? "🧩", label: ActionNames.name(script.name), red: false))
        }
        if !loose.isEmpty { rows.append(.separator) }

        // 场景子菜单(点击展开二级:该场景下已启用的动作)
        for scene in BuiltInMenuCategory.allCases {
            let category = ScriptLibrary.ScriptCategory(rawValue: scene.rawValue) ?? .organize
            let enabledInScene = ScriptLibrary.scripts(for: category).filter { enabled.contains($0.name) }
            guard !enabledInScene.isEmpty else { continue }
            let key = scene.rawValue
            let expanded = expandedMenus.contains(key)
            rows.append(.submenu(
                emoji: scene.emoji,
                label: scene.rawValue,
                subtitle: L10n.text("\(enabledInScene.count) 项", "\(enabledInScene.count) items"),
                expanded: expanded
            ))
            if expanded {
                enabledInScene.forEach { script in
                    rows.append(.child(
                        id: script.name,
                        emoji: ActionEmoji.emoji(for: script.name) ?? ActionEmoji.sceneDefault(script.category?.rawValue ?? ""),
                        label: ActionNames.name(script.name)
                    ))
                }
            }
        }

        rows.append(.separator)
        rows.append(.settingsEntry)

        // 危险动作红色置底
        if enabled.contains(ActionID.deletePermanently) {
            rows.append(.separator)
            rows.append(.action(id: ActionID.deletePermanently, emoji: "🗑", label: ActionNames.name(ActionID.deletePermanently), red: true))
        }
        return rows
    }
}
