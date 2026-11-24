---
name: MiaoRight
description: 轻量原生 macOS Finder 与剪贴板工具
colors:
  primary: "light-dark(#007aff, #0a84ff)"
  control-background: "Field"
  window-background: "Canvas"
  primary-text: "CanvasText"
  secondary-text: "GrayText"
  separator: "light-dark(rgb(0 0 0 / 15%), rgb(255 255 255 / 15%))"
typography:
  title:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "22px"
    fontWeight: 600
  body:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  row-title:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "13px"
    fontWeight: 500
  detail:
    fontFamily: "system-ui, -apple-system, sans-serif"
    fontSize: "12px"
    fontWeight: 400
rounded:
  navigation: "999px"
  application-group: "8px"
  clipboard-focus: "7px"
spacing:
  page: "28px"
  row-vertical: "16px"
  row-gap: "12px"
  title-gap: "7px"
  application-inset: "14px"
components:
  navigation-item:
    textColor: "{colors.primary-text}"
    typography: "{typography.body}"
    rounded: "{rounded.navigation}"
    padding: "9px 14px"
  preference-row:
    textColor: "{colors.primary-text}"
    typography: "{typography.row-title}"
    padding: "16px 0"
  application-group:
    backgroundColor: "{colors.window-background}"
    rounded: "{rounded.application-group}"
    padding: "14px"
  clipboard-row:
    typography: "{typography.body}"
    rounded: "{rounded.clipboard-focus}"
    padding: "12px 10px"
---

# Design System: MiaoRight

## Overview

**Creative North Star: "轻量原生工具"**

妙右采用轻量原生 macOS 工具的视觉语言。Finder 右键与剪贴板是日常入口，主窗口承担低频偏好设置；用系统字体、语义颜色、短列表与必要分隔线建立秩序。

系统蓝只强调选择与操作，图标以单色 SF Symbols 为主。本机 App 使用 NSWorkspace 提供的真实图标。妙右自身使用蓝底白色菜单与光标的原创矢量图标，由代码自动导出 PNG / ICNS。外观可选跟随系统、浅色或深色，三种模式均使用原生毛玻璃，错误和待处理状态同时给出文字说明。

**Key Characteristics:**

- 顶部居中四页胶囊导航，设置按行呈现。
- 原生控件、单一蓝色强调、浅深色语义颜色。
- 更多能力按需添加，历史配置保留。

## Colors

### Primary

系统蓝用于开关、剪贴板焦点和主要操作。原生来源是 SwiftUI `Color.blue`；剪贴板焦点背景浅色使用 0.14、深色使用 0.26 不透明度，并增加 1 点蓝色边框、左侧标记和“已选中”文字，避免只靠底色区分。顶部胶囊选中项使用系统正文色与控件背景，未选中项使用次要文字色。

### Neutral

主窗口和剪贴板面板共用原生毛玻璃背景，控件表面使用 `NSColor.controlBackgroundColor`；减少透明度或增加对比度时回退到 `NSColor.windowBackgroundColor`；正文和说明使用 `.primary` / `.secondary`（对应系统 labelColor / secondaryLabelColor）；分隔采用 `Divider` 与系统 separatorColor。连接成功、警告、失败分别使用系统绿、橙、红，同时保留状态文字。

前置 YAML 是供网页设计面板渲染的语义桥接值，CSS 的 Field、Canvas、CanvasText、GrayText 与 light-dark 不替代原生动态颜色。具体 macOS 颜色以实现中的系统 API 为准；侧车记录对应来源。色阶仅供面板预览，不是新增的 App 调色板。

## Typography

使用系统字体；中文由系统回退。页面标题采用 title，普通内容采用 body，设置行标题采用 row-title，次要说明采用 detail。剪贴板来源、时间和状态等辅助信息为 11 点，正文摘要为 13 点。不得将长说明截断为不可理解的标签；说明可以换行，内容区允许滚动。

YAML 为跨工具表达使用 px；原生实现中所有尺寸单位为 point，并不将像素值直接写回 SwiftUI。

## Layout

主窗口初始内容尺寸 780 × 600 点，最小 680 × 540 点。顶部栏高 64 点，胶囊导航水平居中，不设侧栏。标题栏透明并采用 fullSizeContentView，左侧留给系统窗口按钮，右侧保留扩展连接状态。页面内边距、行间距和标题层级使用前置 token；右键菜单页内容最大宽度 640 点，滚动承载展开内容。

胶囊固定为「右键菜单 / 剪贴板 / 保险箱 / 通用」。36 点 App 图标、妙右名称与版本置于通用页底部。右键菜单首屏有复制文件路径、用应用打开、在终端打开、剪切与粘贴四行，其他已添加功能默认折叠。应用选择、添加功能与结果反馈均在当前主窗口内完成，系统文件选择器与菜单预览 popover 使用原生呈现。

剪贴板固定宽 320 点，停靠呼出时鼠标所在屏幕的 visibleFrame 右缘。面板窗口位置固定，内部内容在裁剪容器内滑动，避免动画泄漏到相邻屏幕。没有网页断点或移动端布局。

## Elevation & Depth

主窗口使用 NSHostingView 下方的原生 `WindowFrostedBackdrop` 兄弟视图，剪贴板在滑动裁剪容器内使用 `FrostedWindowBackground`。两者采用 `underWindowBackground` 材质、behindWindow 混合与 active 状态；模糊层 alpha 固定为 1，不能将其视为“背景透明度百分比”。厚实程度由独立原生底色控制，浅色白色 0.60、深色黑色 0.50，保留模糊层本身。主窗继承当前窗口外观，面板显式选择 vibrantLight / vibrantDark。减少透明度或增加对比度时使用实色回退。留白与分隔线组织内容，不加玻璃光晕。胶囊选中表面使用黑色 0.10、半径 2 点、向下 1 点的轻阴影。Finder 菜单、系统选择器与 popover 继承 macOS 层级。剪贴板稳定展示时使用系统窗口阴影，滑动期间临时关闭阴影。

## Shapes

顶部导航容器与选中表面为 Capsule；YAML 的 999px 是跨工具展示胶囊的桥接值，原生不设固定圆角半径。应用选择区、剪贴板焦点行与原生控件使用小圆角。圆角与内距见前置 token。设置行不包裹成等大卡片，也不增加彩色图标底板。

## Components

- **PreferenceHeader / PreferenceRow**：标题、说明、单色图标在左，控件在右；用原生小尺寸开关、选择器和按钮。图标栏宽 20 点，图标约 15 点。
- **折叠入口**：PreferenceDisclosureStyle 沿用设置行的图标栏、13 点标题与 12 点说明，箭头置右。入口全宽、至少 60 点高，标题与空白均可切换；展开内容缩进 32 点，收起行以细分隔线组织，悬停使用轻微语义底色，辅助功能保留展开状态。
- **导航**：文字与 SF Symbol 成组，12 点字，选中 semibold、未选中 medium；每项内距水平 14 点、垂直 9 点，项间距 2 点，容器内距 4 点。选中表面为 controlBackgroundColor 的 0.85 不透明度，减少透明度时为实色。选中胶囊使用 response 0.25、dampingFraction 1 的 spring，Reduce Motion 时无动画。右上角轻量呈现扩展状态，未启用时提供内嵌修复入口。
- **外观**：通用页保留跟随系统 / 浅色 / 深色选择，存于 appAppearance；跟随系统对应 NSApp.appearance = nil，浅深色对应 Aqua / DarkAqua，材质同步当前主题。
- **程序图标**：Packaging/Icons/GenerateIcons.swift 是菜单与光标的原创矢量源；scripts/generate-icons.sh 导出 AppIcon / FinderIcon PNG、完整十项 iconset 和 ICNS（16–1024 像素），以及透明黑色菜单栏模板（18 / 36 像素，isTemplate）。build-app.sh 每次生成并复制到相应 bundle，plist 声明图标文件。图标资产中的蓝色渐变不扩展成设置页面的背景语言。
- **应用选择区**：从本机选 App 或拖入，图标由 NSWorkspace 读取，列表保留失效应用的文字提示；不使用虚构的已安装状态。
- **添加功能**：默认列出全部附加内置功能，按压缩与解压、新建与整理、复制与分享、图片与 PDF、开发工具、其他工具分段。顶部搜索和分类筛选固定，下方列表独立滚动；条目包含名称、说明和添加按钮，已添加项显示勾选状态。核心常用设置指向上一页，历史自建配置保留，不提供新建编排主入口。
- **菜单预览**：popover 按文件或文件夹示例展示，与 Finder 共用 QuickMenuPlan 分组与顺序；固定核心操作之后是更多操作，不能按使用频率跳位。
- **剪贴板记录行**：摘要优先，来源与时间次级；焦点背景、描边、左侧标记和文字与多选复选框分别表达键盘定位与勾选。前十条快捷数字以 22×20 点、4 点圆角的紧凑键帽呈现，避免混入时间信息。每次展开定位第一条可见记录并清空上次多选，保留筛选条件。搜索编辑时输入法拥有按键，回到列表恢复键盘复用。
- **剪贴板搜索与导出**在同一个搜索框匹配普通记录与图片文字。每条记录的「…」菜单提供「保存…」，文字和图片使用系统保存面板，文件和文件夹使用系统目录选择器。倒数第二条的快捷键在剪贴板设置中单独配置。
- **剪贴板动效**：滑入 0.28 秒 easeOut，滑出 0.22 秒 easeIn；系统 Reduce Motion 开启时均为 0 秒。自动收起与固定模式保持各自行为。
- **常用文件操作**：四个核心行后追加默认折叠的常用文件夹与文件模板管理行，复用 PreferenceDisclosureStyle。每个目录可独立选择打开、复制到、移动到；模板从本机选择并保存快照。失效路径显示文字提示，不新增导航页。
- **压缩与批量重命名**：在主窗口内容区内嵌任务表单。压缩展示格式、可选密码与保存位置；重命名并列原名和新名，逐行标注冲突，未满足条件时禁用确认按钮。处理时禁用切页与重复执行。
- **软件更新**：在「通用」页沿用两种 `PreferenceRow`，分别呈现手动检查与默认开启的每日自动检查。发现新版本后展开版本名、发行日期、说明和与当前架构匹配的安装包大小。生产签名版本位于 `/Applications/MiaoRight.app` 时显示「下载、安装并重新启动」和「选择已下载的 ZIP…」，下载与校验阶段使用小型进度指示；开发版本保留浏览器下载并说明不能自动覆盖。底部使用 11 点次要文字说明校验、退出与重新启动流程，更新结果跨启动保留，不使用独立更新窗口。
- **首次使用检查**：当安装位置、Finder 扩展或剪贴板历史未就绪时，在「通用」页标题下方显示一张控制系统背景色的圆角卡片，用 13 点标题、11 点说明和系统小按钮列出缺失项。卡片显示“已完成 n / 3”，不把可选的辅助功能权限计入完成度；三项完成后自动消失。
- **压缩包目录**由 Quick Look 预览扩展显示在访达的系统快速预览中。只读视图使用带层级缩进的目录树，展示可用的大小与修改日期、统计和部分目录提示。App 内没有压缩包预览入口或快捷键。
- **收藏与结果**：剪贴板搜索下方使用“全部 / 收藏”分段选择器，记录行显示星标，右键/更多菜单切换收藏。剪贴板设置提供默认折叠的常用文字输入。结果使用内嵌内容与“打开所在位置 / 撤销”操作，菜单栏也提供最近结果入口；撤销失败显示原因并保留重试。
- **保险箱**：顶部导航独立页（右键菜单 / 剪贴板 / 保险箱 / 通用）。未创建时显示密码、确认与容量表单并说明密码不可找回；锁定时只显示解锁输入框，不泄露文件名；解锁后顶部为状态与锁定按钮、添加文件主按钮，下方内容列表（名称、大小、时间）与取出、删除，设置行提供自动锁定时长、记住密码与镜像位置；移除保险箱为破坏性行并双重确认。「加入保险箱」仍在主窗口内嵌确认：未创建先建、锁定先解锁，再列出所选项目移入；同名自动改名不覆盖。

侧车 HTML/CSS 是无框架的展示样本，帮助设计面板识别这些原生构件；不是生产 UI，也不替代 AppKit 的焦点、辅助功能和系统控件行为。

## Do's and Don'ts

### Do

- 使用 L10n.text 提供中文与 English，检查英文长度和最小窗口。
- 复用 PreferenceHeader、PreferenceRow 与系统控件。
- 保留输入法编辑优先级、键盘焦点与多选各自的状态。
- 使用系统语义颜色、Reduce Motion 与透明度/对比度回退；本机应用图标从 NSWorkspace 读取，妙右图标从原创矢量源导出。

### Don't

- 不要恢复彩色磁贴墙、功能数量指标或工作流编排主入口。
- 不要以大面积装饰渐变或光晕替代原生材质；浅深主题的遮罩只用于收敛材质与文字对比度。
- 不要将结果展示到独立窗口，或让健康状态占据首屏。
- 不要用隐藏剪贴板面板代替暂停采集，或按频率重排原生菜单。
