# PicSee 动画、Release 与官网下载验证

## 项目与修改边界

- Swift Package，macOS 14+，AppKit 图片画布与 SwiftUI 工具栏/裁剪编辑器，无第三方动画依赖。
- `ImageViewerViewModel` 负责图片、Finder 顺序导航、删除、缩放/旋转目标状态；`CanvasNSView` 负责布局与连续输入。
- 当前通过 `NSImage(contentsOf:)` 同步载入；本次不修改加载、解码、格式支持、Finder 排序、待排序导航请求、删除/恢复与更新器。
- 官网为 `website/` 下零构建步骤静态页面，Cloudflare Pages 输出目录保持 `website`。
- 原 DMG 命名实际为 `PicSee-X.Y.Z.dmg`，不带 `v`；App 内更新器也依赖该名称。因此保留该命名，而不是改成需求示例中的 `PicSee-vX.Y.Z.dmg`。

## Swift 改动

| 文件 | 修改 |
| --- | --- |
| `Sources/PicSee/Viewer/ImageCanvasView.swift` | 显示层缩放/切图动画、旋转接管、系统 Reduce Motion、中断和 SwiftUI 写回时机 |
| `Sources/PicSee/Viewer/ImageViewerViewModel.swift` | 为 Fit/100% 提供动画请求序号；显式前后导航携带方向，原最终目标状态保持不变 |
| `Sources/PicSee/Viewer/ImageViewerView.swift` | 传递动画信息；裁剪编辑器显隐 fade；主工具栏/方向按钮只淡入淡出 |
| `Sources/PicSee/Viewer/ScreenshotEditorView.swift` | 选区形成时标注工具栏 fade，不对选区几何加动画 |
| `Tests/PicSeeTests/ImageCanvasAnimationTests.swift` | 新增动画和连续操作回归测试，含真实窗口 presentation layer 接管 |
| `Tests/PicSeeTests/ImageCanvasOCRTests.swift` | 原旋转测试明确关闭 Reduce Motion，避免依赖运行机器的辅助功能偏好 |

| 动画 | duration / timing | 行为 |
| --- | --- | --- |
| 左右旋转 | 0.22 s / easeInEaseOut | 保留 CABasicAnimation；从 presentation angle 接管，目标等价角选择最短路径；同 key 替换 |
| 工具栏 + / − | 0.18 s / easeInEaseOut | 目标累计、保持原缩放中心；缩放与平移由同一个容器 transform 同步过渡 |
| Fit / 100% / 双击恢复 | 0.20 s / easeOut | 原目标比例/偏移不变；从当前视觉状态过渡；原双击已 Fit 时的全屏行为保持 |
| 上/下一张 | 0.17 s / easeOut | 下一张旧图向左、新图由右进入；上一张反向，位移 18 pt；新图 opacity 0.88→1，旧图退出淡出 |
| Reduce Motion 切图 | 0.12 s / easeOut | 位移为 0，只保留淡入淡出 |
| 裁剪编辑器/标注工具栏显隐 | 0.15 s / easeOut | 仅 opacity；裁剪绘制、拖动、resize 不加动画 |
| 原主工具栏/导航浮动按钮 | 保留 0.18 s / easeInOut | 去掉原 0.92 scale transition，仅 opacity |

缩放单个动画 key 替换，无动画队列。连续按钮点击保留累计目标，从当前视觉状态开始下一段；滚轮、pinch、鼠标按下/拖动、小地图导航会移除缩放动画，先把当前 presentation 对应的 zoom/pan 写回，再直接处理输入。Live Text 子视图接收点击前也会中断，避免选择命中与显示位置错位；Vision 选区随同容器变换。

快速切图时，新图立即替换；若旧切图动画尚未结束，则本次跳过动画并释放旧图。正常切图最多保留一张旧 NSImage 引用，完成或取消即释放，不生成整窗截图，不增加图片解码。

系统设置通过 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` 获取，并监听 `accessibilityDisplayOptionsDidChangeNotification`。开启后取消缩放、旋转和切图位移；设置中途改变也会终止既有动画，保留已提交目标。UI 的 opacity 可以保留。

不新增首图 fade：当前没有异步首显阶段，不延迟首次显示。不新增 OCR Overlay fade：保留 VisionKit 原生识别与选择交互。滚轮、pinch、拖动、裁剪 resize 和标注笔划不插值、不使用高频 Timer。

工具栏命令移至 representable 更新后执行，比例回报也延后并过滤过期值，避免在 SwiftUI 更新过程中同步发布状态；这不是等待动画结束或建立动画队列。

## Release

只修改 `.github/workflows/release.yml`；`Scripts/build-app.sh`、`Scripts/build-dmg.sh`、版本解析、Tag 触发、Release Notes 与更新器均保持原逻辑。

最终流程：Universal 2 → Developer ID 签名（按现有证书配置）→ DMG 构建/签名 → 安装包内容与布局校验 → 公证 → Staple → stapler validate / codesign verify / Gatekeeper 校验 → hdiutil verify → cp 固定名称 → cmp + SHA-256 → artifact / GitHub Release。

两个资产：

- `PicSee-X.Y.Z.dmg`
- `PicSee.dmg`

固定文件只复制最终 DMG；不再次构建、签名、公证或 Staple。复制不一致立即失败。两个路径都上传，Release 设置 `fail_on_unmatched_files: true`。

现有“未配置证书则 ad-hoc 构建并跳过公证”的分支保持不变。正式签名/公证必须由具备现有 secrets 的 GitHub Actions 完成，本地验证不等同于 Apple 公证验证。

## 官网

修改 `website/index.html` 和 `website/README.md`。

导航栏“下载”、首屏“下载 macOS 版”、页脚“下载最新版本”共 3 处：

- 原地址：`https://github.com/houleixx/PicSee/releases/latest`
- 新地址：`https://github.com/houleixx/PicSee/releases/latest/download/PicSee.dmg`

按最新要求，下载和 GitHub 链接统一使用 `target="_blank" rel="noopener"`，在新窗口/标签页打开；下载链接直接访问安装包端点。没有拼接版本号；页面没有新增版本生成逻辑；其他链接、图片资源、样式、脚本、缓存头和 Cloudflare 部署方式不变。没有 Worker、Pages Function 或 GitHub API 查询。全仓库复查没有遗漏官网最新版入口；保留 README/历史设计文档和 App 更新器中的版本链接。

**上线顺序：** 2026-09-11 查询线上 Latest 为 `v0.2.53`，资产只有 `PicSee-0.2.53.dmg`。必须先发布包含 `PicSee.dmg` 的正式 Release，再部署新官网。否则首次部署期间固定 URL 尚无资产。本次未创建 Tag、发布 Release、修改现有 Release 或部署 Cloudflare。

## 验证结果

- 完整 `swift test`：269 项、0 失败，包含 OCR 识别/选择/复制、Finder、删除、裁剪/标注导出与新增动画测试。
- 新增真实窗口测试确认缩放和旋转在动画中途读取 presentation layer 后继续，而非从上次目标跳变。
- Universal 2 Release build：arm64 与 x86_64 均成功，`lipo -info` 确認双架构；编译日志无 Swift warnings/errors。
- 本地 ad-hoc App 和 DMG 构建成功；`Tests/build-dmg-tests.sh`、`Tests/verify-dmg.sh` 通过。
- Actions YAML 解析、所有 run 块 `bash -n`、执行顺序、两个资产路径验证通过。
- 对实际 DMG 执行 workflow 复制步骤，`hdiutil verify`、`cmp`、SHA-256 通过；另用隔离夹具模拟复制损坏，确认步骤非零退出。
- 官网通过本机 HTTP 静态输出验证；3 个 URL 正确，其他链接及所有图片引用与修改前一致，图片资源均存在。无构建步骤。
- 浏览器连接不可用，未执行浏览器内点击；线上安装包端点仍待首个带固定资产的正式 Release。
- 通过本地 PicSee 界面检查缩放按钮、Fit、100%、旋转、滚轮、双击恢复、裁剪框拖动、工具栏显隐与退出，以及隔离目录中的左右/上下连续切图。
- pinch 和中途接管有程序事件/真实渲染测试；工具不支持物理触控板 pinch，也未测量 RAW/HEIC/WebP 大图的帧率或峰值内存，不宣称完成这些硬件性能测试。

本地最终两个 DMG 的 SHA-256 相同：
`9d9f9f37336a820e73d0eadf3cbc0cde3bdb678a276ff9a911f078510d0bb12e`。
这是本地 ad-hoc 验证产物的哈希，不是线上正式公证包的哈希。

## 运行时对照与已知问题

对未修改 HEAD 在 `/private/tmp/picsee-animation-baseline` 单独构建，使用同一隔离图片目录进行相同的缩放和快速切图操作：

- 原版本也出现 `Publishing changes from within view updates`；本次已修正，最终版本的复验日志未再记录此警告。
- 原版本与最终版本都能出现 Live Text / AppKit `Conflicting constraints detected`。
- 原版本与最终版本都能在快速切图时出现 VisionKit “more than 10 requests in the processing queue”。当前 OCR task cancellation 并未完全阻止底层服务排队；这是此次对照确认的既有问题，按最小修改原则保留原 OCR 流程，未借动画任务重构识别调度。
- 未发现动画队列、旧图残留或最终 zoom/pan/rotation 状态回归；尚未做硬件性能基准，不能把构建/测试通过等同于所有大图场景均完成性能验证。

最终验证日志保存在本地 `build/verification/`（忽略的构建产物目录）。

## 本地安装后工具栏无动画：定位与修复

用户反馈工具栏放大/缩小没有动画。检查发现两份安装：`~/Applications/PicSee.app` 已更新，但 `NSWorkspace` 对 PNG 和 `local.picsee.viewer` 实际均选择 `/Applications/PicSee.app`，该位置仍是不同二进制的旧版；Reduce Motion 为关闭状态。启动路径断言连续失败，明确复现了安装位置不一致。

已将 `/Applications/PicSee.app` 同步为已验证的新构建，并备份移走合并安装遗留的旧图标资源，确保整个 bundle 与构建产物完全相同、签名验证通过。两处安装及 build 中的可执行文件 SHA-256 均为 `3cd482a562057c89503d599580502ac755c7f14ea44a2315ef5cecbc6db33947`。通过系统默认方式打开仓库测试 PNG 后，确认进程实际运行于更新后的 `/Applications/PicSee.app`；启动路径断言通过。

新增真实 NSHostingView / NSApplication 鼠标事件测试，点击工具栏后断言 55 ms 时缩放仍处于起点与目标之间，覆盖 SwiftUI 更新后的实际动画存续。完整测试增至 270 项、0 失败；本次没有修改动画实现或 duration。

以后本地安装不能只校验复制目标，还需要校验 LaunchServices 实际选择的打开路径。此前临时基线 App 已注销，防止测试安装参与应用选择。


## 单次缩放柔和度调整

用户确认主要感受是单次点击“太急或生硬”。工具栏 + / − 改为 0.18 秒 easeInEaseOut，起步与收尾速度均平缓；Fit/100%/双击仍为 0.20 秒 easeOut，连续手势保持无补间。

另外修复同一渲染帧内连续接管的起点跳变：之前将旧 presentation transform 与已更新的 model zoom/pan 相乘，会计算出错误的当前画面。现在尺寸、位置、变换都从同一 presentation 帧取得。新增回归测试在修改前稳定失败（约 2.24→2.79 的错误起点），修复后通过。完整测试 271 项、0 失败。

本轮更新本地 Universal 2 App；上文 DMG 哈希保留为此前发布流程验证记录。

柔和度调整版已安装至 `/Applications/PicSee.app` 和 `~/Applications/PicSee.app`，签名、双架构和整个 bundle 一致性检查通过；两处可执行文件与新 build 的 SHA-256 均为 `34aca6c631eaae239a05ad58a2a64a9421509bec42a52649b3aae5749f4b08e8`。已按系统默认方式重新打开用户刚才查看的仓库图片。

## 连续工具栏点击误中断修复

连续真实点击复现了另一个问题：SwiftUI 路由工具栏鼠标按下事件时也会调用底层 Canvas 的 `hitTest`。原实现在那里调用 `interruptMotion()`，误把工具栏点击当成图片直接交互，将尚未到达的目标重置为当前呈现比例。4 次放大的目标本应为 2.44140625，复现中仅约 1.36，造成停顿与目标丢失。

修复为让 `hitTest` 只做命中判断、不修改图片状态。Canvas 实际 `mouseDown` 仍立即中断；Live Text 改为在 `ImageAnalysisOverlayViewDelegate.overlayView(_:shouldBeginAt:forAnalysisType:)` 开始交互回调中中断，并返回 true 保留原交互。保持工具栏 0.18 秒 easeInEaseOut，不通过延长动画掩盖问题。

真实 NSApplication 事件回归覆盖连续放大、连续缩小与交替点击，检查累计目标、方向单调性及每段显示比例范围；新增 Live Text 开始选择时取消缩放且保留识别结果的测试。修复前的真实連点测试稳定失败，修复后完整 272 项测试通过。此前测试仅覆盖单次真实点击和命令层连点，没有覆盖连续真实鼠标事件，这是遗漏此次问题的原因。

本地安装策略已统一为 `/Applications/PicSee.app`；用户目录中的旧副本已移到废纸篓，不再重新创建。

连点修复版已重新安装到 `/Applications/PicSee.app`，签名和完整 bundle 比对通过。安装文件与 build 的 SHA-256 同为 `880ecde6c23a73e49f61ea0e6ac3714c61e6ef66cd10f3c406d4e1c6e16b5dd1`；用户目录副本保持不存在。旧实例退出后，已通过系统默认打开方式启动新实例。

## 连续缩放的速度接续

用户继续反馈连点有轻微抖动感。此前回归覆盖了位置连续与目标累计，却没有覆盖速度连续。新增真实窗口测试 `testRepeatedZoomPreservesSpeedAtTakeover`：先让动画实际显示约 60 ms，再发出第二次缩放请求，比较接管前后的曲线速度。修改前放大速度从约 3.89 突然归零，缩小从约 -3.11 归零，测试两处失败，证实 easeInEaseOut 每次重启会带来反复刹停再起步。

工具栏仍为 0.18 秒：单次点击保留 easeInEaseOut；同方向接管根据当前 presentation 比例与上一条曲线求出速度，为替换 CABasicAnimation 设置匹配初始斜率、平缓收尾的三次贝塞尔曲线。控制点限制在有序的 0...1 范围，避免越过目标。反向目标不沿用背离目标的速度。每次点击只做一次曲线计算，逐帧渲染仍完全由 Core Animation 完成；仍只保留一个缩放动画，不使用 Timer，也不引入 spring 或第三方库。

新增回归同时覆盖放大、缩小、同一帧内再次接管、反向目标与动画不排队。完整 `swift test`：273 项、0 失败，无编译 warnings/errors；现有真实 SwiftUI 连点、滚轮、pinch、拖动、旋转、Reduce Motion 与 OCR 回归保持通过。该测试证实速度断点已消除，不等同于所有图片格式与硬件的帧率测试。

本轮 Universal 2 构建通过，两架构编译无 warnings/errors。已只安装到 `/Applications/PicSee.app`，签名验证及完整 bundle 比对通过；用户目录副本保持不存在。构建与安装可执行文件 SHA-256 同为 `92b30c71805521d18abd25aa4ce1d9c8c330626959fe557dc4279466ef888526`。旧进程退出后，重新打开用户刚查看的仓库图片。红灯、动画回归、完整测试和构建日志保存在 `build/verification/picsee-velocity-*.log`。

## 左右切图节奏优化

连续切图回归在修改前出现 6 处失败：只通过“当前是否有动画”判断快切，会在取消动画后于下一次请求重新播放，导致动画与直接切换交替出现。新增每次方向切图的单调时钟记录，相邻间隔小于 0.22 秒时持续直接切换，包括反向；每次请求都更新时间，停顿后恢复动画。仅按请求计算，不使用轮询或计时器，不延迟新图显示。

单次切图调整为 14 点方向位移、0.16 秒 easeOut，新图透明度 0.94→1；旧图在 0.10 秒内退出并淡出，减少叠影。旧图 model opacity 明确保持为 0，避免等待异步清理时重现。Reduce Motion 保留 0.12 秒新图淡入、0.10 秒旧图淡出，无位移。非方向切图重置连按时间记录，保留打开图片及删除等原有状态流程；未改变同步加载、Finder 顺序、zoom/pan/rotation 重置或 OCR 调度。

新增连续同向/反向切图和停顿恢复/旧图清理等待期间不可见的回归测试。完整 `swift test`：275 项、0 失败，编译日志无 warnings/errors。日志为 `build/verification/picsee-navigation-*.log`。

本轮构建期间工作区另有工具栏/标注 UI 更新，首次构建因输入文件变化中止。保留这些更新，并将原真实缩放鼠标测试的固定横坐标改为使用 `ViewerToolbarMetrics` 计算，适配新的按钮间距；最终当前工作区完整测试重新通过 275 项。切图优化本身只修改 `ImageCanvasView.swift`，未覆盖并行更新的 UI 文件。

重建 Universal 2 成功，无编译 warnings/errors。已仅安装至 `/Applications/PicSee.app`，签名、整个 bundle 一致性验证通过，用户目录副本保持不存在；构建与安装可执行文件 SHA-256 同为 `5e78878c67cc4832da2f2035fbce71d4359cdda3d6cd243656bdf435367b4faf`。在隔离图片目录的实际 App 窗口检查右键切图和前进后反向切图，横竖不同尺寸显示正常；高速连按由回归测试验证，未据此宣称大图帧率基准通过。

## 增强单次切图方向感

用户反馈 14 点位移不明显，本轮仅将单次切图位移增至 24 点，保持 0.16 秒 easeOut、原透明度、快切阈值与 Reduce Motion 行为。同步更新两处位移断言。17 项动画回归复跑全部通过；首次运行中原 SwiftUI 交替缩放测试有两次约 0.0026 的边界超出，重跑未复现，切图测试两轮均通过。本轮未修改缩放实现或放宽测试容差，保留首次与复跑日志，后续仍需关注该测试的帧时序稳定性。

工作区再次在构建期间有工具栏文件变化，改为在 `/private/tmp/picsee-24pt-_0v0to2z` 的当前源码副本中验证并构建。副本的 17 项动画回归通过，避免构建读取到并行编辑中的混合内容；源码修改仍保存在原工作区。

Universal 2 构建成功，已同步构建产物并仅安装到 `/Applications/PicSee.app`，签名和 bundle 一致性通过。构建与安装的可执行文件 SHA-256 同为 `6f8252f2d08a4b8523db6df3b2922a5924a47c3f1f90f924b3dc38524aae9d20`，临时副本中的 App bundle 已清理，避免额外安装候选；用户目录副本保持不存在。日志保存为 `build/verification/picsee-navigation-24pt-*.log`。
