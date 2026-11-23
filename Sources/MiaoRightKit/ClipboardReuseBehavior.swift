import MiaoRightShared

/// 让记录菜单与单选/多选提示描述实际可执行的动作,包括未授权时的复制回退。
enum ClipboardReuseBehavior: Equatable {
    case copy, paste
    static func resolve(autoPaste: Bool, authorized: Bool) -> Self {
        autoPaste && authorized ? .paste : .copy
    }
    var menuTitle: String {
        self == .paste ? L10n.text("复制并粘贴", "Copy and Paste") : L10n.text("复制", "Copy")
    }
    func footer(pickedCount: Int) -> String {
        if pickedCount > 0 {
            return self == .paste
                ? L10n.text("已选 \(pickedCount) 项 · 回车合并粘贴 · Esc 收起", "\(pickedCount) picked · Enter merges & pastes · Esc closes")
                : L10n.text("已选 \(pickedCount) 项 · 回车合并复制 · Esc 收起", "\(pickedCount) picked · Enter merges & copies · Esc closes")
        }
        return self == .paste
            ? L10n.text("↑↓ 选择 · 空格多选 · 回车/数字粘贴 · Esc 收起", "↑↓ select · Space multi · Enter/number paste · Esc")
            : L10n.text("↑↓ 选择 · 空格多选 · 回车/数字复制 · Esc 收起", "↑↓ select · Space multi · Enter/number copy · Esc")
    }
}
