import Foundation

/// 动作 emoji 图标映射:右键菜单、卡片、工作流节点统一使用,
/// 匹配原型的彩色图标风格。未命中映射的动作回退到所在场景的默认 emoji。
public enum ActionEmoji {
    /// 重点动作的专属 emoji
    static let overrides: [String: String] = [
        // 顶层
        "剪切": "✂️",
        "粘贴": "📋",
        "移动到…": "📁",
        "复制到…": "📑",
        "隔空投送…": "📡",
        "彻底删除": "🗑",
        // 新建文件
        "新建 TXT 文档": "📝",
        "新建 Markdown 笔记": "✍️",
        "新建 RTF 文档": "📄",
        "新建 Word 文档": "📘",
        "新建 Excel 工作簿": "📊",
        "新建 PPT 演示文稿": "📽",
        "新建文件夹": "📁",
        "根据文件名新建文件夹": "🗂",
        // 常用功能
        "复制路径": "🔗",
        "复制文件名": "🏷",
        "复制文件名(不含扩展名)": "🏷",
        "复制所在文件夹路径": "📂",
        "复制 file:// 链接": "🔗",
        "复制为 Markdown 链接": "🖊",
        "在终端中打开": "🖥",
        "显示简介": "ℹ️",
        "在 Finder 中显示": "👁",
        "创建带时间戳的副本": "🕓",
        "制作可执行文件": "⚙️",
        "清理 .DS_Store 文件": "🧹",
        "显示/隐藏隐藏文件": "🙈",
        // 图片工具
        "复制图片中的文字": "📷",
        "导出图片中的文字": "📝",
        "HEIC 转 JPG": "📷",
        "图片合并为 PDF": "📑",
        "PDF 拆分为单页": "✂️",
        "PDF 转图片": "🖼",
        "转换为 ICNS": "🧊",
        "转换为 WebP": "🌐",
        "移除照片隐私信息": "🛡",
        "查看图片尺寸": "📏",
        "顺时针旋转 90°": "🔄",
        "创建 @2x 副本": "✖️",
        "设为桌面壁纸": "🖥",
        "用图片设置文件夹图标": "🎨",
        "导出为图标集": "🧊",
        // 分享发送
        "压缩为 ZIP": "📦",
        "压缩为 7Z": "🗜",
        "解压 7Z": "📦",
        "压缩…": "📦",
        "解压": "📦",
        "批量重命名…": "✏️",
        "加入保险箱": "🔐",
        "路径转二维码": "📱",
        "发送快捷方式到桌面": "🚀",
        // 开发效率
        "在 IDEA 中打开": "☕",
        "在 PyCharm 中打开": "🐍",
        "在 CLion 中打开": "⚙️",
        "在 WebStorm 中打开": "🌐",
        "在 GoLand 中打开": "🐹",
        "在 DataGrip 中打开": "🗄",
        "在 Android Studio 中打开": "🤖",
        "初始化 Git 仓库": "🌿",
        "用 Xcode 打开": "🔨",
        "生成 UUID": "🆔",
        // 高级功能
        "MD5 哈希": "#️⃣",
        "SHA1 哈希": "#️⃣",
        "SHA256 哈希": "🔐",
        "SHA512 哈希": "🔐",
        "生成 .sha256 校验文件": "✅",
        "解压到当前文件夹": "📦",
        "创建 TAR.GZ": "🗜",
        "解压 TAR.GZ": "📦",
        "锁定文件": "🔒",
        "解锁文件": "🔓",
        "查看文件十六进制": "🔤",
        "强制解除文件占用": "💥",
        "恢复默认文件夹图标": "↩️"
    ]

    /// 场景默认 emoji(未命中专属映射时使用;与 BuiltInMenuCategory.emoji 保持一致)
    public static func sceneDefault(_ sceneName: String) -> String {
        switch sceneName {
        case "整理归档": "📥"
        case "图片处理": "🖼"
        case "分享发送": "📤"
        case "开发效率": "💻"
        case "快速打开": "🚀"
        case "实用工具": "🧰"
        default: "🧩"
        }
    }

    /// 取动作 emoji;无专属映射时返回 nil(调用方回退场景默认)
    public static func emoji(for actionName: String) -> String? {
        overrides[actionName]
    }

    /// 取动作 emoji,带场景回退
    public static func emoji(for actionName: String, sceneName: String) -> String {
        overrides[actionName] ?? sceneDefault(sceneName)
    }
}
