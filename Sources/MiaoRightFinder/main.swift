import Foundation

// Finder 扩展入口。SPM 构建的可执行文件默认生成的空 main 会让扩展启动后立刻退出,
// 因此这里显式调用 Foundation 的 NSExtensionMain:它会读取 .appex Info.plist 中的
// NSExtension 字典并实例化 NSExtensionPrincipalClass(MiaoRightFinder.FinderSync)。
@_silgen_name("NSExtensionMain")
func NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?) -> Int32

let extensionExitCode = NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv)
exit(extensionExitCode)
