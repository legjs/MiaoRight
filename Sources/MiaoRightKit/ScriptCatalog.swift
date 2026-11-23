import AppKit
import Foundation

// 内置动作库的第二部分:文件管理、图片工具、开发工具、高级功能。
// 与 DefaultScripts.swift 同属 `ScriptLibrary`。
// 破坏性动作(移动/重命名/删除/覆盖)均设置 `confirmBeforeRun: true`。
extension ScriptLibrary {
    // MARK: - 文件管理

    static let fileManagementScripts: [LibraryScript] = [
        LibraryScript(
            name: "归类到新文件夹",
            type: .bash,
            content: "# Runs natively via MiaoRight (Create folder from selection).",
            icon: "folder.fill.badge.plus",
            appliesTo: .allItems,
            category: .organize,
            description: "新建文件夹并把所选文件移入",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "解散文件夹",
            type: .bash,
            content: "# Runs natively via MiaoRight (Dissolve folder).",
            icon: "arrow.up.and.person.rectangle.turn.right",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .organize,
            description: "删除文件夹本身,但把里面的文件保留到上一级",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "拍平嵌套文件",
            type: .bash,
            content: "# Runs natively via MiaoRight (Flatten folder).",
            icon: "arrow.up.to.line",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .organize,
            description: "把子文件夹里的文件全部移到顶层",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "按类型整理",
            type: .bash,
            content: "# Runs natively via MiaoRight (Organize by extension).",
            icon: "folder.badge.gearshape",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .organize,
            description: "按扩展名自动分拣文件到子文件夹",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "按日期整理",
            type: .bash,
            content: "# Runs natively via MiaoRight (Organize by date).",
            icon: "calendar",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .organize,
            description: "按「年-月」自动分拣文件到子文件夹",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "按序号重命名",
            type: .bash,
            content: "# Runs natively via MiaoRight (Rename with sequence).",
            icon: "textformat.123",
            appliesTo: .filesOnly,
            category: .organize,
            description: "把所选文件重命名为 001、002、003…",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "文件名转小写",
            type: .bash,
            content: "# Runs natively via MiaoRight (Lowercase filenames).",
            icon: "textformat.abc",
            appliesTo: .filesOnly,
            category: .organize,
            description: "把文件名转换为小写",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "空格替换为下划线",
            type: .bash,
            content: "# Runs natively via MiaoRight (Replace spaces with underscores).",
            icon: "underline",
            appliesTo: .allItems,
            category: .organize,
            description: "把文件名中的空格替换为下划线",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "隐藏所选文件",
            type: .bash,
            content: "# Runs natively via MiaoRight (Hide items).",
            icon: "eye.slash",
            appliesTo: .allItems,
            category: .organize,
            description: "把所选文件(夹)标记为隐藏"
        ),
        LibraryScript(
            name: "取消隐藏",
            type: .bash,
            content: "# Runs natively via MiaoRight (Unhide items).",
            icon: "eye",
            appliesTo: .allItems,
            category: .organize,
            description: "取消所选文件(夹)的隐藏标记"
        ),
        LibraryScript(
            name: "发送快捷方式到桌面",
            type: .bash,
            content: "# Runs natively via MiaoRight (Alias to desktop).",
            icon: "arrow.up.forward.square",
            appliesTo: .allItems,
            category: .share,
            description: "在桌面创建指向所选文件的快捷方式"
        ),
        LibraryScript(
            name: "清除空文件夹",
            type: .bash,
            content: "# Runs natively via MiaoRight (Remove empty folders).",
            icon: "folder.badge.minus",
            appliesTo: .foldersOnly,
            category: .organize,
            description: "删除所选文件夹内的所有空文件夹"
        )
    ]

    // MARK: - 图片工具

    /// 高频动作(OCR、PDF、HEIC)排在最前,方便一眼找到。
    static let designerScripts: [LibraryScript] = [
        LibraryScript(
            name: "复制图片中的文字",
            type: .bash,
            content: "# Runs natively via MiaoRight (Copy Text from Image).",
            icon: "text.viewfinder",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "识别图片中的文字并复制"
        ),
        LibraryScript(
            name: "导出图片中的文字",
            type: .bash,
            content: "# Runs natively via MiaoRight (Save Text from Image).",
            icon: "doc.text.viewfinder",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "识别图片中的文字并保存为 .txt"
        ),
        LibraryScript(
            name: "HEIC 转 JPG",
            type: .bash,
            content: "# Runs natively via MiaoRight (HEIC to JPEG).",
            icon: "iphone",
            appliesTo: .filesOnly,
            fileExtensions: ["heic"],
            category: .media,
            description: "把 iPhone 的 HEIC 照片转换为 JPG"
        ),
        LibraryScript(
            name: "图片合并为 PDF",
            type: .bash,
            content: "# Runs natively via MiaoRight (Combine Images into PDF).",
            icon: "doc.on.doc",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            minSelection: 2,
            category: .media,
            description: "把所选图片合并成一个 PDF"
        ),
        LibraryScript(
            name: "PDF 拆分为单页",
            type: .bash,
            content: "# Runs natively via MiaoRight (Split PDF into Pages).",
            icon: "doc.on.doc.fill",
            appliesTo: .filesOnly,
            fileExtensions: ["pdf"],
            maxSelection: 1,
            category: .media,
            description: "把 PDF 的每一页拆分为单独文件"
        ),
        LibraryScript(
            name: "PDF 转图片",
            type: .bash,
            content: "# Runs natively via MiaoRight (PDF to Images).",
            icon: "photo.stack",
            appliesTo: .filesOnly,
            fileExtensions: ["pdf"],
            maxSelection: 1,
            category: .media,
            description: "把 PDF 每一页渲染为 PNG 图片"
        ),
        LibraryScript(
            name: "转换为 PNG",
            type: .bash,
            content: "# Runs natively via MiaoRight (Convert to PNG).",
            icon: "photo",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "转换为 PNG 格式(生成新文件)"
        ),
        LibraryScript(
            name: "转换为 JPG",
            type: .bash,
            content: "# Runs natively via MiaoRight (Convert to JPEG).",
            icon: "photo.fill",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "转换为 JPG 格式(生成新文件)"
        ),
        LibraryScript(
            name: "转换为 ICNS",
            type: .bash,
            content: "# Runs natively via MiaoRight (Convert to ICNS).",
            icon: "app.gift",
            appliesTo: .filesOnly,
            fileExtensions: ["png", "jpg", "jpeg", "tiff"],
            category: .media,
            description: "把图片转换为 Mac 图标格式 .icns"
        ),
        LibraryScript(
            name: "转换为 WebP",
            type: .bash,
            content: "# Runs natively via MiaoRight (Convert to WebP).",
            icon: "camera.metering.unknown",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "转换为 WebP 格式(需要系统支持)"
        ),
        LibraryScript(
            name: "缩小到 50%",
            type: .bash,
            content: "# Runs natively via MiaoRight (Resize 50%).",
            icon: "arrow.down.right.and.arrow.up.left",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "把图片缩小为原来的一半(生成新文件)"
        ),
        LibraryScript(
            name: "缩放到 1920px",
            type: .bash,
            content: "# Runs natively via MiaoRight (Resize to 1920px).",
            icon: "rectangle.expand.vertical",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "把图片宽度缩放到 1920px(生成新文件)"
        ),
        LibraryScript(
            name: "创建缩略图 (256px)",
            type: .bash,
            content: "# Runs natively via MiaoRight (Create Thumbnail 256).",
            icon: "photo.on.rectangle",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "创建 256px 的缩略图版本"
        ),
        LibraryScript(
            name: "移除照片隐私信息",
            type: .bash,
            content: "# Runs natively via MiaoRight (Remove Photo Info).",
            icon: "eye.slash.circle",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "去掉照片里的 GPS 定位和相机信息"
        ),
        LibraryScript(
            name: "查看图片尺寸",
            type: .bash,
            content: "# Runs natively via MiaoRight (Get Image Dimensions).",
            icon: "ruler",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "查看图片的宽度和高度"
        ),
        LibraryScript(
            name: "顺时针旋转 90°",
            type: .bash,
            content: "# Runs natively via MiaoRight (Rotate 90 Clockwise).",
            icon: "rotate.right",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            category: .media,
            description: "把图片顺时针旋转 90 度(生成新文件)"
        ),
        LibraryScript(
            name: "创建 @2x 副本",
            type: .bash,
            content: "# Runs natively via MiaoRight (Create Retina Copy).",
            icon: "square.2.layers.3d",
            appliesTo: .filesOnly,
            fileExtensions: ["png"],
            category: .media,
            description: "创建 @2x 视网膜屏尺寸副本"
        ),
        LibraryScript(
            name: "设为桌面壁纸",
            type: .bash,
            content: "# Runs natively via MiaoRight (Set wallpaper).",
            icon: "wallpaper",
            appliesTo: .filesOnly,
            fileExtensions: imageExtensions,
            maxSelection: 1,
            category: .media,
            description: "把这张图片设为桌面壁纸"
        ),
        LibraryScript(
            name: "用图片设置文件夹图标",
            type: .bash,
            content: "# Runs natively via MiaoRight (Set folder icon).",
            icon: "paintbrush",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .media,
            description: "选择一张图片,设置为文件夹的自定义图标"
        ),
        LibraryScript(
            name: "导出为图标集",
            type: .bash,
            content: "# Runs natively via MiaoRight (Export icon set).",
            icon: "app.badge.fill",
            appliesTo: .filesOnly,
            fileExtensions: ["png", "jpg", "jpeg", "tiff"],
            maxSelection: 1,
            category: .media,
            description: "生成 Mac/iPhone/iPad/Watch 全尺寸 .iconset 和 .icns"
        )
    ]

    // MARK: - 开发工具

    static let developerScripts: [LibraryScript] = [
        LibraryScript(
            name: "初始化 Git 仓库",
            type: .bash,
            content: """
            (
                cd "$1" || exit 1
                git init
                echo "# $(basename -- "$1")" > README.md
                echo ".DS_Store" > .gitignore
                echo "node_modules/" >> .gitignore
                git add .
                git commit -m "Initial commit"
            )
            osascript -e 'display notification "Git 仓库已初始化" with title "MiaoRight"'
            """,
            icon: "arrow.triangle.branch",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .dev,
            description: "初始化 Git 仓库并创建 README 和 .gitignore"
        ),
        LibraryScript(
            name: "用 Xcode 打开",
            type: .bash,
            content: "open -a Xcode -- \"$@\"",
            icon: "hammer",
            appliesTo: .allItems,
            fileExtensions: ["swift", "xcodeproj", "xcworkspace", "playground", "plist", "entitlements"],
            category: .dev,
            description: "用 Xcode 打开"
        ),
        LibraryScript(
            name: "执行 npm install",
            type: .bash,
            content: """
            (cd "$1" && npm install)
            osascript -e 'display notification "npm install 完成" with title "MiaoRight"'
            """,
            icon: "shippingbox",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .dev,
            description: "在文件夹中执行 npm install"
        ),
        LibraryScript(
            name: "格式化 JSON",
            type: .bash,
            content: """
            for f in "$@"; do
                TEMP=$(mktemp)
                jq '.' -- "$f" > "$TEMP" && mv -f -- "$TEMP" "$f"
            done
            osascript -e 'display notification "JSON 已格式化" with title "MiaoRight"'
            """,
            icon: "curlybraces",
            appliesTo: .filesOnly,
            fileExtensions: ["json"],
            category: .dev,
            description: "美化 JSON 文件"
        ),
        LibraryScript(
            name: "压缩 JSON",
            type: .bash,
            content: """
            for f in "$@"; do
                BASENAME="${f%.*}"
                jq -c '.' "$f" > "${BASENAME}.min.json"
            done
            osascript -e 'display notification "JSON 已压缩" with title "MiaoRight"'
            """,
            icon: "arrow.down.right.and.arrow.up.left",
            appliesTo: .filesOnly,
            fileExtensions: ["json"],
            category: .dev,
            description: "压缩为 .min.json"
        ),
        LibraryScript(
            name: "生成 UUID",
            type: .bash,
            content: """
            UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
            echo -n "$UUID" | pbcopy
            osascript - "$UUID" <<'APPLESCRIPT'
            on run argv
                display notification (item 1 of argv) with title "UUID 已复制"
            end run
            APPLESCRIPT
            """,
            icon: "number",
            appliesTo: .container,
            category: .dev,
            description: "生成一个新 UUID 并复制"
        ),
        LibraryScript(
            name: "Base64 编码",
            type: .bash,
            content: """
            base64 -i "$1" | tr -d '\\n' | pbcopy
            osascript -e 'display notification "Base64 已复制到剪贴板" with title "MiaoRight"'
            """,
            icon: "doc.text",
            appliesTo: .filesOnly,
            maxSelection: 1,
            category: .dev,
            description: "把文件编码为 Base64 并复制"
        ),
        LibraryScript(
            name: "统计代码行数",
            type: .bash,
            content: """
            NAME=$(basename -- "$1")
            COUNT=$(find "$1" -type f \\( -name "*.swift" -o -name "*.ts" -o -name "*.js" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \\) -print0 | xargs -0 wc -l 2>/dev/null | tail -1 | awk '{print $1}')
            osascript - "$COUNT" "$NAME" <<'APPLESCRIPT'
            on run argv
                set lineCount to item 1 of argv
                set folderName to item 2 of argv
                display dialog ("代码行数: " & lineCount) with title folderName buttons {"好"} default button "好"
            end run
            APPLESCRIPT
            """,
            icon: "number.square",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .dev,
            description: "统计常见源码文件的行数"
        ),
        LibraryScript(
            name: "创建 .gitignore",
            type: .bash,
            content: "cat > \"$1/.gitignore\" << 'EOF'\n# macOS\n.DS_Store\n.AppleDouble\n.LSOverride\n\n# Node\nnode_modules/\nnpm-debug.log*\n\n# Python\n__pycache__/\n*.py[cod]\n.env\nvenv/\n\n# Swift\n.build/\nDerivedData/\n*.xcuserstate\n\n# IDE\n.idea/\n.vscode/\n*.swp\nEOF\nosascript -e 'display notification \".gitignore 已创建\" with title \"MiaoRight\"'",
            icon: "doc.badge.gearshape",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .dev,
            description: "创建常用的 .gitignore 模板"
        ),
        LibraryScript(
            name: "启动本地服务器",
            type: .bash,
            content: """
            (cd "$1" && python3 -m http.server 8000 </dev/null >/dev/null 2>&1) &
            sleep 1 && open "http://localhost:8000"
            """,
            icon: "network",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .dev,
            description: "在 8000 端口启动静态文件服务器"
        )
    ]

    // MARK: - 高级功能

    static let powerUserScripts: [LibraryScript] = [
        LibraryScript(name: "压缩…", type: .bash, content: "# Runs natively via MiaoRight (Compression options).", icon: "archivebox", appliesTo: .allItems, category: .share,
                      description: "选择 ZIP、7Z 或 TAR.GZ 格式，可为 ZIP / 7Z 设置密码"),
        LibraryScript(name: "解压", type: .bash, content: "# Runs natively via MiaoRight (Extract archive).", icon: "archivebox", appliesTo: .filesOnly,
                      fileExtensions: ArchiveInput.menuExtensions, extensionMatchMode: .any, category: .utilities,
                      description: "自动识别 ZIP、7Z、RAR、TAR、GZ、BZ2、XZ，支持常见首个分卷"),
        LibraryScript(name: "批量重命名…", type: .bash, content: "# Runs natively via MiaoRight (Batch rename preview).", icon: "pencil", appliesTo: .allItems, category: .organize,
                      description: "预览文字替换、前后缀与编号，检查冲突后再执行", confirmBeforeRun: true),
        LibraryScript(name: "加入保险箱", type: .bash, content: "# Runs natively via MiaoRight (Add to vault).", icon: "lock.shield", appliesTo: .allItems, category: .organize,
                      description: "把文件或文件夹移入加密保险箱，原位置不再保留", confirmBeforeRun: true),
        LibraryScript(
            name: "MD5 哈希",
            type: .bash,
            content: "# Runs natively via MiaoRight (MD5 hash).",
            icon: "number.circle",
            appliesTo: .filesOnly,
            maxSelection: 1,
            category: .utilities,
            description: "计算文件 MD5 并复制"
        ),
        LibraryScript(
            name: "SHA1 哈希",
            type: .bash,
            content: "# Runs natively via MiaoRight (SHA1 hash).",
            icon: "number.circle.fill",
            appliesTo: .filesOnly,
            maxSelection: 1,
            category: .utilities,
            description: "计算文件 SHA1 并复制"
        ),
        LibraryScript(
            name: "SHA256 哈希",
            type: .bash,
            content: "# Runs natively via MiaoRight (SHA256 hash).",
            icon: "lock.shield",
            appliesTo: .filesOnly,
            maxSelection: 1,
            category: .utilities,
            description: "计算文件 SHA256 并复制"
        ),
        LibraryScript(
            name: "SHA512 哈希",
            type: .bash,
            content: "# Runs natively via MiaoRight (SHA512 hash).",
            icon: "checkmark.shield.fill",
            appliesTo: .filesOnly,
            maxSelection: 1,
            category: .utilities,
            description: "计算文件 SHA512 并复制"
        ),
        LibraryScript(
            name: "生成 .sha256 校验文件",
            type: .bash,
            content: "# Runs natively via MiaoRight (Create sha256 file).",
            icon: "checkmark.shield",
            appliesTo: .filesOnly,
            category: .utilities,
            description: "在旁边生成 .sha256 校验文件"
        ),
        LibraryScript(
            name: "压缩为 ZIP",
            type: .bash,
            content: "# Runs natively via MiaoRight (Compress to ZIP).",
            icon: "doc.zipper",
            appliesTo: .allItems,
            category: .share,
            description: "把所选文件压缩为 ZIP"
        ),
        LibraryScript(
            name: "解压到当前文件夹",
            type: .bash,
            content: "# Runs natively via MiaoRight (Extract ZIP here).",
            icon: "arrow.up.doc",
            appliesTo: .filesOnly,
            fileExtensions: ["zip"],
            category: .utilities,
            description: "把 ZIP 解压到旁边的新文件夹，支持输入密码"
        ),
        LibraryScript(
            name: "创建 TAR.GZ",
            type: .bash,
            content: "# Runs natively via MiaoRight (Create TAR.GZ).",
            icon: "archivebox",
            appliesTo: .allItems,
            category: .utilities,
            description: "创建 .tar.gz 压缩包"
        ),
        LibraryScript(
            name: "解压 TAR.GZ",
            type: .bash,
            content: "# Runs natively via MiaoRight (Extract TAR.GZ here).",
            icon: "arrow.down.doc",
            appliesTo: .filesOnly,
            fileExtensions: ["tar.gz", "tgz"],
            extensionMatchMode: .any,
            category: .utilities,
            description: "把 TAR.GZ / TGZ 解压到旁边的新文件夹"
        ),
        LibraryScript(
            name: "压缩为 7Z",
            type: .bash,
            content: "# Runs natively via MiaoRight (Compress to 7Z).",
            icon: "archivebox.fill",
            appliesTo: .allItems,
            category: .share,
            description: "使用内置工具压缩为 7Z，无需额外安装"
        ),
        LibraryScript(
            name: "解压 7Z",
            type: .bash,
            content: "# Runs natively via MiaoRight (Extract 7Z).",
            icon: "arrow.up.doc",
            appliesTo: .filesOnly,
            fileExtensions: ["7z"],
            category: .utilities,
            description: "把 7Z 解压到旁边的新文件夹，支持输入密码"
        ),
        LibraryScript(
            name: "锁定文件",
            type: .bash,
            content: "# Runs natively via MiaoRight (Lock file).",
            icon: "lock",
            appliesTo: .allItems,
            category: .utilities,
            description: "锁定文件,防止被修改或删除"
        ),
        LibraryScript(
            name: "解锁文件",
            type: .bash,
            content: "# Runs natively via MiaoRight (Unlock file).",
            icon: "lock.open",
            appliesTo: .allItems,
            category: .utilities,
            description: "解除文件的锁定状态"
        ),
        LibraryScript(
            name: "查看文件十六进制",
            type: .bash,
            content: "# Runs natively via MiaoRight (View raw data).",
            icon: "01.square",
            appliesTo: .filesOnly,
            maxSelection: 1,
            category: .utilities,
            description: "查看文件开头的十六进制数据"
        ),
        LibraryScript(
            name: "强制解除文件占用",
            type: .bash,
            content: "# Runs natively via MiaoRight (Force close apps using file).",
            icon: "xmark.circle",
            appliesTo: .filesOnly,
            maxSelection: 1,
            category: .utilities,
            description: "结束占用此文件的进程",
            confirmBeforeRun: true
        ),
        LibraryScript(
            name: "路径转二维码",
            type: .bash,
            content: "# Runs natively via MiaoRight (QR code from path).",
            icon: "qrcode",
            appliesTo: .allItems,
            maxSelection: 1,
            category: .share,
            description: "把文件路径生成二维码图片并复制"
        ),
        LibraryScript(
            name: "恢复默认文件夹图标",
            type: .bash,
            content: "# Runs natively via MiaoRight (Reset folder icon).",
            icon: "arrow.uturn.backward.square",
            appliesTo: .foldersOnly,
            maxSelection: 1,
            category: .utilities,
            description: "清除自定义图标,还原系统默认文件夹外观"
        )
    ]
}
