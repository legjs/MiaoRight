# 更新日志

本文件记录妙右所有值得说明的变更。

格式遵循 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。English version: [CHANGELOG.md](CHANGELOG.md)。

## [未发布]

## [0.1.2] - 2026-11-25

### 新增

- 新增 Apple 芯片与 Intel 芯片的 DMG 安装包，包含“应用程序”快捷方式和安装说明。
- 新增三步安装引导，并在妙右「通用」页提供首次使用检查清单。
- 新增从匹配 ZIP 或用户选择的 ZIP 安装生产更新的能力。

### 变更

- 生产版本在校验版本、架构、嵌套扩展和发布证书后，原位替换 `/Applications/MiaoRight.app`。
- Finder 扩展检查现在会明确显示已就绪、等待加载和未启用三种状态。
- 开发版本与生产版本使用独立的长期签名身份。
- 首次从开发签名版本切换到生产发布身份时，需要重新确认系统权限和登录项。

### 修复

- 修复设置入口可能打开两个设置窗口的问题。
- 修正 macOS 26 从构建目录启动时 Finder 扩展可能不加载的本地测试流程。

[未发布]: https://github.com/legjs/MiaoRight/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/legjs/MiaoRight/releases/tag/v0.1.2
