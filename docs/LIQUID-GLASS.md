# 动态 Liquid Glass 与跨端界面目标

[English](LIQUID-GLASS.en.md) | 简体中文

用户于2026-11-04明确：iOS优先，桌面同方向，目标是“iOS 27级别”的动态Liquid Glass质感、动态图标、大画幅图片/漫画/视频、标签和高度可定制界面。此目标描述体验质量，不自动把最低系统从iOS26提高到27。底层先行的顺序保留；首轮材质试点保留现有布局、间距、圆角、字体、图标身份和文案，布局重构另阶段执行。

## 参考与已经核实的能力

- 用户提供[Kubai087](https://x.com/Kubai087)主页及完整材质配方。本轮浏览器因 `APP_BOUND_ENCRYPTION_UNSUPPORTED` 无法使用复制的登录态，未读取其其他推文；以下采用用户提供的文本，不宣称核查了整个主页。
- Apple官方[自定义视图的Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)说明了 `glassEffect`、`.interactive()`、`GlassEffectContainer`、稳定效果ID和变形过渡。`glassEffect`可用性元数据为iOS26起；大量独立效果容器会影响性能。
- 当前MyGo0.7.3已提供MIT的[plugins/glass](https://github.com/egoist/mygo/tree/v0.7.3/plugins/glass)：`Glass{Style,Tint,Interactive,Clarity}`、`ScrollEdge`和渐进背景模糊。它通过渲染器绘制原生界面，不依赖JS或CSS。
- MyGo窗口 `VibrancyGlass/Clear` 在macOS26+使用系统Liquid Glass，Windows11映射到Acrylic；这是窗口级背景，与同窗口内容上的 `Material(glass.Glass{})` 不同，不能混称为同一种视觉结果。

## 表面盘点与首轮处理

| 现有表面与位置 | 首轮材质方向 | 边缘折射/色散与保持项 |
|---|---|---|
| iOS `VideoPlayerView.transport` 播放控制胶囊 | 视频上的系统原生玻璃；不可读背景使用主题和较密材质 | 使用系统边缘，不叠加SVG；保留位置、尺寸、字体和文案 |
| iOS `DesignSystem.PosterTile` 图片角标 | 原生材质适应图片，优先可读 | 小角标不加自定义镜片或RGB色散；不改变封面 |
| iOS `DesignSystem.Pill` 浮动操作 | 延续已有glassEffect，可评估系统交互效果 | 保持现有图标和几何；实色主操作保留语义色 |
| iOS `PromptCenter.PromptPresenter` toast/加载层 | 背景复杂时启用统一较密材质 | 不给短暂/运动面板追加自定义镜片 |
| iOS `RootView`、`ReaderView` 系统导航/菜单 | 使用系统原生材质和无障碍行为 | 不叠一层玻璃；漫画正文保持原始像素 |
| iOS `GlassCard` 及发现/书架/我的内容卡 | 当前实际为纯色卡；平面背景保持现有表面 | 未来置于壁纸/图片上时才按语义选择材质，避免整体灰化 |
| 桌面 `internal/ui/app.go` 工具栏/面板 | 纯色背景保持现有样式；原生图片背景上的浮层优先MyGo Glass | 上游原生折射优先；不复制CSS光学算法 |
| 桌面 `internal/reader/assets/reader.html` 的sticky `#bar` | 统一CSS材质token与明暗设置 | 默认CSS-only；小尺寸/独立合成层跳过SVG镜片；页图不加滤镜 |
| 桌面 `internal/player/assets/player.html` 的 `#bar` 与原生video controls | 当前底栏在视频下方、背景纯色，先保持 | 替换浏览器播放控件属于新组件，先提出独立方案再确认 |
| 源码编辑、长文本、错误与设置表单 | 保留稳定高对比内容面 | 焦点、禁用和错误色保持；错误仍使用语义红色 |

首轮不添加新的自定义控件。如果某个效果必须更换播放器控制条或增加新的组件，先给出具体方案再征求用户确认。系统效果容器只用于合成已有视图，不改变现有布局参数。

## 统一材质token与保存方式

材质进入主题层；组件只选择语义角色，不各自维护透明度和模糊常数。现有iOS `Theme` 只有accent/background/surface/radius/dark；`RootView`通过preferredColorScheme应用明暗，`DesignSystem`映射颜色。新增字段必须向后兼容旧主题。桌面MyGo主题和阅读器CSS token分别作适配，不假定它们已统一。

| 语义配置 | 约束与用途 |
|---|---|
| `material.role` | navigation、mediaOverlay、notification、content；纯内容默认不套玻璃 |
| `light.tintScale` / `dark.tintScale` | 各0…1.5，默认1，按主题ID保存；用户覆盖值与下载的主题文件分开 |
| `glass.style` | regular/clear；视频/未知背景优先保证对比度，不能只追求透明 |
| `glass.clarity` | MyGo可映射0…1；SwiftUI没有同义公开旋钮，不伪装成精确相同的模糊值 |
| `ink.primary/secondary` | 明暗各用固定颜色阶；对比不足先增加材质密度，不降低字的实度 |
| `motion.interaction` | 按下反馈、状态替换、展开合并；减少动态效果时静态或简化 |
| `fallback.solid` | 减少透明度、强制颜色/高对比环境优先于主题装饰设置 |

用户提供的alpha、2px模糊、饱和度、边缘和亮度值作为Web试点的起始值，不作为SwiftUI系统材质或MyGo shader的等价参数承诺。两个tint设置的持久化与主题切换过渡要有实际回归证据，当前尚未接入设置页。

## 背景适应、可读性与动态图标

可读取的本地图片可采用5×3采样、去掉两亮两暗、分组共享明暗决策，以及0.5阈值±0.05迟滞。密度计算须限制到0…1，采样按图片/主题/位置变更触发并缓存，不逐帧在主线程读取视频。直播视频、跨域或不能读取的内容使用主题颜色和较密表面。

配方中的0.299/0.587/0.114亮度用于外观启发，不代替WCAG线性相对亮度。实际合成后的普通文字至少4.5:1，大字和必要图标/控件至少3:1；检查最暗、最繁杂背景，保留焦点环、禁用态和错误色。系统与用户的减少透明度、增加对比度、减少动态效果设置拥有最高优先级。

动态图标用于状态反馈：播放/暂停切换、一次收藏反馈、真实加载状态；保留图标身份与可访问名称，不以无意义的持续循环替代状态。大画幅保证媒体主体清晰，玻璃主要承载浮动控制。布局阶段再加入封面比例/信息密度、模块显隐/排序/尺寸、内容标签/分组和导航页签配置，并保持主题token、布局预设和业务数据分离。

## 跨端边界与实施顺序

1. 底层继续收尾；先完成材质清单和可维护上游选型，不重做旧UI视觉矩阵。
2. 在已有视频控制胶囊、图片角标和阅读器工具栏做小范围材质试点；保留几何，分别测试原生SwiftUI、MyGo和WebView。
3. iOS采用系统容器、交互与变形API；桌面采用已有MyGo Glass。MyGo只能保证已绘入其场景的背景，嵌入WebView/视频的跨合成采样必须单独验证。
4. Web端先CSS-only。SVG位移与RGB色散仅对稳定、足够大的合格表面，在实际渲染确认后启用；CSS.supports解析成功不独立证明显示正确。唯一filter ID、资源解码、缓存和尺寸变化均要处理。
5. 验证明暗最差背景、减少透明度/动态效果、滚动/视频帧率和能耗之后，再推进整体大画幅与可定制布局。

## 本轮证据范围

Apple官方文档与API可用性已取回，文件位于 `E:/Temp/nk-liquid-glass/`。Windows执行MyGo0.7.3的 `go test -count=1 -v ./plugins/glass` 全部通过，包含CPU渲染检查与Direct3D11离屏对照；日志 `mygo-glass-tests.log`。这是上游材质实现证据，不是当前产品界面、Mac/iOS运行、视频合成或性能验收。此次未修改产品SwiftUI布局或主题字段。
