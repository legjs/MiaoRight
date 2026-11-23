import AppKit
import Foundation
import MiaoRightShared

// MARK: - 数据槽类型

/// 管道中流动的数据类型。组合动作的第一步输入是右键选中的文件;
/// 之后的每一步吃上一步的产物,输出继续向下传。
enum PipelineSlot: String, Codable {
    case files // 文件/文件夹路径列表
    case text // 纯文本
    case any // 两者皆可
    case none // 该步骤不消费输入(极少;一般用于"源"步骤)
}

// MARK: - 参数描述(给无代码编辑器的表单规格)

/// 一个原子步骤的可配置参数。值统一按 String 持久化,
/// kind 只描述编辑器该渲染哪种控件。
struct AtomicParamSpec {
    enum Kind {
        case text(String?) // 占位提示
        case number
        case toggle // 开/关
        case choice([(value: String, title: String)]) // 单选
        case folderPick // 文件夹选择器
        case appPick // 应用选择器
    }

    let key: String
    let title: String
    let kind: Kind
    let isRequired: Bool
    let defaultValue: String?
}

// MARK: - 原子能力

/// 一块"积木":最小的可组合能力(移动文件、转格式、弹通知……)。
/// 定义与实现同体注册 —— `registry` 是唯一的原子目录。
struct AtomicOperation {
    let id: String // 稳定标识,如 "file.move";持久化在组合动作 JSON 里
    let title: String // 中文名(编辑器显示)
    let emoji: String
    let category: AtomicCategory
    let input: PipelineSlot
    let output: PipelineSlot
    /// 破坏性(删除/移动/覆盖原文件):出现在组合中时,整个动作执行前自动要求确认
    let isDestructive: Bool
    let params: [AtomicParamSpec]
    /// 执行体。返回 (输出值, 给用户的完成描述)。
    let run: @Sendable (_ input: PipelineValue, _ params: [String: String]) async throws -> (PipelineValue, String)
}

enum AtomicCategory: String, CaseIterable {
    case file = "文件"
    case image = "图片"
    case clipboard = "剪贴板"
    case system = "系统与交互"
    case info = "信息"

    var emoji: String {
        switch self {
        case .file: "📁"
        case .image: "🖼"
        case .clipboard: "📋"
        case .system: "🔔"
        case .info: "🔎"
        }
    }
}

// MARK: - 管道值

/// 步骤间传递的数据
enum PipelineValue {
    case files([URL])
    case text(String)
    case none

    var slot: PipelineSlot {
        switch self {
        case .files: .files
        case .text: .text
        case .none: .none
        }
    }

    var filePaths: [String] {
        if case .files(let urls) = self { return urls.map(\.path) }
        return []
    }

    /// 摘要(通知/错误信息用)
    var summary: String {
        switch self {
        case .files(let urls): urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) 个文件"
        case .text(let s): String(s.prefix(60))
        case .none: "无"
        }
    }
}

// MARK: - 原子注册表(唯一的原子目录;编辑器与引擎都从这里取)

enum AtomRegistry {
    static let all: [AtomicOperation] = [
        // ---- 文件 ----
        AtomicOperation(
            id: "file.openFolder", title: "打开常用文件夹", emoji: "📂", category: .file,
            input: .none, output: .none, isDestructive: false,
            params: [.init(key: "folder", title: "文件夹", kind: .folderPick, isRequired: true, defaultValue: nil)]
        ) { _, params in
            let folder = try QuickFileOperations.folder(params["folder"] ?? "")
            if !AppGroup.isIsolated { await MainActor.run { _ = NSWorkspace.shared.open(folder) } }
            return (.none, L10n.text("已打开：\(folder.path)", "Opened: \(folder.path)"))
        },
        AtomicOperation(
            id: "file.fromTemplate", title: "从模板新建", emoji: "📄", category: .file,
            input: .files, output: .files, isDestructive: false,
            params: [.init(key: "templatePath", title: "模板", kind: .text(nil), isRequired: true, defaultValue: nil)]
        ) { input, params in
            let urls = try input.requireFiles(L10n.text("从模板新建", "New from Template"))
            guard let first = urls.first, let path = params["templatePath"], path.hasPrefix("/") else {
                throw PipelineError.param(L10n.text("请选择模板和目标文件夹。", "Choose a template and destination folder."))
            }
            let destination = try QuickFileOperations.destinationFolder(for: first)
            let created = try QuickFileOperations.createFromTemplate(URL(fileURLWithPath: path), in: destination)
            return (.files([created]), L10n.text("已创建：\(created.path)", "Created: \(created.path)"))
        },
        AtomicOperation(
            id: "file.copy", title: "复制到文件夹", emoji: "📑", category: .file,
            input: .files, output: .files, isDestructive: false,
            params: [
                AtomicParamSpec(key: "folder", title: "目标文件夹", kind: .folderPick, isRequired: true, defaultValue: nil),
            ]
        ) { input, params in
            let urls = try input.requireFiles("复制到文件夹")
            let dest = try paramFolder(params, key: "folder")
            if params["miaorightShortcut"] == "1" { _ = try QuickFileOperations.folder(dest.path) }
            let copied = try FileOps.copy(urls, to: dest)
            return (.files(copied), "已复制 \(copied.count) 项到「\(dest.lastPathComponent)」")
        },
        AtomicOperation(
            id: "file.move", title: "移动到文件夹", emoji: "📥", category: .file,
            input: .files, output: .files, isDestructive: true,
            params: [
                AtomicParamSpec(key: "folder", title: "目标文件夹", kind: .folderPick, isRequired: true, defaultValue: nil),
            ]
        ) { input, params in
            let urls = try input.requireFiles("移动到文件夹")
            let dest = try paramFolder(params, key: "folder")
            if params["miaorightShortcut"] == "1" { _ = try QuickFileOperations.folder(dest.path) }
            let moved = try FileOps.move(urls, to: dest)
            return (.files(moved), "已移动 \(moved.count) 项到「\(dest.lastPathComponent)」")
        },
        AtomicOperation(
            id: "file.duplicate", title: "创建副本", emoji: "🧬", category: .file,
            input: .files, output: .files, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("创建副本")
            let copies = try FileOps.duplicate(urls)
            return (.files(copies), "已创建 \(copies.count) 个副本")
        },
        AtomicOperation(
            id: "file.rename", title: "批量重命名", emoji: "✏️", category: .file,
            input: .files, output: .files, isDestructive: true,
            params: [
                AtomicParamSpec(key: "mode", title: "方式", kind: .choice([
                    ("lowercase", "文件名转小写"),
                    ("uppercase", "文件名转大写"),
                    ("spaces", "空格替换为下划线"),
                    ("sequence", "加序号前缀 001-"),
                ]), isRequired: true, defaultValue: "lowercase"),
            ]
        ) { input, params in
            let urls = try input.requireFiles("批量重命名")
            let renamed = try FileOps.rename(urls, mode: params["mode"] ?? "lowercase")
            return (.files(renamed), "已重命名 \(renamed.count) 项")
        },
        AtomicOperation(
            id: "file.toTrash", title: "移到废纸篓", emoji: "🗑", category: .file,
            input: .files, output: .none, isDestructive: true,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("移到废纸篓")
            for url in urls { _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            return (.none, "已把 \(urls.count) 项移到废纸篓")
        },
        AtomicOperation(
            id: "file.newFile", title: "新建文件", emoji: "📝", category: .file,
            input: .none, output: .files, isDestructive: false,
            params: [
                AtomicParamSpec(key: "name", title: "文件名", kind: .text("未命名.txt"), isRequired: true, defaultValue: "未命名.txt"),
            ]
        ) { _, params in
            let name = params["name"]?.isEmpty == false ? params["name"]! : "未命名.txt"
            let url = try FileOps.createFile(name: name)
            return (.files([url]), "已新建「\(name)」")
        },
        AtomicOperation(
            id: "file.newFolder", title: "新建文件夹", emoji: "📁", category: .file,
            input: .none, output: .files, isDestructive: false,
            params: [
                AtomicParamSpec(key: "name", title: "文件夹名", kind: .text("新建文件夹"), isRequired: true, defaultValue: "新建文件夹"),
            ]
        ) { _, params in
            let name = params["name"]?.isEmpty == false ? params["name"]! : "新建文件夹"
            let url = try FileOps.createFolder(name: name)
            return (.files([url]), "已新建「\(name)」")
        },
        AtomicOperation(
            id: "file.zip", title: "压缩为 ZIP", emoji: "🗜", category: .file,
            input: .files, output: .files, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("压缩为 ZIP")
            let zip = try await FileOps.zip(urls)
            return (.files([zip]), "已压缩为「\(zip.lastPathComponent)」")
        },
        AtomicOperation(
            id: "file.unzip", title: "解压", emoji: "📂", category: .file,
            input: .files, output: .files, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("解压")
            let out = try await FileOps.unzip(urls)
            return (.files(out), "已解压 \(urls.count) 个压缩包")
        },
        AtomicOperation(
            id: "file.reveal", title: "在 Finder 中显示", emoji: "🔍", category: .file,
            input: .any, output: .none, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("在 Finder 中显示")
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return (.none, "已在 Finder 中显示")
        },
        AtomicOperation(
            id: "file.open", title: "打开", emoji: "▶️", category: .file,
            input: .files, output: .none, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("打开")
            for url in urls { NSWorkspace.shared.open(url) }
            return (.none, "已打开 \(urls.count) 项")
        },
        AtomicOperation(
            id: "file.openWith", title: "用指定应用打开", emoji: "🚀", category: .file,
            input: .files, output: .none, isDestructive: false,
            params: [
                AtomicParamSpec(key: "appPath", title: "应用", kind: .appPick, isRequired: true, defaultValue: nil),
            ]
        ) { input, params in
            let urls = try input.requireFiles("用指定应用打开")
            guard let appPath = params["appPath"], !appPath.isEmpty else {
                throw PipelineError.param("「用指定应用打开」需要先选择应用")
            }
            let appURL = URL(fileURLWithPath: (appPath as NSString).expandingTildeInPath)
            let workspace = NSWorkspace.shared
            for url in urls {
                _ = try? workspace.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
            return (.none, "已用「\(appURL.deletingPathExtension().lastPathComponent)」打开")
        },

        // ---- 图片 ----
        AtomicOperation(
            id: "image.convert", title: "转换图片格式", emoji: "🔄", category: .image,
            input: .files, output: .files, isDestructive: false,
            params: [
                AtomicParamSpec(key: "format", title: "目标格式", kind: .choice([
                    ("jpeg", "JPG"),
                    ("png", "PNG"),
                    ("heic", "HEIC"),
                    ("pdf", "PDF"),
                ]), isRequired: true, defaultValue: "jpeg"),
            ]
        ) { input, params in
            let urls = try input.requireFiles("转换图片格式")
            let format = params["format"] ?? "jpeg"
            let out = try ImageOps.convert(urls, format: format)
            return (.files(out), "已转换为 \(format.uppercased()),产出 \(out.count) 个文件")
        },
        AtomicOperation(
            id: "image.resize", title: "缩放图片", emoji: "📐", category: .image,
            input: .files, output: .files, isDestructive: false,
            params: [
                AtomicParamSpec(key: "width", title: "目标宽度(像素)", kind: .number, isRequired: true, defaultValue: "1280"),
            ]
        ) { input, params in
            let urls = try input.requireFiles("缩放图片")
            guard let width = Int(params["width"] ?? ""), width > 0 else {
                throw PipelineError.param("「缩放图片」的宽度必须是正整数")
            }
            let out = try ImageOps.resize(urls, width: width)
            return (.files(out), "已缩放到 \(width)px 宽,产出 \(out.count) 个文件")
        },
        AtomicOperation(
            id: "image.rotate", title: "旋转图片", emoji: "🔀", category: .image,
            input: .files, output: .files, isDestructive: false,
            params: [
                AtomicParamSpec(key: "degrees", title: "角度", kind: .choice([
                    ("90", "顺时针 90°"), ("180", "180°"), ("270", "顺时针 270°"),
                ]), isRequired: true, defaultValue: "90"),
            ]
        ) { input, params in
            let urls = try input.requireFiles("旋转图片")
            let out = try ImageOps.rotate(urls, degrees: params["degrees"] ?? "90")
            return (.files(out), "已旋转,产出 \(out.count) 个文件")
        },
        AtomicOperation(
            id: "image.wallpaper", title: "设为桌面壁纸", emoji: "🏞", category: .image,
            input: .files, output: .none, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("设为桌面壁纸")
            guard let first = urls.first else { throw PipelineError.param("请选择一张图片") }
            try await ImageOps.setWallpaper(first)
            return (.none, "已设置桌面壁纸")
        },

        // ---- 剪贴板 ----
        AtomicOperation(
            id: "clipboard.write", title: "复制文本到剪贴板", emoji: "📋", category: .clipboard,
            input: .any, output: .none, isDestructive: false,
            params: [
                AtomicParamSpec(key: "text", title: "文本内容", kind: .text("要复制的文字"), isRequired: true, defaultValue: ""),
            ]
        ) { input, params in
            let text = params["text"] ?? ""
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return (.none, "已复制到剪贴板")
        },
        AtomicOperation(
            id: "clipboard.writePaths", title: "复制文件路径", emoji: "🔗", category: .clipboard,
            input: .files, output: .none, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("复制文件路径")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            return (.none, "已复制 \(urls.count) 个路径")
        },

        // ---- 系统与交互 ----
        AtomicOperation(
            id: "system.notify", title: "发送通知", emoji: "🔔", category: .system,
            input: .any, output: .none, isDestructive: false,
            params: [
                AtomicParamSpec(key: "title", title: "标题", kind: .text(nil), isRequired: false, defaultValue: "妙右"),
                AtomicParamSpec(key: "text", title: "内容", kind: .text("要显示的文字"), isRequired: true, defaultValue: "完成"),
            ]
        ) { _, params in
            let title = params["title"]?.isEmpty == false ? params["title"]! : "妙右"
            let text = params["text"] ?? ""
            let _ = try? await Shell.run("/usr/bin/osascript", ["-e", "display notification \"\(text.escapedForAppleScript)\" with title \"\(title.escapedForAppleScript)\""])
            return (.none, "已发送通知")
        },
        AtomicOperation(
            id: "system.alert", title: "弹窗提示", emoji: "💬", category: .system,
            input: .any, output: .none, isDestructive: false,
            params: [
                AtomicParamSpec(key: "title", title: "标题", kind: .text(nil), isRequired: false, defaultValue: "妙右"),
                AtomicParamSpec(key: "text", title: "内容", kind: .text("要显示的文字"), isRequired: true, defaultValue: ""),
            ]
        ) { _, params in
            let title = params["title"]?.isEmpty == false ? params["title"]! : "妙右"
            let text = params["text"] ?? ""
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = text
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
            return (.none, "已弹窗提示")
        },
        AtomicOperation(
            id: "system.askFolder", title: "弹窗选择文件夹", emoji: "📂", category: .system,
            input: .any, output: .files, isDestructive: false,
            params: [
                AtomicParamSpec(key: "prompt", title: "提示文字", kind: .text(nil), isRequired: false, defaultValue: "选择文件夹"),
            ]
        ) { _, params in
            let prompt = params["prompt"]?.isEmpty == false ? params["prompt"]! : "选择文件夹"
            let picked = await MainActor.run { () -> URL? in
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.message = prompt
                NSApp.activate(ignoringOtherApps: true)
                return panel.runModal() == .OK ? panel.url : nil
            }
            guard let picked else { throw PipelineError.cancelled }
            return (.files([picked]), "已选择「\(picked.lastPathComponent)」")
        },
        AtomicOperation(
            id: "system.askText", title: "弹窗输入文字", emoji: "⌨️", category: .system,
            input: .any, output: .text, isDestructive: false,
            params: [
                AtomicParamSpec(key: "prompt", title: "提示文字", kind: .text(nil), isRequired: false, defaultValue: "请输入"),
                AtomicParamSpec(key: "defaultValue", title: "默认值", kind: .text(nil), isRequired: false, defaultValue: ""),
            ]
        ) { _, params in
            let prompt = params["prompt"]?.isEmpty == false ? params["prompt"]! : "请输入"
            let def = params["defaultValue"] ?? ""
            let answer = await MainActor.run { () -> String? in
                let alert = NSAlert()
                alert.messageText = prompt
                let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
                field.stringValue = def
                alert.accessoryView = field
                NSApp.activate(ignoringOtherApps: true)
                return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
            }
            guard let answer else { throw PipelineError.cancelled }
            return (.text(answer), "已输入文字")
        },
        AtomicOperation(
            id: "system.airdrop", title: "隔空投送", emoji: "📡", category: .system,
            input: .files, output: .none, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("隔空投送")
            try await MainActor.run {
                guard let service = NSSharingService(named: .sendViaAirDrop) else {
                    throw PipelineError.runtime("当前环境不支持隔空投送")
                }
                NSApp.activate(ignoringOtherApps: true)
                service.perform(withItems: urls)
            }
            return (.none, "已打开隔空投送")
        },
        AtomicOperation(
            id: "system.openURL", title: "打开网址", emoji: "🌐", category: .system,
            input: .any, output: .none, isDestructive: false,
            params: [
                AtomicParamSpec(key: "url", title: "网址", kind: .text("https://…"), isRequired: true, defaultValue: nil),
            ]
        ) { _, params in
            guard let raw = params["url"], !raw.isEmpty, let url = URL(string: raw) else {
                throw PipelineError.param("「打开网址」需要有效网址")
            }
            NSWorkspace.shared.open(url)
            return (.none, "已打开 \(raw)")
        },
        AtomicOperation(
            id: "system.openApp", title: "打开应用", emoji: "🚀", category: .system,
            input: .any, output: .none, isDestructive: false,
            params: [
                AtomicParamSpec(key: "appPath", title: "应用", kind: .appPick, isRequired: true, defaultValue: nil),
            ]
        ) { _, params in
            guard let appPath = params["appPath"], !appPath.isEmpty else {
                throw PipelineError.param("「打开应用」需要先选择应用")
            }
            let appURL = URL(fileURLWithPath: (appPath as NSString).expandingTildeInPath)
            let config = NSWorkspace.OpenConfiguration()
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return (.none, "已打开「\(appURL.deletingPathExtension().lastPathComponent)」")
        },
        AtomicOperation(
            id: "system.shell", title: "运行 Shell 命令(高级)", emoji: "⌨️", category: .system,
            input: .any, output: .text, isDestructive: false,
            params: [
                AtomicParamSpec(key: "command", title: "命令", kind: .text("echo hello"), isRequired: true, defaultValue: nil),
            ]
        ) { input, params in
            guard let command = params["command"], !command.isEmpty else {
                throw PipelineError.param("「运行 Shell 命令」需要命令内容")
            }
            // 输入文件路径附在命令尾部,脚本内用 $1 $2 / $@ 取用(与旧 shell 动作一致)
            var args = ["-c", command, "miaoright"]
            args.append(contentsOf: input.filePaths)
            let (code, out) = try await Shell.runRaw("/bin/bash", args)
            guard code == 0 else {
                throw PipelineError.runtime("命令失败(exit \(code)):\(out)")
            }
            return (.text(out), "命令已执行")
        },

        // ---- 内置菜单调用 ----
        AtomicOperation(
            id: "builtin.run", title: "调用内置菜单", emoji: "🧩", category: .system,
            input: .files, output: .files, isDestructive: false,
            params: [
                AtomicParamSpec(key: "name", title: "内置菜单名", kind: .text("如:按类型整理"), isRequired: true, defaultValue: nil),
            ]
        ) { input, params in
            guard let name = params["name"], !name.isEmpty else {
                throw PipelineError.param("「调用内置菜单」需要指定菜单名")
            }
            let paths = try input.requireFiles("调用内置菜单")
            let (message, produced) = try await BuiltinRunner.run(named: name, inputPaths: paths.map(\.path))
            // 有差分产物则传产物,否则透传输入(调用不改变数据流时)
            if produced.isEmpty {
                return (.files(paths), message.isEmpty ? "已调用「\(name)」" : message)
            }
            return (.files(produced.map { URL(fileURLWithPath: $0) }), message.isEmpty ? "已调用「\(name)」" : message)
        },

        // ---- 信息 ----
        AtomicOperation(
            id: "info.paths", title: "取文件路径", emoji: "🔗", category: .info,
            input: .files, output: .text, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("取文件路径")
            return (.text(urls.map(\.path).joined(separator: "\n")), "已取出 \(urls.count) 个路径")
        },
        AtomicOperation(
            id: "info.names", title: "取文件名", emoji: "🏷", category: .info,
            input: .files, output: .text, isDestructive: false,
            params: []
        ) { input, _ in
            let urls = try input.requireFiles("取文件名")
            return (.text(urls.map(\.lastPathComponent).joined(separator: "\n")), "已取出 \(urls.count) 个文件名")
        },
    ]

    static func operation(_ id: String) -> AtomicOperation? {
        all.first { $0.id == id }
    }
}

// MARK: - 错误

enum PipelineError: Error, LocalizedError {
    case param(String)
    case runtime(String)
    case typeMismatch(step: String, wants: PipelineSlot, got: PipelineSlot)
    case unknownAtom(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .param(let m): m
        case .runtime(let m): m
        case .typeMismatch(let step, let wants, let got):
            "步骤「\(step)」需要\(wants.displayName)输入,但上游传来的是\(got.displayName)"
        case .unknownAtom(let id): "未知原子能力「\(id)」(可能来自更高版本)"
        case .cancelled: "已取消"
        }
    }
}

extension PipelineSlot {
    var displayName: String {
        switch self {
        case .files: "文件"
        case .text: "文本"
        case .any: "任意"
        case .none: "空"
        }
    }
}

// MARK: - 小工具

private func paramFolder(_ params: [String: String], key: String) throws -> URL {
    guard let raw = params[key], !raw.isEmpty else {
        throw PipelineError.param("缺少文件夹参数")
    }
    let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

extension PipelineValue {
    func requireFiles(_ step: String) throws -> [URL] {
        if case .files(let urls) = self, !urls.isEmpty { return urls }
        throw PipelineError.typeMismatch(step: step, wants: .files, got: slot)
    }
}

extension String {
    var escapedForAppleScript: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
