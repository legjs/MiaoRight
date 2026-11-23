import AppKit
import CoreImage
import CryptoKit
import Foundation
import MiaoRightShared
import UniformTypeIdentifiers

// MiaoRight 新增动作的原生实现:新建文件、剪切/粘贴、移动/复制到常用文件夹、
// 隔空投送、彻底删除、解散文件夹、隐藏、快捷方式、二维码、壁纸、文件夹图标、
// 压缩解压、打开指定 App 等。全部在主 App 进程内执行(直发版本非沙盒)。
extension NativeActionExecutor {
    /// 需要 UI(面板/分享服务)的动作必须在主线程执行。
    static func requiresMainActorUI(_ action: NativeAction) -> Bool {
        switch action {
        case .airdropShare, .setFolderIconFromImage, .setDesktopWallpaper,
             .moveToFavoriteFolder, .copyToFavoriteFolder, .openWithOtherApp,
             .newTextDoc, .newMarkdownNote, .newRTFDoc, .newWordDoc,
             .newExcelWorkbook, .newPPTDeck, .newFolderHere:
            true // 新建类需弹命名框,走 MainActor UI 路径
        default:
            false
        }
    }

    // MARK: - 新建文件

    enum NewDocKind {
        case txt, markdown, rtf, docx, xlsx, pptx

        var preferredName: String {
            switch self {
            case .txt: "未命名"
            case .markdown: "未命名笔记"
            case .rtf: "未命名"
            case .docx: "未命名"
            case .xlsx: "未命名"
            case .pptx: "未命名演示文稿"
            }
        }

        var pathExtension: String {
            switch self {
            case .txt: "txt"
            case .markdown: "md"
            case .rtf: "rtf"
            case .docx: "docx"
            case .xlsx: "xlsx"
            case .pptx: "pptx"
            }
        }
    }

    /// 新建前的命名对话框:预填默认名,返回完整文件名;取消抛错中止创建
    @MainActor
    private static func askFileName(prompt: String, defaultName: String) throws -> String {
        guard !AppGroup.isIsolated else { throw ScriptError.executionFailed(L10n.text("离屏测试不会打开命名对话框。", "Offscreen tests do not open naming dialogs.")) }
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultName
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("创建", "Create"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            throw ScriptError.executionFailed("已取消")
        }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", !trimmed.hasPrefix("/") else {
            throw ScriptError.executionFailed("文件名无效")
        }
        return trimmed
    }

    @MainActor
    static func createNewDocument(_ urls: [URL], kind: NewDocKind) throws -> String {
        guard let first = urls.first else {
            throw ScriptError.executionFailed("没有可用的文件夹。")
        }
        let folder = parentFolder(for: first)
        // 先命名再创建,免去创建后手动重命名
        let defaultName = "\(kind.preferredName).\(kind.pathExtension)"
        let typed = try askFileName(prompt: L10n.text("新建文件", "New File"), defaultName: defaultName)
        let name = typed.contains(".") ? typed : "\(typed).\(kind.pathExtension)"
        let destination = uniqueDestinationURL(
            in: folder,
            preferredName: (name as NSString).deletingPathExtension,
            pathExtension: (name as NSString).pathExtension
        )

        switch kind {
        case .txt:
            FileManager.default.createFile(atPath: destination.path, contents: Data())
        case .markdown:
            let template = "# \(destination.deletingPathExtension().lastPathComponent)\n\n"
            FileManager.default.createFile(
                atPath: destination.path,
                contents: template.data(using: .utf8)
            )
        case .rtf:
            let rtf = "{\\rtf1\\ansi\\ansicpg936\\cocoartf2761\n\\cocoatextscaling0\\cocoaplatform0{\\fonttbl}\n{\\colortbl;\\red255\\green255\\blue255;}\n}"
            FileManager.default.createFile(
                atPath: destination.path,
                contents: rtf.data(using: .utf8)
            )
        case .docx:
            try createDocx(at: destination)
        case .xlsx:
            try createOOXMLDocument(xlsxFiles(), at: destination)
        case .pptx:
            try createOOXMLDocument(pptxFiles(), at: destination)
        }

        // 在 Finder 中定位刚创建的文件,接续重命名/打开都方便
        FileOperationJournal.shared.recordOutputs([destination])
        if !AppGroup.isIsolated { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
        return destination.lastPathComponent
    }

    /// 通过 macOS 自带 textutil 生成一个合法的最小 .docx。
    private static func createDocx(at destination: URL) throws {
        let tmpTXT = FileManager.default.temporaryDirectory
            .appendingPathComponent("miaoright-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: tmpTXT.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tmpTXT) }

        let result = runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/textutil"),
            arguments: ["-convert", "docx", tmpTXT.path, "-output", destination.path]
        )
        switch result {
        case .success:
            break
        case let .failure(error):
            throw error
        }
    }

    /// 生成最小 OOXML 文档(xlsx / pptx):写出文件字典后用统一 7-Zip 后端打包。
    static func createOOXMLDocument(_ files: [String: String], at destination: URL, archiver: SevenZipArchive = SevenZipArchive()) throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("miaoright-ooxml-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        for (relativePath, content) in files {
            let fileURL = tmpDir.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.data(using: .utf8)!.write(to: fileURL)
        }

        // 顶层条目直接进入 ZIP 根目录，保持 OOXML 容器结构。
        let topLevelEntries = Set(files.keys.map { $0.split(separator: "/").first.map(String.init) ?? $0 }).sorted()
        _ = try archiver.compress(topLevelEntries.map { tmpDir.appendingPathComponent($0) }, format: .zip, at: destination)
    }

    private static func xlsxFiles() -> [String: String] {
        [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
            </Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
            </Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
            </workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
            </Relationships>
            """,
            "xl/worksheets/sheet1.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <sheetData><row r="1"><c r="A1"><v></v></c></row></sheetData>
            </worksheet>
            """,
            "xl/styles.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
            <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
            <borders count="1"><border/></borders>
            <cellStyleXfs count="1"><xf/></cellStyleXfs>
            <cellXfs count="1"><xf xfId="0"/></cellXfs>
            </styleSheet>
            """
        ]
    }

    private static func pptxFiles() -> [String: String] {
        let themeXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office">
        <a:themeElements>
        <a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="4472C4"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme>
        <a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>
        <a:fmtScheme name="Office">
        <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>
        <a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>
        <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst><a:outerShdw blurRad="57150" dist="19050" dir="5400000" algn="ctr" rotWithShape="0"><a:srgbClr val="000000"><a:alpha val="63000"/></a:srgbClr></a:outerShdw></a:effectLst></a:effectStyle></a:effectStyleLst>
        <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>
        </a:fmtScheme>
        </a:themeElements>
        </a:theme>
        """
        return [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
            <Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
            <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
            <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
            <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
            </Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
            </Relationships>
            """,
            "ppt/presentation.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
            <p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst>
            <p:sldSz cx="12192000" cy="6858000"/>
            </p:presentation>
            """,
            "ppt/_rels/presentation.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
            <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
            </Relationships>
            """,
            "ppt/slides/slide1.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
            <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
            <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
            </p:sld>
            """,
            "ppt/slides/_rels/slide1.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
            </Relationships>
            """,
            "ppt/slideMasters/slideMaster1.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
            <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
            <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
            <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/></p:sldLayoutIdLst>
            </p:sldMaster>
            """,
            "ppt/slideMasters/_rels/slideMaster1.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
            </Relationships>
            """,
            "ppt/slideLayouts/slideLayout1.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" type="blank" preserve="1">
            <p:cSld name="空白"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
            <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
            </p:sldLayout>
            """,
            "ppt/slideLayouts/_rels/slideLayout1.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
            </Relationships>
            """,
            "ppt/theme/theme1.xml": themeXML
        ]
    }

    @MainActor
    static func newFolderHere(_ urls: [URL]) throws -> String {
        guard let first = urls.first else {
            throw ScriptError.executionFailed("没有可用的文件夹。")
        }
        let typed = try askFileName(prompt: L10n.text("新建文件夹", "New Folder"), defaultName: "未命名文件夹")
        let destination = uniqueDestinationURL(in: parentFolder(for: first), preferredName: typed)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        return destination.lastPathComponent
    }

    static func newFolderFromFilename(_ urls: [URL]) throws -> String {
        guard let first = urls.first else {
            throw ScriptError.executionFailed("没有选中文件。")
        }
        let name = first.deletingPathExtension().lastPathComponent
        let destination = uniqueDestinationURL(in: first.deletingLastPathComponent(), preferredName: name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return destination.lastPathComponent
    }

    // MARK: - 剪切 / 粘贴 / 移动 / 复制

    static func cutItems(_ urls: [URL]) throws -> String {
        CutClipboard.save(paths: urls.map(\.path))
        ensurePasteEnabled()
        return L10n.text("已剪切 \(urls.count) 项，在目标文件夹执行“粘贴”完成移动。", "Cut \(urls.count) items. Paste in the destination folder to move them.")
    }

    /// 剪切/粘贴是配对功能:执行剪切时确保「粘贴」处于启用状态。
    /// 防止粘贴被误关后,用户剪切完在目标文件夹找不到粘贴入口。
    private static func ensurePasteEnabled() {
        DispatchQueue.main.async {
            let store = ScriptStore.shared
            store.loadIfNeeded()
            guard let paste = store.scripts.first(where: { $0.name == ActionID.paste }),
                  !paste.isEnabled
            else { return }
            var updated = paste
            updated.isEnabled = true
            store.updateScript(updated)
        }
    }

    static func pasteItems(_ urls: [URL]) throws -> String {
        guard let state = CutClipboard.load(), !state.paths.isEmpty else {
            throw ScriptError.executionFailed(L10n.text("没有待移动的文件，请先执行“剪切”。", "Nothing to move. Cut files first."))
        }
        guard let first = urls.first else {
            throw ScriptError.executionFailed(L10n.text("没有可用的目标文件夹。", "No destination folder is available."))
        }
        let destination = parentFolder(for: first).resolvingSymlinksInPath().standardizedFileURL
        var remaining = state.paths
        var moved = 0
        for path in state.paths {
            let source = URL(fileURLWithPath: path)
            guard source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL != destination else { continue }
            let target = uniqueDestinationURL(in: destination, preferredName: source.deletingPathExtension().lastPathComponent, pathExtension: source.pathExtension)
            do {
                try FileManager.default.moveItem(at: source, to: target)
                FileOperationJournal.shared.recordCompleted([FileMove(source: source, destination: target)], title: L10n.text("移动", "Move"))
            }
            catch {
                CutClipboard.save(paths: remaining)
                throw ScriptError.executionFailed(L10n.text(
                    "已移动 \(moved) 项，未完成的 \(remaining.count) 项仍保留为待移动。原因：\(error.localizedDescription)",
                    "Moved \(moved) items. \(remaining.count) unfinished items are still ready to paste. Reason: \(error.localizedDescription)"
                ))
            }
            moved += 1
            remaining.removeAll { $0 == path }
            if remaining.isEmpty { CutClipboard.clear() } else { CutClipboard.save(paths: remaining) }
        }
        if moved == 0 {
            return L10n.text("文件已在目标文件夹中，无需移动。", "The files are already in this folder; nothing was moved.")
        }
        return L10n.text("已移动 \(moved) 项到“\(destination.lastPathComponent)”。", "Moved \(moved) items to “\(destination.lastPathComponent)”.")
    }

    /// 把所选项目移动/复制到指定目标文件夹(目标必填;面板选择由 UI 路径完成)。
    static func moveCopyItems(_ urls: [URL], destination: String, copy: Bool) throws -> String {
        let targetURL = URL(fileURLWithPath: destination, isDirectory: true)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw ScriptError.executionFailed("目标文件夹不存在。")
        }

        let results = try copy ? FileOps.copy(urls, to: targetURL) : FileOps.move(urls, to: targetURL)
        return copy ? L10n.text("已复制 \(results.count) 项到 \(targetURL.path)", "Copied \(results.count) items to \(targetURL.path)")
            : L10n.text("已移动 \(results.count) 项到 \(targetURL.path)", "Moved \(results.count) items to \(targetURL.path)")
    }

    @MainActor
    static func chooseDirectory(prompt: String) -> URL? {
        guard !AppGroup.isIsolated else { return nil }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = prompt
        panel.prompt = "选择"
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - UI 路径(主线程)

    /// 需要 UI 的动作统一从这里进(由 ScriptExecutor 保证在主线程执行)。
    @MainActor
    static func executeUIAction(
        _ action: NativeAction,
        paths: [String],
        parameter: String?
    ) throws -> String {
        let urls = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        switch action {
        case .newTextDoc:
            return try createNewDocument(urls, kind: .txt)
        case .newMarkdownNote:
            return try createNewDocument(urls, kind: .markdown)
        case .newRTFDoc:
            return try createNewDocument(urls, kind: .rtf)
        case .newWordDoc:
            return try createNewDocument(urls, kind: .docx)
        case .newExcelWorkbook:
            return try createNewDocument(urls, kind: .xlsx)
        case .newPPTDeck:
            return try createNewDocument(urls, kind: .pptx)
        case .newFolderHere:
            return try newFolderHere(urls)
        case .airdropShare:
            return try airdropShare(urls)
        case .setFolderIconFromImage:
            return try setFolderIconFromImage(urls)
        case .setDesktopWallpaper:
            return try setDesktopWallpaper(urls)
        case .moveToFavoriteFolder:
            let target = parameter ?? chooseDirectory(prompt: "选择要移动到的文件夹")?.path
            guard let target else { throw ScriptError.executionFailed("已取消。") }
            return try moveCopyItems(urls, destination: target, copy: false)
        case .copyToFavoriteFolder:
            let target = parameter ?? chooseDirectory(prompt: "选择要复制到的文件夹")?.path
            guard let target else { throw ScriptError.executionFailed("已取消。") }
            return try moveCopyItems(urls, destination: target, copy: true)
        case .openWithOtherApp:
            return try openWithOtherApp(urls)
        default:
            throw ScriptError.executionFailed("该动作不需要 UI 上下文。")
        }
    }

    // MARK: - 隔空投送 / 彻底删除

    @MainActor
    static func airdropShare(_ urls: [URL]) throws -> String {
        let files = urls.filter { !$0.hasDirectoryPath }
        guard !files.isEmpty else {
            throw ScriptError.executionFailed("隔空投送只支持文件,请选择文件后重试。")
        }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            throw ScriptError.executionFailed("当前环境不支持隔空投送。")
        }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: files)
        return "已打开隔空投送"
    }

    static func deletePermanently(_ urls: [URL]) throws -> String {
        var deleted = 0
        for url in urls {
            var attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let locked = attributes[.immutable] as? Bool, locked {
                    attributes[.immutable] = false
                    try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
                }
            } catch {
                // 属性读取失败时仍尝试删除
            }
            try FileManager.default.removeItem(at: url)
            deleted += 1
        }
        return "已彻底删除 \(deleted) 项"
    }

    // MARK: - 文件管理

    static func dissolveFolder(_ urls: [URL]) throws -> String {
        guard let folder = urls.first, folder.hasDirectoryPath else {
            throw ScriptError.executionFailed("请选择一个文件夹。")
        }
        let parent = folder.deletingLastPathComponent()
        let children = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard !children.isEmpty else {
            try FileManager.default.removeItem(at: folder)
            return "空文件夹已删除"
        }

        for child in children {
            let target = uniqueDestinationURL(
                in: parent,
                preferredName: child.deletingPathExtension().lastPathComponent,
                pathExtension: child.pathExtension
            )
            try FileManager.default.moveItem(at: child, to: target)
        }
        try FileManager.default.removeItem(at: folder)
        return "已解散文件夹,保留 \(children.count) 个文件"
    }

    static func setHiddenFlag(_ urls: [URL], hidden: Bool) throws -> String {
        for url in urls {
            var attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            attributes[FileAttributeKey("NSFileHidden")] = hidden
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        }
        return hidden ? "已隐藏 \(urls.count) 项" : "已取消隐藏 \(urls.count) 项"
    }

    static func setLockedFlag(_ urls: [URL], locked: Bool) throws -> String {
        for url in urls {
            var attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            attributes[FileAttributeKey("NSFileImmutable")] = locked
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        }
        return locked ? "已锁定 \(urls.count) 项" : "已解锁 \(urls.count) 项"
    }

    static func sendAliasToDesktop(_ urls: [URL]) throws -> String {
        guard let first = urls.first else {
            throw ScriptError.executionFailed("没有选中文件。")
        }
        let desktop = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let aliasURL = uniqueDestinationURL(
            in: desktop,
            preferredName: first.deletingPathExtension().lastPathComponent,
            pathExtension: ""
        )
        let bookmarkData = try first.bookmarkData()
        try NSURL.writeBookmarkData(bookmarkData, to: aliasURL, options: 0)
        return "已在桌面创建快捷方式"
    }

    static func removeEmptyFolders(_ urls: [URL]) throws -> String {
        var removed = 0
        for url in urls where url.hasDirectoryPath {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }

            let directories = enumerator.compactMap { $0 as? URL }
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .sorted { $0.path.count > $1.path.count }

            for directory in directories {
                let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])) ?? []
                if contents.isEmpty, directory != url {
                    try? FileManager.default.removeItem(at: directory)
                    removed += 1
                }
            }
        }
        return "已清除 \(removed) 个空文件夹"
    }

    // MARK: - 打开应用

    static func openInApp(
        _ urls: [URL],
        bundleIDs: [String],
        appNames: [String],
        displayName: String,
        cliNames: [String] = []
    ) throws -> String {
        guard let first = urls.first else {
            throw ScriptError.executionFailed("没有选中文件。")
        }

        for bundleID in bundleIDs {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
                return "已在 \(displayName) 中打开"
            }
        }

        // 回退 1:通过 `open -a AppName`
        for appName in appNames {
            let result = runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-a", appName] + urls.map(\.path)
            )
            if case .success = result {
                return "已在 \(displayName) 中打开"
            }
        }

        // 回退 2:CLI(如 `code`、`cursor`)
        for cli in cliNames {
            if let cliURL = resolvedCLIPath(cli) {
                let result = runProcess(
                    executableURL: cliURL,
                    arguments: ["--"] + urls.map(\.path)
                )
                if case .success = result {
                    return "已在 \(displayName) 中打开"
                }
            }
        }

        throw ScriptError.executionFailed("未安装 \(displayName),请先安装。")
    }

    private static func resolvedCLIPath(_ name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - 壁纸 / 文件夹图标

    @MainActor
    static func setDesktopWallpaper(_ urls: [URL]) throws -> String {
        guard let image = urls.first(where: { !$0.hasDirectoryPath }) else {
            throw ScriptError.executionFailed("请选择一张图片。")
        }
        guard let screen = NSScreen.main else {
            throw ScriptError.executionFailed("未找到显示器。")
        }
        try NSWorkspace.shared.setDesktopImageURL(image, for: screen)
        return "已设为桌面壁纸"
    }

    @MainActor
    static func setFolderIconFromImage(_ urls: [URL]) throws -> String {
        guard let folder = urls.first(where: { $0.hasDirectoryPath }) else {
            throw ScriptError.executionFailed("请选择一个文件夹。")
        }
        guard let imageURL = chooseImage(prompt: "选择一张图片作为「\(folder.lastPathComponent)」的图标"),
              let image = NSImage(contentsOf: imageURL)
        else {
            throw ScriptError.executionFailed("已取消。")
        }
        guard NSWorkspace.shared.setIcon(image, forFile: folder.path) else {
            throw ScriptError.executionFailed("设置图标失败。")
        }
        return "已更新文件夹图标"
    }

    @MainActor
    private static func chooseImage(prompt: String) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.message = prompt
        panel.prompt = "选择"
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - 压缩 / 解压

    static func createSHA256File(_ urls: [URL]) throws -> String {
        for url in urls {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let destination = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + ".sha256")
            try "\(hash)  \(url.lastPathComponent)\n".write(
                to: destination, atomically: true, encoding: .utf8
            )
        }
        return "已生成 \(urls.count) 个校验文件"
    }

    static func compressToZIP(_ urls: [URL]) throws -> String {
        try compressArchive(urls, format: .zip)
    }

    static func createTARGZ(_ urls: [URL]) throws -> String {
        try compressArchive(urls, format: .tarGzip)
    }

    static func compressTo7Z(_ urls: [URL]) throws -> String {
        try compressArchive(urls, format: .sevenZip)
    }

    static func extractZIPHere(_ urls: [URL]) throws -> String {
        try extractArchives(urls, format: .zip)
    }

    static func extractTARGZ(_ urls: [URL]) throws -> String {
        try extractArchives(urls, format: .tarGzip)
    }

    static func extract7Z(_ urls: [URL]) throws -> String {
        try extractArchives(urls, format: .sevenZip)
    }

    static func extractAnyArchive(_ urls: [URL]) throws -> String {
        try extractArchives(urls, format: nil)
    }

    private static func compressArchive(_ urls: [URL], format: SevenZipArchive.Format) throws -> String {
        let destination = try SevenZipArchive().compress(urls, format: format)
        return L10n.text("已创建：\(destination.path)", "Created: \(destination.path)")
    }

    private static func extractArchives(_ urls: [URL], format: SevenZipArchive.Format?) throws -> String {
        let destinations = try SevenZipArchive().extract(urls, format: format, passwordProvider: requestArchivePassword)
        return L10n.text("已解压至：\n", "Extracted to:\n") + destinations.map(\.path).joined(separator: "\n")
    }

    static func requestArchivePassword(_ archiveName: String, retry: Bool) -> String? {
        guard !AppGroup.isIsolated else { return nil }
        if Thread.isMainThread {
            return MainActor.assumeIsolated { showArchivePasswordPrompt(archiveName, retry: retry) }
        }
        return DispatchQueue.main.sync { showArchivePasswordPrompt(archiveName, retry: retry) }
    }

    @MainActor
    private static func showArchivePasswordPrompt(_ archiveName: String, retry: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = retry ? L10n.text("密码不正确，请重试", "Incorrect Password. Try Again") : L10n.text("输入解压密码", "Enter Archive Password")
        alert.informativeText = L10n.text("压缩包“\(archiveName)”需要密码。", "The archive “\(archiveName)” requires a password.")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = L10n.text("密码", "Password")
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("解压", "Extract"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    // MARK: - 其他工具

    static func viewRawData(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("没有选中文件。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 512) ?? Data()

        let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        try copyToPasteboard(hex)

        let readable = String(data: data, encoding: .utf8)?
            .map { $0.isASCII && !$0.isNewline && $0.unicodeScalars.allSatisfy { $0.value >= 32 } ? $0 : "." }
            .reduce(into: "") { $0.append($1) } ?? ""
        return "前 \(data.count) 字节的十六进制已复制到剪贴板。\n\n\(hex.prefix(200))\n\nASCII 预览:\n\(readable.prefix(200))"
    }

    static func forceCloseUsingApps(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("没有选中文件。")
        }
        let result = runProcess(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: [url.path]
        )
        guard case let .success(output) = result, !output.isEmpty else {
            return "没有进程占用此文件"
        }

        var pids = Set<pid_t>()
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            if columns.count > 1, let pid = pid_t(columns[1]) {
                pids.insert(pid)
            }
        }
        guard !pids.isEmpty else {
            return "没有进程占用此文件"
        }
        for pid in pids {
            kill(pid, SIGKILL)
        }
        return "已结束 \(pids.count) 个占用进程"
    }

    static func generateQRCodeFromPath(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("没有选中文件。")
        }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        guard let filter else {
            throw ScriptError.executionFailed("无法创建二维码生成器。")
        }
        filter.setValue(url.path.data(using: .utf8), forKey: "message")
        filter.setValue("M", forKey: "errorCorrection")
        guard let outputImage = filter.outputImage else {
            throw ScriptError.executionFailed("二维码生成失败。")
        }

        let scale: CGFloat = 512 / outputImage.extent.width
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw ScriptError.executionFailed("二维码渲染失败。")
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScriptError.executionFailed("二维码导出失败。")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        return "文件路径二维码已复制到剪贴板"
    }

    // MARK: - 图标集 / 默认图标 / 用其他应用打开

    /// 生成 macOS 标准全尺寸 .iconset 目录(16~1024 含 @2x)并合成 .icns,
    /// 覆盖 Mac / iPhone / iPad / Apple Watch 常见尺寸规格。
    static func exportIconSet(_ urls: [URL]) throws -> String {
        guard let image = urls.first(where: { !$0.hasDirectoryPath }) else {
            throw ScriptError.executionFailed("请选择一张图片。")
        }
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ScriptError.executionFailed("无法读取图片:\(image.lastPathComponent)")
        }

        let baseName = image.deletingPathExtension().lastPathComponent
        let setDirectory = uniqueDestinationURL(
            in: image.deletingLastPathComponent(),
            preferredName: baseName,
            pathExtension: "iconset"
        )
        try FileManager.default.createDirectory(at: setDirectory, withIntermediateDirectories: true)

        // (文件名, 目标像素尺寸)
        let variants: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]

        for (fileName, pixelSize) in variants {
            guard let scaled = drawScaledCopy(cgImage, width: pixelSize, height: pixelSize),
                  let destination = CGImageDestinationCreateWithURL(
                    setDirectory.appendingPathComponent(fileName) as CFURL,
                    UTType.png.identifier as CFString, 1, nil)
            else {
                throw ScriptError.executionFailed("缩放失败:\(fileName)")
            }
            CGImageDestinationAddImage(destination, scaled, nil)
            CGImageDestinationFinalize(destination)
        }

        let icnsDestination = uniqueDestinationURL(
            in: image.deletingLastPathComponent(),
            preferredName: baseName,
            pathExtension: "icns"
        )
        let result = runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/iconutil"),
            arguments: ["-c", "icns", setDirectory.path, "-o", icnsDestination.path]
        )
        guard case .success = result else {
            return "已生成 \(setDirectory.lastPathComponent)(.icns 合成失败,请检查目录)"
        }
        return "已生成 \(icnsDestination.lastPathComponent) 和 \(setDirectory.lastPathComponent)"
    }

    /// 简单等比绘制缩放(LANCZOS)。
    private static func drawScaledCopy(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func resetFolderIcon(_ urls: [URL]) throws -> String {
        guard let folder = urls.first(where: { $0.hasDirectoryPath }) else {
            throw ScriptError.executionFailed("请选择一个文件夹。")
        }
        guard NSWorkspace.shared.setIcon(nil, forFile: folder.path) else {
            throw ScriptError.executionFailed("恢复默认图标失败。")
        }
        return "已恢复默认文件夹图标"
    }

    @MainActor
    static func openWithOtherApp(_ urls: [URL]) throws -> String {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.message = "选择用来打开所选项目的 App"
        panel.prompt = "打开"
        guard panel.runModal() == .OK, let appURL = panel.url else {
            throw ScriptError.executionFailed("已取消。")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
        return "已用 \(appURL.deletingPathExtension().lastPathComponent) 打开"
    }

    // MARK: - 通用小工具

    /// 简单的同步进程调用,成功返回 stdout 文本,失败抛出 ScriptError。
    static func runProcess(
        executableURL: URL,
        arguments: [String]
    ) -> Result<String, ScriptError> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return .failure(.executionFailed(stderr.isEmpty ? "命令执行失败(\(process.terminationStatus))" : stderr))
            }
            return .success(stdout)
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }
    }
}
