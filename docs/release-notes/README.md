# Release Notes

发布说明使用一份 Markdown 文件同时提供中文和 English，供 GitHub Release 与 App 内更新页共用。累计版本历史写入根目录的 [CHANGELOG.md](../../CHANGELOG.md) 和 [CHANGELOG.zh-CN.md](../../CHANGELOG.zh-CN.md)。

## 文件位置

每次稳定版本发布前创建 `docs/release-notes/<tag>.md`，例如 `v0.1.2.md`。发布工作流读取该文件并直接写入 GitHub Release 正文。

## 格式

- 使用固定的 `## 中文` 和 `## English` 两段。
- 分类遵循 Keep a Changelog，使用 `### 新增` / `### Added`、`### 变更` / `### Changed`、`### 弃用` / `### Deprecated`、`### 移除` / `### Removed`、`### 修复` / `### Fixed`、`### 安全` / `### Security` 中实际存在的项目。
- 每个条目以 `- ` 开头；中文条目使用完整句子，英文条目使用过去式或结果导向描述。
- 不写内部提交术语、变量名、证书指纹或仅供开发使用的实现细节。
- 不在正文重复版本标题，Release 标题由工作流生成。

App 更新页会按当前界面语言提取对应段落，并显示分类标题与项目符号。缺少双语段落时退回显示完整正文。

发布前同时把该版本条目写入中英文累计 changelog。发布工作流会检查两个 changelog 是否包含当前版本，并检查本文件是否存在。
