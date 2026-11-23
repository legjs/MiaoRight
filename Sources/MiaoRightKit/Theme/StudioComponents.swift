import MiaoRightShared
import SwiftUI

// MARK: - 药丸导航

/// 顶栏图标切换器:替代文字页签,悬停有提示,高亮胶囊平滑滑动
struct IconTabs<Item: Hashable>: View {
    let items: [(item: Item, icon: String, title: String)]
    @Binding var selection: Item
    @Namespace private var slideNS

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.item) { entry in
                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.15)) {
                        selection = entry.item
                    }
                } label: {
                    Image(systemName: entry.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 28)
                        .background {
                            if selection == entry.item {
                                Capsule()
                                    .fill(MiaoTheme.accentGradient)
                                    .shadow(color: MiaoTheme.accentIndigo.opacity(0.35), radius: 8, y: 3)
                                    .matchedGeometryEffect(id: "activeIconTab", in: slideNS)
                            }
                        }
                        .foregroundStyle(selection == entry.item ? .white : Color.secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(entry.title)
            }
        }
        .padding(4)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .animation(.spring(duration: 0.28, bounce: 0.15), value: selection)
    }
}

/// 动作磁贴:emoji 渐变色块 + 名称 + 一句话描述 + 开关。整卡可点切换。
struct ActionTile: View {
    let emoji: String
    let tint: Color
    let title: String
    let subtitle: String?
    let badgeTitle: String
    /// 非 nil 时徽章变为归属分类菜单(参数传 nil = 移到顶层,传场景 rawValue = 移到该场景)
    var onMoveCategory: ((String?) -> Void)? = nil
    let isOn: Bool
    /// 非 nil 时(自建动作)标题行右侧显示编辑铅笔
    var onEdit: (() -> Void)? = nil
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(MiaoTheme.tileGradient(tint))
                    .frame(width: 36, height: 36)
                    .overlay(Text(emoji).font(.system(size: 19)))
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.text("编辑菜单", "Edit action"))
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            HStack {
                if let onMoveCategory {
                    Menu {
                        Button(L10n.text("顶层", "Top-level")) { onMoveCategory(nil) }
                        Divider()
                        ForEach(BuiltInMenuCategory.allCases, id: \.self) { scene in
                            Button(scene.emoji + " " + scene.rawValue) { onMoveCategory(scene.rawValue) }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(badgeTitle)
                                .font(.system(size: 10))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .opacity(0.7)
                        }
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.13)))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                } else {
                    Text(badgeTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                // 只有开关触发状态切换,点磁贴其余区域不误触
                Button(action: onToggle) {
                    MiniSwitch(isOn: isOn)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isOn ? MiaoTheme.accent.opacity(0.5) : rim, lineWidth: 1)
        )
    }

    private var rim: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.55)
    }
}

/// 迷你开关(磁贴/命令面板行内用)
struct MiniSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(MiaoTheme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.14)))
            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .offset(x: isOn ? 15 : 2)
        }
        .frame(width: 31, height: 18)
        .animation(.spring(duration: 0.2), value: isOn)
    }
}

// MARK: - 场景卡

/// 场景入口卡(工作台「动作宇宙」)
struct SceneCard: View {
    let scene: BuiltInMenuCategory
    let countText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MiaoTheme.tileGradient(MiaoTheme.sceneColor(scene)))
                    .frame(width: 46, height: 46)
                    .overlay(Text(scene.emoji).font(.system(size: 23)))
                Text(scene.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(countText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverLift()
    }
}

// MARK: - 悬浮上浮

/// 卡片类元素的悬停反馈
struct HoverLift: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.015 : 1)
            .shadow(color: .black.opacity(hovering ? 0.14 : 0), radius: 12, y: 5)
            .onHover { hovering = $0 }
            .animation(.spring(duration: 0.2), value: hovering)
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}

// MARK: - 菜单实时预览

/// 右键菜单预览的行模型(与 FinderSync 的菜单结构一一对应)
enum MenuPreviewRow: Identifiable, Equatable {
    case group(String)
    case action(id: String, emoji: String, label: String, red: Bool)
    case submenu(emoji: String, label: String, subtitle: String, expanded: Bool)
    /// 子菜单展开后的二级条目;点击可跳转定位
    case child(id: String, emoji: String, label: String)
    case settingsEntry
    case separator

    var id: String {
        switch self {
        case .group(let s): "g-\(s)"
        case .action(let id, _, _, _): "a-\(id)"
        case .submenu(_, let label, _, _): "s-\(label)"
        case .child(let id, _, _): "c-\(id)"
        case .settingsEntry: "settings"
        case .separator: "sep-\(UUID().uuidString)"
        }
    }
}

/// macOS 右键菜单样式的实时预览面板。
/// `onTap` 回调携带行标识:`submenu:<标签>` 切换展开,`child:<动作名>` 跳转定位。
struct MenuPreviewPanel: View {
    let rows: [MenuPreviewRow]
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .group(let title):
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 5)
                        .padding(.bottom, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .action(_, let emoji, let label, let red):
                    HStack(spacing: 8) {
                        Text(emoji)
                            .font(.system(size: 13))
                            .frame(width: 17)
                        Text(label)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(red ? Color(hexString: "#E5484D") : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.clear)
                    )
                case .submenu(let emoji, let label, let subtitle, let expanded):
                    Button {
                        onTap?("submenu:\(label)")
                    } label: {
                        HStack(spacing: 8) {
                            Text(emoji)
                                .font(.system(size: 13))
                                .frame(width: 17)
                            Text(label)
                                .font(.system(size: 12.5))
                            Spacer()
                            Text(subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.primary.opacity(0.001))
                        )
                    }
                    .buttonStyle(.plain)
                case .child(let id, let emoji, let label):
                    Button {
                        onTap?("child:\(id)")
                    } label: {
                        HStack(spacing: 8) {
                            Text(emoji)
                                .font(.system(size: 12))
                                .frame(width: 17)
                                .padding(.leading, 18)
                            Text(label)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3.5)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.primary.opacity(0.001))
                        )
                    }
                    .buttonStyle(.plain)
                case .settingsEntry:
                    HStack(spacing: 8) {
                        Text("⚙️").font(.system(size: 13)).frame(width: 17)
                        Text(L10n.text("打开妙右设置…", "Open MiaoRight Settings…"))
                            .font(.system(size: 12.5))
                        Spacer()
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                case .separator:
                    Divider().overlay(Color.primary.opacity(0.14)).padding(.horizontal, 8).padding(.vertical, 3)
                }
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

// MARK: - 区块标题

/// 工作台区块标题:图标 + 标题 + 副说明
struct StudioSectionHeader: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(icon).font(.system(size: 13))
            Text(title)
                .font(.system(size: 13, weight: .heavy))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - 扩展状态便捷显示

extension ExtensionStatus {
    /// 界面用状态色
    var tint: Color {
        switch self {
        case .active: .green
        case .enabledNotRunning: .orange
        case .disabled: .red
        }
    }

    /// 双语状态文案(ExtensionStatus.statusText 为旧中文-only,界面统一走这里)
    var displayText: String {
        switch self {
        case .active:
            L10n.text("右键菜单可用", "Context menu ready")
        case .enabledNotRunning:
            L10n.text("已启用,建议重启 Finder", "Enabled — restart Finder")
        case .disabled:
            L10n.text("扩展未启用", "Extension disabled")
        }
    }
}
