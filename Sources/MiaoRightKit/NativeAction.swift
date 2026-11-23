import AppKit
import CryptoKit
import Foundation
import MiaoRightShared

enum NativeAction: String, CaseIterable {
    // 常用功能
    case copyPath = "复制路径"
    case copyFilename = "复制文件名"
    case copyFilenameNoExtension = "复制文件名(不含扩展名)"
    case copyParentPath = "复制所在文件夹路径"
    case copyFileURL = "复制 file:// 链接"
    case copyMarkdownLink = "复制为 Markdown 链接"

    // 新建文件
    case newTextDoc = "新建 TXT 文档"
    case newMarkdownNote = "新建 Markdown 笔记"
    case newRTFDoc = "新建 RTF 文档"
    case newWordDoc = "新建 Word 文档"
    case newExcelWorkbook = "新建 Excel 工作簿"
    case newPPTDeck = "新建 PPT 演示文稿"
    case newFolderHere = "新建文件夹"
    case newFolderFromFilename = "根据文件名新建文件夹"

    // 顶层:剪切/粘贴/发送
    case cutItems = "剪切"
    case pasteItems = "粘贴"
    case moveToFavoriteFolder = "移动到…"
    case copyToFavoriteFolder = "复制到…"
    case airdropShare = "隔空投送…"
    case deletePermanently = "彻底删除"

    // 文件管理
    case createFolderFromSelection = "归类到新文件夹"
    case dissolveFolder = "解散文件夹"
    case flattenFolder = "拍平嵌套文件"
    case organizeByExtension = "按类型整理"
    case organizeByDate = "按日期整理"
    case renameWithSequence = "按序号重命名"
    case lowercaseFilenames = "文件名转小写"
    case replaceSpacesWithUnderscores = "空格替换为下划线"
    case hideItems = "隐藏所选文件"
    case unhideItems = "取消隐藏"
    case sendAliasToDesktop = "发送快捷方式到桌面"
    case removeEmptyFolders = "清除空文件夹"

    // 打开应用
    case openInITerm = "在 iTerm2 中打开"
    case openInWarp = "在 Warp 中打开"
    case openInVSCode = "在 VS Code 中打开"
    case openInCursor = "在 Cursor 中打开"
    case openInSublimeText = "在 Sublime Text 中打开"
    case openInTypora = "在 Typora 中打开"
    case openInObsidian = "在 Obsidian 中打开"
    case openInIDEA = "在 IDEA 中打开"
    case openInPyCharm = "在 PyCharm 中打开"
    case openInCLion = "在 CLion 中打开"
    case openInWebStorm = "在 WebStorm 中打开"
    case openInGoLand = "在 GoLand 中打开"
    case openInDataGrip = "在 DataGrip 中打开"
    case openInAndroidStudio = "在 Android Studio 中打开"
    case openWithOtherApp = "用其他应用打开…"

    // 图片工具(含 OCR / PDF)
    case copyTextFromImage = "复制图片中的文字"
    case saveTextFromImage = "导出图片中的文字"
    case combineImagesIntoPDF = "图片合并为 PDF"
    case splitPDFIntoPages = "PDF 拆分为单页"
    case pdfToImages = "PDF 转图片"
    case convertToPNG = "转换为 PNG"
    case convertToJPEG = "转换为 JPG"
    case convertToICNS = "转换为 ICNS"
    case convertToWebP = "转换为 WebP"
    case resize50 = "缩小到 50%"
    case resizeTo1920 = "缩放到 1920px"
    case createThumbnail256 = "创建缩略图 (256px)"
    case removePhotoInfo = "移除照片隐私信息"
    case rotate90Clockwise = "顺时针旋转 90°"
    case createRetinaCopy = "创建 @2x 副本"
    case getImageDimensions = "查看图片尺寸"
    case heicToJPEG = "HEIC 转 JPG"
    case setDesktopWallpaper = "设为桌面壁纸"
    case setFolderIconFromImage = "用图片设置文件夹图标"
    case exportIconSet = "导出为图标集"

    // 高级功能
    case md5Hash = "MD5 哈希"
    case sha1Hash = "SHA1 哈希"
    case sha256Hash = "SHA256 哈希"
    case sha512Hash = "SHA512 哈希"
    case createSHA256File = "生成 .sha256 校验文件"
    case compressToZIP = "压缩为 ZIP"
    case extractZIPHere = "解压到当前文件夹"
    case createTARGZ = "创建 TAR.GZ"
    case extractTARGZ = "解压 TAR.GZ"
    case compressTo7Z = "压缩为 7Z"
    case extract7Z = "解压 7Z"
    case compressionOptions = "压缩…"
    case extractArchive = "解压"
    case batchRenamePreview = "批量重命名…"
    case addToVault = "加入保险箱"
    case lockFile = "锁定文件"
    case unlockFile = "解锁文件"
    case viewRawData = "查看文件十六进制"
    case forceCloseUsingApps = "强制解除文件占用"
    case generateQRCodeFromPath = "路径转二维码"
    case resetFolderIcon = "恢复默认文件夹图标"

    /// Actions that execute via the native engine (not the shell). Two groups qualify:
    ///   1. Native-only actions with no shell/AppleScript equivalent (OCR, PDF)
    ///      or that are cleaner native (path variants).
    ///   2. Image actions that DO have a sips equivalent but which we run natively
    ///      for non-destructive, consistent behavior (write a new file, never edit
    ///      the original). Their sips `content` is kept only for identity matching.
    /// Everything in the `false` branch still runs via the shell.
    var requiresNativeRuntime: Bool {
        switch self {
        // 继续走 Shell 的动作(内容本身就是脚本)
        case .copyPath, .copyFilename:
            return false
        // 其余全部走原生引擎
        default:
            return true
        }
    }

    init?(script: Script) {
        guard let action = Self(rawValue: script.name),
              let libraryScript = ScriptLibrary.libraryScript(named: script.name),
              script.type == libraryScript.type,
              script.content == libraryScript.content
        else {
            return nil
        }

        self = action
    }
}

enum NativeActionExecutor {
    static func execute(_ action: NativeAction, paths: [String], parameter: String? = nil) throws -> String {
        let urls = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        switch action {
        case .copyPath:
            return try copyPath(urls)
        case .copyFilename:
            return try copyFilename(urls)
        case .copyFilenameNoExtension:
            return try copyFilenameNoExtension(urls)
        case .copyParentPath:
            return try copyParentPath(urls)
        case .copyFileURL:
            return try copyFileURL(urls)
        case .copyMarkdownLink:
            return try copyMarkdownLink(urls)
        case .newTextDoc, .newMarkdownNote, .newRTFDoc, .newWordDoc,
             .newExcelWorkbook, .newPPTDeck, .newFolderHere:
            // 需要命名对话框,由 executeUIAction 在主线程执行
            throw ScriptError.executionFailed("此动作应由 UI 路径执行。")
        case .newFolderFromFilename:
            return try newFolderFromFilename(urls)
        case .cutItems:
            return try cutItems(urls)
        case .pasteItems:
            return try pasteItems(urls)
        case .moveToFavoriteFolder, .copyToFavoriteFolder, .airdropShare:
            // 需要 UI 的动作由 executeUIAction 在主线程执行,不应走到这里
            throw ScriptError.executionFailed("此动作应由 UI 路径执行。")
        case .deletePermanently:
            return try deletePermanently(urls)
        case .createFolderFromSelection:
            return try createFolderFromSelection(urls)
        case .dissolveFolder:
            return try dissolveFolder(urls)
        case .flattenFolder:
            return try flattenFolder(urls)
        case .organizeByExtension:
            return try organizeByExtension(urls)
        case .organizeByDate:
            return try organizeByDate(urls)
        case .renameWithSequence:
            return try renameWithSequence(urls)
        case .lowercaseFilenames:
            return try renameItems(urls) { $0.lowercased() }
        case .replaceSpacesWithUnderscores:
            return try renameItems(urls) { $0.replacingOccurrences(of: " ", with: "_") }
        case .hideItems:
            return try setHiddenFlag(urls, hidden: true)
        case .unhideItems:
            return try setHiddenFlag(urls, hidden: false)
        case .sendAliasToDesktop:
            return try sendAliasToDesktop(urls)
        case .removeEmptyFolders:
            return try removeEmptyFolders(urls)
        case .openInITerm:
            return try openInApp(urls, bundleIDs: ["com.googlecode.iterm2"], appNames: ["iTerm"], displayName: "iTerm2")
        case .openInWarp:
            return try openInApp(urls, bundleIDs: ["dev.warp.Warp-Stable"], appNames: ["Warp"], displayName: "Warp")
        case .openInVSCode:
            return try openInApp(urls, bundleIDs: ["com.microsoft.VSCode"], appNames: ["Visual Studio Code", "Code"], displayName: "VS Code", cliNames: ["code"])
        case .openInCursor:
            return try openInApp(urls, bundleIDs: ["com.todesktop.230313mzl4w4u92"], appNames: ["Cursor"], displayName: "Cursor", cliNames: ["cursor"])
        case .openInSublimeText:
            return try openInApp(urls, bundleIDs: ["com.sublimetext.4", "com.sublimetext.3"], appNames: ["Sublime Text"], displayName: "Sublime Text")
        case .openInTypora:
            return try openInApp(urls, bundleIDs: ["abnerworks.Typora"], appNames: ["Typora"], displayName: "Typora")
        case .openInObsidian:
            return try openInApp(urls, bundleIDs: ["md.obsidian"], appNames: ["Obsidian"], displayName: "Obsidian")
        case .openInIDEA:
            return try openInApp(urls, bundleIDs: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"], appNames: ["IntelliJ IDEA", "IntelliJ IDEA CE"], displayName: "IntelliJ IDEA")
        case .openInPyCharm:
            return try openInApp(urls, bundleIDs: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"], appNames: ["PyCharm", "PyCharm CE"], displayName: "PyCharm")
        case .openInCLion:
            return try openInApp(urls, bundleIDs: ["com.jetbrains.clion"], appNames: ["CLion"], displayName: "CLion")
        case .openInWebStorm:
            return try openInApp(urls, bundleIDs: ["com.jetbrains.webstorm"], appNames: ["WebStorm"], displayName: "WebStorm")
        case .openInGoLand:
            return try openInApp(urls, bundleIDs: ["com.jetbrains.goland"], appNames: ["GoLand"], displayName: "GoLand")
        case .openInDataGrip:
            return try openInApp(urls, bundleIDs: ["com.jetbrains.datagrip"], appNames: ["DataGrip"], displayName: "DataGrip")
        case .openInAndroidStudio:
            return try openInApp(urls, bundleIDs: ["com.google.android.studio"], appNames: ["Android Studio"], displayName: "Android Studio")
        case .openWithOtherApp, .resetFolderIcon:
            // 需要 UI / 主线程,由 executeUIAction 处理
            throw ScriptError.executionFailed("此动作应由 UI 路径执行。")
        case .copyTextFromImage:
            return try copyTextFromImage(urls)
        case .saveTextFromImage:
            return try saveTextFromImage(urls)
        case .combineImagesIntoPDF:
            return try combineImagesIntoPDF(urls)
        case .splitPDFIntoPages:
            return try splitPDFIntoPages(urls)
        case .pdfToImages:
            return try pdfToImages(urls)
        case .convertToPNG:
            return try convertImages(urls, to: .png)
        case .convertToJPEG:
            return try convertImages(urls, to: .jpeg)
        case .convertToICNS:
            return try convertImages(urls, to: .icns)
        case .convertToWebP:
            return try convertImages(urls, to: .webp)
        case .heicToJPEG:
            return try convertImages(urls, to: .jpeg, sourceExtensions: ["heic"])
        case .resize50:
            return try resizeImages(urls, scale: 0.5, suffix: "_half")
        case .resizeTo1920:
            return try resizeImages(urls, maxWidth: 1920, suffix: "_1920")
        case .createThumbnail256:
            return try createThumbnails(urls, maxDimension: 256)
        case .removePhotoInfo:
            return try removePhotoInfo(urls)
        case .rotate90Clockwise:
            return try rotateImagesClockwise(urls)
        case .createRetinaCopy:
            return try createRetinaCopies(urls)
        case .getImageDimensions:
            return try getImageDimensions(urls)
        case .setDesktopWallpaper, .setFolderIconFromImage:
            // 需要 UI 的动作由 executeUIAction 在主线程执行,不应走到这里
            throw ScriptError.executionFailed("此动作应由 UI 路径执行。")
        case .exportIconSet:
            return try exportIconSet(urls)
        case .md5Hash:
            return try hashFile(urls, algorithm: .md5)
        case .sha1Hash:
            return try hashFile(urls, algorithm: .sha1)
        case .sha256Hash:
            return try hashFile(urls, algorithm: .sha256)
        case .sha512Hash:
            return try hashFile(urls, algorithm: .sha512)
        case .createSHA256File:
            return try createSHA256File(urls)
        case .compressToZIP:
            return try compressToZIP(urls)
        case .extractZIPHere:
            return try extractZIPHere(urls)
        case .createTARGZ:
            return try createTARGZ(urls)
        case .extractTARGZ:
            return try extractTARGZ(urls)
        case .compressTo7Z:
            return try compressTo7Z(urls)
        case .extract7Z:
            return try extract7Z(urls)
        case .extractArchive:
            return try extractAnyArchive(urls)
        case .compressionOptions, .batchRenamePreview, .addToVault:
            throw ScriptError.executionFailed(L10n.text("请从 Finder 菜单打开此操作，并在预览页面确认执行。", "Open this action from Finder and confirm it in the preview page."))
        case .lockFile:
            return try setLockedFlag(urls, locked: true)
        case .unlockFile:
            return try setLockedFlag(urls, locked: false)
        case .viewRawData:
            return try viewRawData(urls)
        case .forceCloseUsingApps:
            return try forceCloseUsingApps(urls)
        case .generateQRCodeFromPath:
            return try generateQRCodeFromPath(urls)
        }
    }

    private static func copyPath(_ urls: [URL]) throws -> String {
        let paths = urls.map(\.path)
        try copyToPasteboard(paths.joined(separator: "\n"))
        return paths.joined(separator: "\n")
    }

    private static func copyFilename(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("No item selected.")
        }

        let filename = url.lastPathComponent
        try copyToPasteboard(filename)
        return filename
    }

    private static func openInTerminal(_ urls: [URL]) throws -> String {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw ScriptError.launchFailed("Terminal.app could not be found.")
        }

        let folders = urls.map(parentFolder(for:))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(folders, withApplicationAt: terminalURL, configuration: configuration)
        return "Opened \(folders.count) location(s) in Terminal."
    }

    private static func newTextFile(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("No folder selected.")
        }

        let folderURL = parentFolder(for: url)
        let destinationURL = uniqueDestinationURL(
            in: folderURL,
            preferredName: "Untitled",
            pathExtension: "txt"
        )
        FileManager.default.createFile(atPath: destinationURL.path, contents: Data())
        return destinationURL.lastPathComponent
    }

    private static func deleteDSStoreFiles(_ urls: [URL]) throws -> String {
        var deleted = 0

        for url in urls {
            let root = parentFolder(for: url)
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let itemURL as URL in enumerator where itemURL.lastPathComponent == ".DS_Store" {
                    try FileManager.default.removeItem(at: itemURL)
                    deleted += 1
                }
            }
        }

        return "Deleted \(deleted) .DS_Store file(s)."
    }

    private static func duplicateWithTimestamp(_ urls: [URL]) throws -> String {
        let timestamp = timestampFormatter.string(from: Date())
        var created = 0

        for url in urls {
            let destinationURL = duplicatedItemURL(for: url, timestamp: timestamp)
            try FileManager.default.copyItem(at: url, to: destinationURL)
            created += 1
        }

        return "Created \(created) duplicate item(s)."
    }

    private static func getFileInfo(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("No file selected.")
        }

        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        let permissionString = permissions.map { String($0.intValue, radix: 8) } ?? "unknown"
        let sizeString = values.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "unknown"
        let created = values.creationDate.map(readableDateFormatter.string(from:)) ?? "unknown"
        let modified = values.contentModificationDate.map(readableDateFormatter.string(from:)) ?? "unknown"

        let info = [
            "Name: \(url.lastPathComponent)",
            "Path: \(url.path)",
            "Size: \(sizeString)",
            "Created: \(created)",
            "Modified: \(modified)",
            "Permissions: \(permissionString)"
        ].joined(separator: "\n")

        try copyToPasteboard(info)
        return info
    }

    private static func revealInFinder(_ urls: [URL]) -> String {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        return "Revealed \(urls.count) item(s) in Finder."
    }

    private static func makeExecutable(_ urls: [URL]) throws -> String {
        var updated = 0

        for url in urls {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let existingPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
            let newPermissions = existingPermissions | 0o111
            try FileManager.default.setAttributes([.posixPermissions: newPermissions], ofItemAtPath: url.path)
            updated += 1
        }

        return "Updated permissions for \(updated) item(s)."
    }

    private static func hashFile(_ urls: [URL], algorithm: HashAlgorithm) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("No file selected.")
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let hash: String = switch algorithm {
        case .md5:
            Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha1:
            Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha256:
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .sha512:
            SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        try copyToPasteboard(hash)
        return hash
    }

    private static func createFolderFromSelection(_ urls: [URL]) throws -> String {
        guard let firstURL = urls.first else {
            throw ScriptError.executionFailed("No items selected.")
        }

        let folderName = "New Folder \(folderDateFormatter.string(from: Date()))"
        let parentURL = firstURL.deletingLastPathComponent()
        let destinationFolder = uniqueDestinationURL(in: parentURL, preferredName: folderName)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        for url in urls {
            let destinationURL = uniqueDestinationURL(in: destinationFolder, preferredName: url.deletingPathExtension().lastPathComponent, pathExtension: url.pathExtension)
            try FileManager.default.moveItem(at: url, to: destinationURL)
        }

        return destinationFolder.lastPathComponent
    }

    private static func flattenFolder(_ urls: [URL]) throws -> String {
        guard let folderURL = urls.first else {
            throw ScriptError.executionFailed("No folder selected.")
        }

        let rootURL = folderURL.standardizedFileURL
        let nestedFiles = try collectNestedRegularFiles(in: rootURL)
        var moved = 0

        for fileURL in nestedFiles {
            let destinationURL = uniqueDestinationURL(
                in: rootURL,
                preferredName: fileURL.deletingPathExtension().lastPathComponent,
                pathExtension: fileURL.pathExtension
            )
            try FileManager.default.moveItem(at: fileURL, to: destinationURL)
            moved += 1
        }

        try deleteEmptyDirectories(in: rootURL)
        return "Flattened \(moved) file(s)."
    }

    private static func organizeByExtension(_ urls: [URL]) throws -> String {
        guard let folderURL = urls.first else {
            throw ScriptError.executionFailed("No folder selected.")
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        var moved = 0
        for fileURL in contents where try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true {
            guard try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard !ext.isEmpty else { continue }

            let targetDirectory = folderURL.appendingPathComponent(ext, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueDestinationURL(
                in: targetDirectory,
                preferredName: fileURL.deletingPathExtension().lastPathComponent,
                pathExtension: fileURL.pathExtension
            )
            try FileManager.default.moveItem(at: fileURL, to: destinationURL)
            moved += 1
        }

        return "Organized \(moved) file(s) by extension."
    }

    private static func organizeByDate(_ urls: [URL]) throws -> String {
        guard let folderURL = urls.first else {
            throw ScriptError.executionFailed("No folder selected.")
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        var moved = 0
        for fileURL in contents where try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true {
            guard try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let monthFolder = monthlyFolderFormatter.string(from: values.contentModificationDate ?? Date())
            let targetDirectory = folderURL.appendingPathComponent(monthFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueDestinationURL(
                in: targetDirectory,
                preferredName: fileURL.deletingPathExtension().lastPathComponent,
                pathExtension: fileURL.pathExtension
            )
            try FileManager.default.moveItem(at: fileURL, to: destinationURL)
            moved += 1
        }

        return "Organized \(moved) file(s) by date."
    }

    private static func renameWithSequence(_ urls: [URL]) throws -> String {
        let ordered = urls.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        let moves = ordered.enumerated().map { index, url in
            let stem = String(format: "%03d", index + 1)
            let name = url.pathExtension.isEmpty ? stem : stem + "." + url.pathExtension
            return FileMove(source: url, destination: url.deletingLastPathComponent().appendingPathComponent(name))
        }
        _ = try FileOperationJournal.shared.perform(moves, title: L10n.text("重命名", "Rename"))
        return L10n.text("已重命名 \(moves.count) 项。", "Renamed \(moves.count) items.")
    }

    private static func renameItems(_ urls: [URL], transform: (String) -> String) throws -> String {
        let moves = urls.compactMap { url -> FileMove? in
            let name = transform(url.lastPathComponent)
            guard name != url.lastPathComponent else { return nil }
            return FileMove(source: url, destination: url.deletingLastPathComponent().appendingPathComponent(name))
        }
        _ = try FileOperationJournal.shared.perform(moves, title: L10n.text("重命名", "Rename"))
        return L10n.text("已重命名 \(moves.count) 项。", "Renamed \(moves.count) items.")
    }

    // MARK: - Copy path variants

    private static func copyFileURL(_ urls: [URL]) throws -> String {
        guard !urls.isEmpty else {
            throw ScriptError.executionFailed("No item selected.")
        }
        let value = urls.map(\.absoluteString).joined(separator: "\n")
        try copyToPasteboard(value)
        return value
    }

    private static func copyFilenameNoExtension(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("No item selected.")
        }
        let value = url.deletingPathExtension().lastPathComponent
        try copyToPasteboard(value)
        return value
    }

    private static func copyParentPath(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("No item selected.")
        }
        let value = url.deletingLastPathComponent().path
        try copyToPasteboard(value)
        return value
    }

    private static func copyMarkdownLink(_ urls: [URL]) throws -> String {
        guard let url = urls.first else {
            throw ScriptError.executionFailed("No item selected.")
        }
        let value = "[\(url.lastPathComponent)](\(url.absoluteString))"
        try copyToPasteboard(value)
        return value
    }

    static func copyToPasteboard(_ string: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(string, forType: .string) else {
            throw ScriptError.executionFailed("Failed to write to the clipboard.")
        }
    }

    static func parentFolder(for url: URL) -> URL {
        url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    }

    private static func duplicatedItemURL(for url: URL, timestamp: String) -> URL {
        let parentURL = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let extensionString = url.pathExtension
        return uniqueDestinationURL(
            in: parentURL,
            preferredName: "\(name)_\(timestamp)",
            pathExtension: extensionString
        )
    }

    static func uniqueDestinationURL(in directory: URL, preferredName: String, pathExtension: String = "") -> URL {
        let sanitizedName = preferredName.isEmpty ? "Untitled" : preferredName
        var candidate = directory.appendingPathComponent(sanitizedName, isDirectory: false)
        if !pathExtension.isEmpty {
            candidate.appendPathExtension(pathExtension)
        }

        guard !FileManager.default.fileExists(atPath: candidate.path) else {
            var counter = 2
            while true {
                let suffixedName = "\(sanitizedName)-\(counter)"
                candidate = directory.appendingPathComponent(suffixedName, isDirectory: false)
                if !pathExtension.isEmpty {
                    candidate.appendPathExtension(pathExtension)
                }
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
                counter += 1
            }
        }

        return candidate
    }

    private static func collectNestedRegularFiles(in rootURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let itemURL as URL in enumerator {
            guard itemURL.deletingLastPathComponent() != rootURL else { continue }
            let values = try itemURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(itemURL)
            }
        }

        return files
    }

    private static func deleteEmptyDirectories(in rootURL: URL) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let directories = enumerator.compactMap { $0 as? URL }
            .sorted { $0.path.count > $1.path.count }

        for directoryURL in directories where directoryURL != rootURL {
            let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [])
            if contents.isEmpty {
                try FileManager.default.removeItem(at: directoryURL)
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private static let folderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static let monthlyFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let readableDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private enum HashAlgorithm {
        case md5
        case sha1
        case sha256
        case sha512
    }
}
