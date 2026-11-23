import SwiftUI

// MARK: - 区块标题

/// 区块标题行:左标题 + 可选尾部视图(按钮/链接)
struct MiaoSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
    }
}

// MARK: - 状态胶囊

/// 圆点/图标 + 文本的状态胶囊(扩展状态、计数等)
struct StatusPill: View {
    let color: Color
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
        .fixedSize()
    }
}

// MARK: - 按钮

/// 品牌渐变胶囊主按钮
struct MiaoProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(MiaoTheme.accentGradient))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// 玻璃胶囊次按钮
struct MiaoSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == MiaoProminentButtonStyle {
    static var miaoProminent: MiaoProminentButtonStyle { .init() }
}

extension ButtonStyle where Self == MiaoSecondaryButtonStyle {
    static var miaoSecondary: MiaoSecondaryButtonStyle { .init() }
}

// MARK: - 筛选 chip

/// 场景/分类筛选胶囊,选中时染场景色
struct MiaoChip: View {
    let emoji: String
    let title: String
    var tint: Color = .accentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 12))
                Text(title).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? tint.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? tint.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? tint : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 搜索框

/// 圆角玻璃搜索框;支持外部 FocusState 以便做快捷键聚焦
struct MiaoSearchField: View {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            field
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var field: some View {
        if let isFocused {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(isFocused)
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
    }
}

// MARK: - 列表行

/// 通用行:emoji/SF 色块 + 标题 + 副标题 + 尾部(开关/按钮)
struct MiaoListRow<Trailing: View>: View {
    let tileText: String
    /// SF Symbol 时传 nil,emoji 时传场景色
    var tileSystemName: Bool = false
    let tint: Color
    let title: String
    var subtitle: String?
    var badge: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(tint.opacity(0.13)))
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(
                tileSystemName
                    ? AnyShapeStyle(tint.opacity(0.15))
                    : AnyShapeStyle(LinearGradient(
                        colors: [tint, tint.opacity(0.72)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .frame(width: 34, height: 34)
            .overlay {
                if tileSystemName {
                    Image(systemName: tileText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tint)
                } else {
                    Text(tileText).font(.system(size: 16))
                }
            }
    }
}

// MARK: - 空状态

/// 居中空状态:大图标 + 标题 + 说明
struct MiaoEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(MiaoTheme.accent.opacity(0.8))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
