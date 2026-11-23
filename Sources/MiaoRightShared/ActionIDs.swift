import Foundation

/// 内置动作的显示名(即右键菜单标题)。Finder 扩展与主 App 共用,
/// 扩展根据这些名字识别需要动态子菜单(常用文件夹目标)的动作。
public enum ActionID {
    public static let cut = "剪切"
    public static let paste = "粘贴"
    public static let airdrop = "隔空投送…"
    public static let deletePermanently = "彻底删除"
}
