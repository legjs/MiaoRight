# AGENTS.md · 妙右 (MiaoRight)

> 本文件供 AI 编码代理(Agent)阅读,建立项目上下文。请勿删除。

## 项目是什么

「妙右」是轻量的 macOS Finder 与剪贴板增强工具，支持 Apple 芯片和 Intel 芯片的 Mac，最低版本为 macOS 14。核心能力为复制路径、用本机应用打开、终端、文件剪切粘贴与剪贴板历史；原有 100 个内置动作保留，按需搜索添加。

- **面向用户**:普通 Mac 用户的日常文件事务，主窗口承担低频偏好设置；其他需求通过添加功能满足
- **核心交互**:稳定顺序的 Finder 右键菜单 + 全局剪贴板列表；主窗口仅「右键菜单 / 剪贴板 / 保险箱 / 通用」四个顶部胶囊导航，右键页四个核心设置行，其他已添加功能默认折叠。已有自建配置保留，无新建编排主入口
- **设计契约**:见 `PRODUCT.md`、`DESIGN.md` 与 `.impeccable/design.json`；使用系统语义颜色、系统字体与单一蓝色强调。默认窗口 780×600、最小 680×540，64 点顶部栏，无侧栏。外观可选跟随系统/浅色/深色，原生毛玻璃遵循减少透明度与增加对比度；原创菜单+光标图标由 Packaging/Icons/GenerateIcons.swift 自动生成，品牌信息置于通用页底部。不要恢复彩色磁贴工作台或节点画布作为主入口
- **双语**:全部文案走 `L10n.text(中文, English)`,支持跟随系统/中文/English 即时切换

> 本项目仅供个人学习与本地使用，不得分发。保留 `LICENSE` 中的许可证与必要声明。

## 构建(无需完整 Xcode,CLT 即可)

```bash
swift build -c release          # 编译
./scripts/build-app.sh release  # 组装 build/MiaoRight.app 并签名
./scripts/dev.sh release        # 退出旧实例、重新构建并更新 /Applications/MiaoRight.app
open build/MiaoRight.app        # ⚠️ 必须用 open 启动,直接执行二进制会绕过 LaunchServices
```

- 构建产物为 `build/MiaoRight.app`，包含主程序、`MiaoRightFinder.appex`、`MiaoRightArchivePreview.appex` 与独立签名的 7-Zip 工具。
- 发布工作流同时生成 DMG 和 ZIP。DMG 用于首次手动安装，包含 `MiaoRight.app`、`Applications` 快捷方式和安装说明；ZIP 仅用于应用内原位更新。`scripts/package-dmg.sh` 负责生成、挂载并校验 DMG。
- macOS 26 从构建目录启动时可能登记 Finder Sync 扩展但不加载进程。本地测试由 `scripts/dev.sh` 将开发签名包更新到 `/Applications/MiaoRight.app`，重新注册扩展后再通过 `open` 启动。可用 `MIAORIGHT_DEV_APP_PATH` 改到其他可受信的应用目录。
- 构建默认使用本机架构。可通过 `MIAORIGHT_BUILD_ARCH=arm64` 或 `MIAORIGHT_BUILD_ARCH=x86_64` 指定目标。推送版本标签后，私有仓库的发布工作流在两种原生架构的运行器上分别构建、测试并打包。操作见 [GitHub 发布和更新检查](docs/GitHub-更新发布.md)。
- `swift test` 需要 Xcode 的 XCTest,CLT 环境不可用

### 签名(稳定开发身份)

本机钥匙串中有两张长期有效的自签代码签名证书。**「MiaoRight dev」**用于本地开发，构建脚本默认检测并使用它；**「MiaoRight Release」**只用于 GitHub 发布，通过 Actions Secrets 导入 CI 临时钥匙串。两张证书和 Bundle ID 都必须保持稳定;
签名指定 `--identifier com.miaoright.app`,DR 为「证书哈希」,**跨重建稳定**,
因此 TCC 授权(如 App Group 访问)一次授权永久有效,不会因重编译反复弹窗。

- 证书丢失/换机:按 `MACOS_DEV_SIGNING.md` 第 1-2 步重建并信任(需用户级 codeSign 信任)
- 证书不在时脚本自动回退 ad-hoc(每次重建需重新授权,不推荐)
- 发布工作流通过 `MIAORIGHT_SIGNING_P12` 与 `MIAORIGHT_SIGNING_P12_PASSWORD` 导入独立的 `MiaoRight Release` 证书，并设置 `MIAORIGHT_SIGNING_IDENTITY=MiaoRight Release` 与 `MIAORIGHT_REQUIRE_STABLE_SIGNING=1`。缺少 Secret 或找不到证书时构建失败，不得发布 ad-hoc 包
- TCC 授权连续性与 Gatekeeper 公证是两件事。稳定自签证书可以在没有 Apple 开发者账号时让后续更新沿用授权，但首次安装仍需手动允许打开。不要用 ad-hoc 发布需要辅助功能、输入监控或 Finder/Quick Look 扩展的版本
- 证书私钥只在登录钥匙串和加密备份中。不得导出整个登录钥匙串，不得把 `.p12`、Base64、密码或 Secret 打印到日志。证书轮换会让所有已安装版本重新授权，仅在证书丢失或泄露时执行。验证方法见 `MACOS_DEV_SIGNING.md`
- 私钥只在本机钥匙串,绝不入库

## 架构（SwiftPM）

| 模块 | 职责 |
|---|---|
| `MiaoRightShared` | 主 App 与扩展共享:AppGroup、场景分类、动作名/emoji 映射、双语 L10n、常用数据存储、工作流模型 |
| `MiaoRightKit` | 业务层:动作库(104 个内置动作)、原生执行器、工作流引擎、全部 SwiftUI 界面 |
| `MiaoRightKit/Composer` | 原子能力层(阶段1基建):`AtomRegistry` 注册约 30 个原子积木,`PipelineEngine` 解释执行组合动作(步骤串联、产物传递、破坏性自动确认) |
| `MiaoRightApp` | 主程序入口(@main),仅做装配 |
| `MiaoRightFinder` | Finder Sync 扩展:右键菜单渲染、执行请求写入。**入口必须走 `main.swift` 的 NSExtensionMain**(SPM 构建的关键,勿删) |
| `MiaoRightArchivePreview` | Quick Look 预览扩展，在访达快速预览与右侧预览面板显示只读目录树、文件大小、修改时间和摘要。没有 App 内压缩包预览入口或专用快捷键。SPM 入口同样使用 `NSExtensionMain`。 |
| `MiaoRightArchivePreviewKit` / `CArchive` | 使用系统 libarchive 读取压缩包目录，返回有条目和时间限制的预览数据。 |

## 关键机制

- **动作即数据**:内置动作定义在 `MiaoRightKit/DefaultScripts.swift` + `ScriptCatalog.swift`(name 为唯一键,中文)。执行器按动作名分发:`NativeAction`(原生 Swift 实现)优先,脚本类动作回退 shell
- **压缩解压**:ZIP、7Z、TAR.GZ、旧组合动作与新建 Excel/PPT 的 ZIP 打包统一走 `SevenZipArchive`。官方 arm64 与 x86_64 的 `7zz` 固定在 `ThirdParty/7zip`，构建前校验 SHA-256，按目标架构复制到 `Contents/Helpers` 并单独签名；许可和对应源码随包保留。先写入独立暂存目录，成功后发布；解压统一到旁边的新文件夹，不覆盖旧文件。TAR.GZ 分两步处理 TAR/gzip，ZIP 使用 Deflate；ZIP/7Z 解压密码通过 stdin 传递，不持久化。不得恢复系统 zip/ditto/tar 或依赖用户安装 Homebrew/Python 工具。
- **压缩包预览**由 Quick Look 预览扩展独立读取目录，并显示在 Finder 的系统快速预览中。App 内不提供压缩包预览入口或快捷键。扩展只读，条目太多或读取超时会显示部分内容。目录加密的压缩包通过原有解压入口输入密码。
- **跨进程协作**:扩展把执行请求写入 App Group 的 `pending_execution.json` → 主 App 的 `ScriptExecutor` 监听通知后认领执行;工作流请求带 `workflowId`
- **单实例主窗口**:SwiftUI 只声明一个 `Window(id: "main")`，不要改回可多开的 `WindowGroup`。“打开设置”统一打开同一个主窗口并切到「通用」页；`WindowActionStorage.showMainWindow()` 用 `openingMainWindow` 合并并发开窗请求，避免重复设置窗口。
- **菜单顺序**:Finder 与按需预览共用 `QuickMenuPlan`。核心顺序为复制路径、应用、终端、剪切、粘贴，再到更多操作；不按使用频率重排。`ActionUsage.record()` 仍记录成功执行，不能据此恢复自动置顶或最近使用主页面
- **双语**:界面字符串一律 `L10n.text("中文", "English")`;动作名/描述经 `ActionNames` 映射(数据键为中文);语言偏好存 App Group,扩展构建菜单时读取
- **工作流兼容**:`WorkflowStore` 保留旧工作流数据模型，`WorkflowMigrator` 将已有 workflows.json 迁移为组合动作，执行统一走 `PipelineEngine`。当前主窗口没有新建编排入口；不得因隐藏入口而清空用户配置
- **应用管理**:从本机选择或拖入 App；图标由 `NSWorkspace` 获取，已保存但丢失的目标显示提示。终端仅列本机可用目标和需要修复的已启用目标
- **首次使用检查**：`SettingsView` 在「通用」页顶部显示“开始使用妙右”卡片，只列尚未完成的安装位置、Finder 扩展和剪贴板历史三项，每项提供直接操作按钮。辅助功能授权作为可选行展示，不计入三项完成度。三项完成后卡片自动隐藏，不新增导航页或独立向导窗口。
- **剪贴板**:暂停采集与隐藏面板是不同操作。320 点面板固定在目标屏幕 visibleFrame 内裁剪滑动，遵循 Reduce Motion；搜索输入法优先，列表定位与多选状态分离。文件移动失败保留未完成状态
- **剪贴板搜索与保存**在本机用 Vision 按需识别已缓存图片的文字。记录菜单统一提供「保存…」，将文字写为 UTF-8 TXT、图片写为 PNG，或复制记录指向的原文件。倒数第二条使用独立可改键的全局快捷键，需要辅助功能授权。临时粘贴完成后恢复原剪贴板内容，期间有新的复制则保留新内容。
- **软件更新**由 `AppUpdateService` 读取 GitHub Releases。默认启动后每 24 小时最多检查一次，可关闭自动检查；手动检查会显示网络、限流和响应错误。发行资产必须按 `MiaoRight-<tag>-<arch>.zip` 精确匹配当前架构，发行页面和下载地址必须属于 `MiaoRightUpdateRepository`。生产版只有在路径为 `/Applications/MiaoRight.app` 且当前签名包含 `MiaoRight Release` 证书指纹时才显示原位安装。安装前必须校验候选 App 的 Bundle ID、发行版本、架构、嵌套扩展和固定证书指纹，然后用后台助手等待主程序退出，备份旧包、原位替换并重新启动。开发签名版本禁止自动覆盖生产包。更新正文统一来自 `docs/release-notes/<tag>.md`，使用中英双语和 Keep a Changelog 分类；App 按当前语言解析并显示分类条目。累计历史同步维护在 `CHANGELOG.md` 与 `CHANGELOG.zh-CN.md`，发布工作流会校验版本条目。匿名检查无法读取私有仓库的发行版。
- **常用文件操作**:目录与模板使用带 `miaorightShortcut` 标记的既有组合动作 JSON，由 `QuickFilePreferences` 管理；目录的打开/复制/移动各自启用，移动执行前确认。模板先保存独立快照。不能把无标记的历史组合动作识别成快捷目录。
- **压缩与重命名**:`压缩…`、`批量重命名…` 先在主窗口内嵌表单，确认后执行；`解压` 自动识别格式及常见分卷。所有压缩解压走内置 7-Zip，密码仅经 stdin，禁止持久化或放入命令行参数。
- **保险箱**:`VaultStore` 管理 hdiutil AES-256 加密 sparse bundle，解锁=挂载到 App Group 容器旁的固定挂载点(`VaultMount`)，锁定=卸载。密码只经 stdin 传给 hdiutil 且不带换行；「记住密码」为可选的登录钥匙串存储，忘记密码不可恢复。右键「加入保险箱」走内嵌确认表单(未创建先建、锁定先解锁后移入)，移入经 `FileOperationJournal` 支持撤销；创建、解锁与内容管理在主窗口独立「保险箱」导航页完成(与剪贴板并列)。空闲(默认 15 分钟)/睡眠/退出自动锁定。扩展凭 App Group 的 `vault.configured` 标记判断菜单可用性；异常退出后卷仍挂着时按已解锁处理。离屏测试禁止执行 hdiutil 命令。
- **收藏与撤销**:剪贴板收藏不受普通历史条数、到期与清理影响。`FileOperationJournal` 记录本次会话最近 20 批移动/重命名，撤销前检查整个批次的文件元数据与原位置，不覆盖冲突文件；结果附输出位置和撤销 ID。
- **离屏测试**:显式设置 `MIAORIGHT_OFFSCREEN_TESTING=1`、`MIAORIGHT_TEST_STORAGE`、`MIAORIGHT_CLIPBOARD_TEST_STORAGE`；隔离默认偏好/存储，禁止发送跨进程刷新、安装热键、采集剪贴板或激活窗口。构建使用 `MIAORIGHT_APP_OUTPUT`、`MIAORIGHT_SWIFT_BUILD_PATH`、`MIAORIGHT_ICON_OUTPUT` 写到临时目录，不能替换正在使用的 App。
- **组合动作(Composer)**:ScriptType `.composed` 的动作,`content` 是 `ComposedAction` JSON(`{version, steps:[{op, params}]}`)。执行走 `PipelineEngine`:第一步吃选中文件,之后逐步传递产物;输出为「空」的旁路步骤(通知等)不改变数据流。**含破坏性原子(移动/删除/重命名)的组合自动要求执行前确认**,不依赖 confirmBeforeRun 字段。新增原子:`AtomRegistry` 加条目(id/中文名/输入输出槽/参数 schema/isDestructive/实现),参数值统一按 String 持久化

## 约定

- 新增动作:先在 `DefaultScripts/ScriptCatalog` 定义(中文名 + 描述),在 `NativeAction` 加同名 case 并接执行分支,在 `ActionNames`/`ActionEmoji` 补双语映射
- 文案禁止硬编码中文,一律 `L10n.text`;动作用户可见名以中文为数据键
- 涉及覆盖/移动/删除的动作必须 `confirmBeforeRun: true`
- 业务详情、添加功能与执行结果统一内嵌主窗口；系统选择器、菜单预览 popover 与剪贴板面板按原生方式呈现
- 新增界面沿用 `PreferenceHeader` / `PreferenceRow`，不让原子能力和编排术语进入普通用户主流程
- 每次 Git 提交的标题和正文都必须使用英文。改完必须运行 `./scripts/build-app.sh release`，构建通过后再提交。
- 默认 README 为英文 `README.md`，简体中文版为 `README.zh-CN.md`。更新功能、限制、使用入口或验证状态时同步维护两份 README。

## 已知边界

- 设置里切语言:窗口内容即时生效;系统级菜单栏(文件/编辑等)由 macOS 渲染,重启 App 后跟随
- 分隔线在 macOS 26 菜单中渲染为整行空白,右键菜单避免使用
- 直接执行二进制(不经 `open`)会导致 AX/窗口注册异常,调试时注意

- 前台系统保存窗口、Finder 与 Quick Look 完整交互、VoiceOver、物理多屏和权限全链路需要单独实测。Release 构建及离屏测试与前台验收分别记录。
