# 图片拖出保存验证记录

## 首次本地试用构建与安装（发版前）

已构建 arm64/x86_64 Universal 2 应用，并安装至 `/Applications/PicSee.app`。版本为 `0.2.54`，本地测试构建号为 `55`。构建脚本的默认版本号未修改。

安装前后均通过 `codesign --verify --deep --strict`；`cmp` 确认安装二进制与构建产物一致。安装前副本保存在 `/tmp/PicSee-before-drag-install.IdVxmA/PicSee.app`。

## v0.2.55 发版前复验

用户试用后要求发布。版本默认值、README 示例和 CHANGELOG 更新为 `0.2.55`，继续沿用版本标签触发 GitHub Actions 的双架构 DMG 发布流程。

独立审查发现符号链接指向的图片在解析前检查普通文件属性，会错误进入 PNG 编码兜底。新增测试先复现 `missingCGImage`，随后改为先解析真实 URL，再检查、返回或复制真实文件。测试覆盖普通来源和临时来源，检查 GIF 原字节、真实文件名及副本不是符号链接；修复经独立复查确认。

最终 `swift test` 执行 299 个测试用例，298 个通过；新增 19 个拖拽测试全部通过。仍有 1 个既有动画测试失败，包含 11 条时序/显示范围断言，不是 11 个测试用例失败。失败项为 `testToolbarZoomRemainsVisibleThroughSwiftUIUpdates`，未修改该测试或动画实现，也未放宽断言。未修改的 v0.2.54（f31de7a）独立临时副本复测仍出现该测试第 101 行失败；此前验证记录也已记录该测试的显示范围时序波动。本次按已说明并接受的既有问题保留记录。

`bash Tests/build-dmg-tests.sh` 通过。原生 Finder/桌面落盘没有新增自动验收证据，继续保留下面的实机验收边界说明。

最终本地 Universal 2 应用与 DMG 构建成功。`bash Tests/verify-dmg.sh build/dmg/PicSee-0.2.55.dmg` 确认签名应用内容、Applications 链接、背景与安装布局一致；`hdiutil verify` 通过。该本地 ad-hoc 包 SHA-256 为 `9851c51f53ce3f2a837018738e0771d3ae369fded3f0ba2140773f0aa74d4b75`，不代表后续 GitHub Actions 正式签名/公证包的哈希。

## 实现范围

- `Sources/PicSee/Viewer/ImageCanvasView.swift`：普通图片按下成为导出候选，窗口内沿用原平移；窗口移动、窗口缩放、文字选择优先处理；切图、松开和原生拖拽结束时复位。
- `Sources/PicSee/Viewer/ImageDragPolicy.swift`：距按下位置移动至少 12 点，且离开整个窗口的 12 点缓冲区后才允许原生导出，坐标采用屏幕逻辑点。
- `Sources/PicSee/Viewer/ImageFileDragController.swift`：AppKit `NSDraggingItem` + 文件 URL + `NSDraggingSession`，提供缩略图，仅允许应用外复制；失败记录日志，取消不改动原图。
- `Sources/PicSee/Viewer/ImageDragFileProvider.swift`：本地文件使用解析符号链接后的真实文件 URL；系统临时目录来源按原字节复制；仅有 `NSImage` 时使用现有 `ImageExporter` 导出 PNG。
- `Sources/PicSee/App/AppDelegate.swift`：启动时清理过期临时导出目录。
- `README.md`：增加使用方式、手势边界和临时文件说明。
- 新增 `ImageCanvasFileDragTests.swift`、`ImageDragFileProviderTests.swift`、`ImageDragPolicyTests.swift`。

## 临时文件

使用系统临时目录中的 `PicSee-DragExports/export-<PID>-<UUID>/可读文件名`，每次导出独立目录，避免覆盖。后续启动或导出时，只删除已过 24 小时且所属进程不再运行的导出目录；不在松手或退出时立即删除，以便接收方继续读取。失败写入会移除本次未完成目录。

## 首次实现自动检查（符号链接修复前）

执行 `swift test`：共 298 项，297 项通过，1 项失败。新增 18 项全部通过，覆盖：

- 普通点击、轻微拖动、窗口内部拖动和窗口边缘缓冲区不启动文件拖拽。
- 放大后保持平移，越界时才转换，一次按压只启动一次系统会话。
- 无标题栏顶部继续调用窗口移动；右下角、左上角继续改变窗口大小，越界也不导出。
- 取消后连续重复导出，源文件字节保持不变；切图取消候选。
- 失败后不反复重试，下一次操作仍能平移。
- 本地 JPG/PNG/WebP/GIF 路径和字节保持不变；临时 GIF 直接复制，重复导出不覆盖。
- 内存及带远程 URL 的内存图片生成真正的 PNG，文件名和像素尺寸匹配。
- 多屏负坐标和四个窗口边界；过期清理跳过活动进程及无关目录。

失败项为现有 `ImageCanvasAnimationTests.testToolbarZoomRemainsVisibleThroughSwiftUIUpdates` 的第 101 行动画时序断言。通过 `git archive HEAD` 在独立临时目录运行未修改代码，同一测试同一断言也失败。没有修改或放宽该测试。

## 实机验收边界

Computer Use 原生管道启动失败，未完成真实 Finder/桌面拖放。自动测试注入了系统会话启动入口，验证状态、URL 和预览参数，不等同于接收方已成功落盘。需要用户实测 JPG 到桌面、PNG 到 Finder、取消、连续拖出，以及无标题栏移动/缩放。

网络 URL、Blob 和剪贴板导入入口不是当前项目功能。本次仅提供已有内存图片的导出兜底，没有新增下载或导入流程。PicSee 当前仅支持 macOS。

全屏或窗口贴住屏幕边缘时可能无法越过窗口边界，可先缩小窗口或使用现有另存为。平移时越过窗口缓冲区会转换为文件拖拽；原生会话开始后，同一次按压不再切回平移。
