import Foundation

@_silgen_name("NSExtensionMain")
func NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?) -> Int32

let extensionExitCode = NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv)
exit(extensionExitCode)
