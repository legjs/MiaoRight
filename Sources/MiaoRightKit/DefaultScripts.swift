import Foundation
import MiaoRightShared

/// 内置动作库(参考超级右键专业版功能重组,全部中文化)。
/// 动作名即右键菜单标题;`category: nil` 的动作在右键菜单顶层显示。
enum ScriptLibrary {
    /// Script template for library items
    struct LibraryScript {
        let name: String
        let type: ScriptType
        let content: String
        let icon: String
        let appliesTo: AppliesTo
        let fileExtensions: [String]
        let extensionMatchMode: ExtensionMatchMode
        let minSelection: Int
        let maxSelection: Int?
        /// 所属分类;`nil` 表示顶层动作(不归入任何分类子菜单)。
        let category: ScriptCategory?
        let description: String
        let outputMode: ScriptOutputMode
        let confirmBeforeRun: Bool

        init(
            name: String,
            type: ScriptType,
            content: String,
            icon: String,
            appliesTo: AppliesTo,
            fileExtensions: [String] = [],
            extensionMatchMode: ExtensionMatchMode = .all,
            minSelection: Int = 1,
            maxSelection: Int? = nil,
            category: ScriptCategory?,
            description: String,
            outputMode: ScriptOutputMode = .standard,
            confirmBeforeRun: Bool = false
        ) {
            self.name = name
            self.type = type
            self.content = content
            self.icon = icon
            self.appliesTo = appliesTo
            self.fileExtensions = fileExtensions
            self.extensionMatchMode = extensionMatchMode
            self.minSelection = minSelection
            self.maxSelection = maxSelection
            self.category = category
            self.description = description
            self.outputMode = outputMode
            self.confirmBeforeRun = confirmBeforeRun
        }

        /// Convert to a Script model
        func toScript() -> Script {
            Script(
                name: name,
                type: type,
                content: content,
                icon: icon,
                appliesTo: appliesTo,
                fileExtensions: fileExtensions,
                extensionMatchMode: extensionMatchMode,
                minSelection: minSelection,
                maxSelection: maxSelection,
                outputMode: outputMode,
                confirmBeforeRun: confirmBeforeRun,
                libraryCategory: category?.rawValue
            )
        }
    }

    /// 场景分类(与 Shared 中的 BuiltInMenuCategory rawValue 保持一致)。
    enum ScriptCategory: String, CaseIterable {
        case organize = "整理归档"
        case media = "图片处理"
        case share = "分享发送"
        case dev = "开发效率"
        case quickOpen = "快速打开"
        case utilities = "实用工具"

        var icon: String {
            switch self {
            case .organize: "archivebox"
            case .media: "photo"
            case .share: "square.and.arrow.up"
            case .dev: "chevron.left.forwardslash.chevron.right"
            case .quickOpen: "arrow.up.forward.app"
            case .utilities: "wrench.and.screwdriver"
            }
        }

        var description: String {
            switch self {
            case .organize: "把乱糟糟的文件夹变得井井有条"
            case .media: "转换、压缩、尺寸调整与文字识别"
            case .share: "把文件发给别人或发到别处"
            case .dev: "面向开发的常用工具"
            case .quickOpen: "用各种应用快速打开所选内容"
            case .utilities: "日常高频小工具"
            }
        }

        var colorName: String {
            switch self {
            case .organize: "teal"
            case .media: "pink"
            case .share: "orange"
            case .dev: "purple"
            case .quickOpen: "cyan"
            case .utilities: "indigo"
            }
        }
    }

    static let imageExtensions = [
        "jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp", "webp"
    ]

    /// 首次安装默认开启的动作(其余动作可在库中按需开启)。
    static let defaultEnabledActions: Set<String> = [
        "复制路径", "在终端中打开", ActionID.cut, ActionID.paste, "移动到…", "复制到…",
        "压缩…", "解压到当前文件夹"
    ]

    // MARK: - 顶层动作(剪切/粘贴/移动到/复制到/隔空投送/彻底删除)

    static let looseScripts: [LibraryScript] = [
        LibraryScript(
            name: ActionID.cut,
            type: .bash,
            content: "# Runs natively via MiaoRight (Cut).",
            icon: "scissors",
            appliesTo: .allItems,
            category: nil,
            description: "剪切所选文件,之后在目标文件夹执行「粘贴」完成移动"
        ),
        LibraryScript(
            name: ActionID.paste,
            type: .bash,
            content: "# Runs natively via MiaoRight (Paste).",
            icon: "doc.on.clipboard.fill",
            appliesTo: .allItems,
            category: nil,
            description: "把之前「剪切」的文件移动到当前文件夹",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "移动到…",
            type: .bash,
            content: "# Runs natively via MiaoRight (Move to favorite).",
            icon: "folder.badge.gearshape",
            appliesTo: .allItems,
            category: nil,
            description: "弹窗选择文件夹,把所选文件移动过去",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "复制到…",
            type: .bash,
            content: "# Runs natively via MiaoRight (Copy to favorite).",
            icon: "plus.square.on.square",
            appliesTo: .allItems,
            category: nil,
            description: "弹窗选择文件夹,把所选文件复制过去"
        ),
        LibraryScript(
            name: ActionID.airdrop,
            type: .bash,
            content: "# Runs natively via MiaoRight (AirDrop).",
            icon: "dot.radiowaves.left.and.right",
            appliesTo: .filesOnly,
            category: nil,
            description: "通过隔空投送把文件发送到附近的 Apple 设备"
        ),
        LibraryScript(
            name: ActionID.deletePermanently,
            type: .bash,
            content: "# Runs natively via MiaoRight (Delete permanently).",
            icon: "trash.slash",
            appliesTo: .allItems,
            category: nil,
            description: "不经过废纸篓,直接彻底删除所选文件(不可恢复)",
            confirmBeforeRun: true
        )
    ]

    // MARK: - 新建文件

    static let newFileScripts: [LibraryScript] = [
        LibraryScript(
            name: "新建 TXT 文档",
            type: .bash,
            content: "# Runs natively via MiaoRight (New TXT).",
            icon: "doc.plaintext",
            appliesTo: .container,
            category: .organize,
            description: "在当前文件夹新建空白文本文档"
        ),
        LibraryScript(
            name: "新建 Markdown 笔记",
            type: .bash,
            content: "# Runs natively via MiaoRight (New Markdown).",
            icon: "doc.richtext",
            appliesTo: .container,
            category: .organize,
            description: "在当前文件夹新建 Markdown 笔记"
        ),
        LibraryScript(
            name: "新建 RTF 文档",
            type: .bash,
            content: "# Runs natively via MiaoRight (New RTF).",
            icon: "doc.text",
            appliesTo: .container,
            category: .organize,
            description: "在当前文件夹新建富文本文档"
        ),
        LibraryScript(
            name: "新建 Word 文档",
            type: .bash,
            content: "# Runs natively via MiaoRight (New Word).",
            icon: "doc.badge.gearshape",
            appliesTo: .container,
            category: .organize,
            description: "在当前文件夹新建 Word(.docx)文档"
        ),
        LibraryScript(
            name: "新建 Excel 工作簿",
            type: .bash,
            content: "# Runs natively via MiaoRight (New Excel).",
            icon: "tablecells",
            appliesTo: .container,
            category: .organize,
            description: "在当前文件夹新建 Excel(.xlsx)工作簿"
        ),
        LibraryScript(
            name: "新建 PPT 演示文稿",
            type: .bash,
            content: "# Runs natively via MiaoRight (New PPT).",
            icon: "chart.bar.doc.horizontal",
            appliesTo: .container,
            category: .organize,
            description: "在当前文件夹新建 PowerPoint(.pptx)演示文稿"
        ),
        LibraryScript(
            name: "新建文件夹",
            type: .bash,
            content: "# Runs natively via MiaoRight (New Folder).",
            icon: "folder.badge.plus",
            appliesTo: .container,
            category: .organize,
            description: "在当前文件夹新建文件夹"
        ),
        LibraryScript(
            name: "根据文件名新建文件夹",
            type: .bash,
            content: "# Runs natively via MiaoRight (New folder from filename).",
            icon: "doc.badge.plus",
            appliesTo: .filesOnly,
            category: .organize,
            description: "以所选文件的名称新建同名文件夹"
        )
    ]

    // MARK: - 常用功能

    static let universalScripts: [LibraryScript] = [
        LibraryScript(
            name: "复制路径",
            type: .bash,
            content: "printf '%s\\n' \"$@\" | pbcopy",
            icon: "doc.on.clipboard",
            appliesTo: .allItems,
            category: .utilities,
            description: "复制文件的完整路径到剪贴板"
        ),
        LibraryScript(
            name: "复制文件名",
            type: .bash,
            content: "basename -- \"$1\" | tr -d '\\n' | pbcopy",
            icon: "textformat",
            appliesTo: .allItems,
            maxSelection: 1,
            category: .utilities,
            description: "仅复制文件名(含扩展名)"
        ),
        LibraryScript(
            name: "复制文件名(不含扩展名)",
            type: .bash,
            content: "# Runs natively via MiaoRight (Copy filename without extension).",
            icon: "textformat.alt",
            appliesTo: .allItems,
            maxSelection: 1,
            category: .utilities,
            description: "仅复制文件名,不带扩展名"
        ),
        LibraryScript(
            name: "复制所在文件夹路径",
            type: .bash,
            content: "# Runs natively via MiaoRight (Copy parent folder path).",
            icon: "folder",
            appliesTo: .allItems,
            maxSelection: 1,
            category: .utilities,
            description: "复制文件所在文件夹的路径"
        ),
        LibraryScript(
            name: "复制 file:// 链接",
            type: .bash,
            content: "# Runs natively via MiaoRight (Copy as file URL).",
            icon: "link",
            appliesTo: .allItems,
            category: .utilities,
            description: "以 file:// URL 形式复制"
        ),
        LibraryScript(
            name: "复制为 Markdown 链接",
            type: .bash,
            content: "# Runs natively via MiaoRight (Copy as Markdown link).",
            icon: "text.badge.plus",
            appliesTo: .allItems,
            maxSelection: 1,
            category: .utilities,
            description: "复制为 [文件名](file://…) 形式的 Markdown 链接"
        ),
        LibraryScript(
            name: "在终端中打开",
            type: .bash,
            content: """
            if [ -d "$1" ]; then
                open -a Terminal "$1"
            else
                open -a Terminal "$(dirname -- "$1")"
            fi
            """,
            icon: "terminal",
            appliesTo: .allItems,
            maxSelection: 1,
            category: .utilities,
            description: "在终端中打开当前位置"
        ),
        LibraryScript(
            name: "创建带时间戳的副本",
            type: .bash,
            content: """
            for f in "$@"; do
                FILENAME=$(basename -- "$f")
                EXTENSION="${FILENAME##*.}"
                BASENAME="${FILENAME%.*}"
                TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                DIR=$(dirname -- "$f")
                if [ "$EXTENSION" = "$FILENAME" ]; then
                    cp -rn -- "$f" "$DIR/${BASENAME}_${TIMESTAMP}"
                else
                    cp -rn -- "$f" "$DIR/${BASENAME}_${TIMESTAMP}.${EXTENSION}"
                fi
            done
            """,
            icon: "doc.on.doc",
            appliesTo: .allItems,
            category: .utilities,
            description: "复制一份并在名称中加入日期时间"
        ),
        LibraryScript(
            name: "制作可执行文件",
            type: .bash,
            content: """
            for f in "$@"; do
                chmod +x -- "$f"
            done
            osascript -e 'display notification "已设置为可执行" with title "MiaoRight"'
            """,
            icon: "gearshape.2",
            appliesTo: .filesOnly,
            category: .utilities,
            description: "允许文件作为程序运行"
        ),
        LibraryScript(
            name: "清理 .DS_Store 文件",
            type: .bash,
            content: """
            if [ -d "$1" ]; then
                find "$1" -name '.DS_Store' -type f -delete
            else
                find "$(dirname "$1")" -name '.DS_Store' -type f -delete
            fi
            osascript -e 'display notification "已清理 .DS_Store 文件" with title "MiaoRight"'
            """,
            icon: "trash",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .utilities,
            description: "清理文件夹内的 Mac 隐藏系统文件",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "显示/隐藏隐藏文件",
            type: .bash,
            content: """
            CURRENT=$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null)
            if [ "$CURRENT" = "YES" ] || [ "$CURRENT" = "TRUE" ] || [ "$CURRENT" = "1" ]; then
                defaults write com.apple.finder AppleShowAllFiles NO
            else
                defaults write com.apple.finder AppleShowAllFiles YES
            fi
            killall Finder
            """,
            icon: "eye",
            appliesTo: .container,
            category: .utilities,
            description: "切换 Finder 中隐藏文件的显示状态"
        )
    ]

    // MARK: - 打开应用

    static let openWithScripts: [LibraryScript] = [
        LibraryScript(
            name: "在 iTerm2 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in iTerm2).",
            icon: "terminal.fill",
            appliesTo: .allItems,
            maxSelection: 1,
            category: .quickOpen,
            description: "在 iTerm2 终端中打开当前位置"
        ),
        LibraryScript(
            name: "在 Warp 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in Warp).",
            icon: "terminal",
            appliesTo: .allItems,
            maxSelection: 1,
            category: .quickOpen,
            description: "在 Warp 终端中打开当前位置"
        ),
        LibraryScript(
            name: "在 VS Code 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in VS Code).",
            icon: "chevron.left.forwardslash.chevron.right",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 Visual Studio Code 打开"
        ),
        LibraryScript(
            name: "在 Cursor 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in Cursor).",
            icon: "cursorarrow.rays",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 Cursor 编辑器打开"
        ),
        LibraryScript(
            name: "在 Sublime Text 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in Sublime Text).",
            icon: "text.alignleft",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 Sublime Text 打开"
        ),
        LibraryScript(
            name: "在 Typora 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in Typora).",
            icon: "doc.richtext.fill",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 Typora 打开 Markdown 文件"
        ),
        LibraryScript(
            name: "在 Obsidian 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in Obsidian).",
            icon: "brain",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "在 Obsidian 中打开笔记"
        ),
        LibraryScript(
            name: "在 IDEA 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in IDEA).",
            icon: "chevron.left.square.fill",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 IntelliJ IDEA 打开项目"
        ),
        LibraryScript(
            name: "在 PyCharm 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in PyCharm).",
            icon: "curlybraces.square.fill",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 PyCharm 打开项目"
        ),
        LibraryScript(
            name: "在 CLion 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in CLion).",
            icon: "c.circle.fill",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 CLion 打开项目"
        ),
        LibraryScript(
            name: "在 WebStorm 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in WebStorm).",
            icon: "globe",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 WebStorm 打开项目"
        ),
        LibraryScript(
            name: "在 GoLand 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in GoLand).",
            icon: "swiftdata",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 GoLand 打开项目"
        ),
        LibraryScript(
            name: "在 DataGrip 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in DataGrip).",
            icon: "cylinder.split.1x2",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 DataGrip 打开数据库目录"
        ),
        LibraryScript(
            name: "在 Android Studio 中打开",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open in Android Studio).",
            icon: "android",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "用 Android Studio 打开项目"
        ),
        LibraryScript(
            name: "用其他应用打开…",
            type: .bash,
            content: "# Runs natively via MiaoRight (Open with other app).",
            icon: "square.grid.3x3.square",
            appliesTo: .allItems,
            category: .quickOpen,
            description: "弹窗选择任意 App 打开所选文件"
        )
    ]

    // MARK: - 汇总

    static var allScripts: [LibraryScript] {
        looseScripts + newFileScripts + universalScripts + openWithScripts + fileManagementScripts + designerScripts + developerScripts + powerUserScripts
    }

    static var availableCategories: [ScriptCategory] {
        ScriptCategory.allCases.filter { !scripts(for: $0).isEmpty }
    }

    static var availableAllScripts: [LibraryScript] {
        allScripts
    }

    /// 场景 → 动作(按场景过滤全部动作)
    static func scripts(for scene: ScriptCategory) -> [LibraryScript] {
        allScripts.filter { $0.category == scene }
    }

    static func availableScripts(for category: ScriptCategory) -> [LibraryScript] {
        scripts(for: category)
    }

    static func libraryScript(named name: String) -> LibraryScript? {
        allScripts.first { $0.name == name }
    }
}
