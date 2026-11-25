# 更新日志

本文件记录妙右所有值得说明的变更。

格式遵循 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。English version: [CHANGELOG.md](CHANGELOG.md)。

## [未发布]

## [0.1.3] - 2026-11-25

### 新增

- 妙右现已按 MIT License 开源发布。
- 公开的 GitHub Releases 支持无需 GitHub 登录的一键检查更新和原位安装。
- 新增三步安装引导和 App 内首次使用检查清单。

### 变更

- 下载 ZIP 或选择已有 ZIP 后，在校验版本、架构、嵌套扩展和证书后替换 `/Applications/MiaoRight.app`。
- 发布流水线在单个 Apple 芯片 runner 上原生构建 arm64，并交叉构建 x86_64。
- MIT 版权信息现包含 MiaoRight contributors。

### 修复

- 修复深色模式下更新说明文字不可读的问题。
- 改进 Finder 扩展状态反馈，并移除重复创建设置窗口的问题。

### 安全

- 更新包必须由稳定的 MiaoRight Release 身份签名后才能替换 App。

### 变更

- 仓库现已公开，并按 MIT License 发布。
- 公开 Release 支持自动检查更新和无 GitHub 登录的原位安装。

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

[未发布]: https://github.com/legjs/MiaoRight/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/legjs/MiaoRight/releases/tag/v0.1.3
[0.1.2]: https://github.com/legjs/MiaoRight/releases/tag/v0.1.2
