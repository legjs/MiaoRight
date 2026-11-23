import Observation

/// 结果由主窗口内嵌呈现;窗口关闭期间也保留待展示的内容。
@MainActor
@Observable
public final class ActionResultPresentation {
    public static let shared = ActionResultPresentation()
    public var result: ScriptExecutionResult?
    private init() {}
    public func present(_ value: ScriptExecutionResult) { result = value }
}
