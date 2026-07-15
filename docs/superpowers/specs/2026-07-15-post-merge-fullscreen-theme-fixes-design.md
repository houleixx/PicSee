# Post-merge Fullscreen and Theme Fixes

## Goal

修复 PR #2 合并后确认的窗口全屏恢复与主题菜单问题，同时补齐能阻止这些问题再次出现的自动化测试，并将验证后的应用安装到本地。

## Scope

- 修复隐藏标题栏窗口退出原生全屏时的标题栏高度补偿。
- 在原生全屏进入失败时恢复进入前的窗口样式。
- 保证 Live Text 菜单重复更新时只存在一个“主题”菜单。
- 移除本次变更中确认未使用的全屏和工具栏状态代码。
- 添加窗口恢复、失败回滚、主题菜单幂等与主题偏好测试。
- 运行完整测试和 Release 构建，并安装到 `~/Applications/PicSee.app`。

## Design

### Fullscreen restoration

将窗口几何计算拆成可单元测试的纯函数。退出全屏时，必须在窗口仍使用 `.titled` 样式时取得标题栏高度，然后再切换回用户当前标题栏偏好对应的样式。隐藏标题栏时，恢复 frame 需要将高度减少标题栏高度并将原点向上移动相同距离；显示标题栏时保持系统恢复的 frame。

### Failed fullscreen entry

`ViewerWindow` 在进入全屏前保存原始 `styleMask`。`WindowDelegate` 增加全屏进入失败回调，失败时恢复保存的样式并清空临时状态。正常退出时按用户当前标题栏偏好恢复，而不是使用旧偏好，以保留用户在全屏期间作出的设置变化。

### Theme menu idempotency

顶层“主题”菜单使用稳定的 `NSUserInterfaceItemIdentifier`。追加 PicSee 菜单项时按该 identifier 判断是否已经存在，不再通过只出现在子菜单项上的 action 判断。

### Cleanup

删除不参与任何恢复路径的 `toolbarHoverEdgeFraction`。`fullScreenPreMask` 保留并真正用于进入失败回滚，正常退出后清空。

## Testing

测试先行并验证失败原因：

- 标题栏为 28px 时，隐藏标题栏恢复 frame 正确缩短并上移 28px。
- 显示标题栏时退出全屏保持 frame。
- 进入全屏失败时恢复进入前的 style mask，并清空临时状态。
- 连续两次追加上下文菜单仍只有一个“主题”菜单。
- `ViewerTheme` 默认值、持久化、非法值回退和 appearance 映射正确。

完成后运行完整 `swift test`、`swift build -c release` 和应用构建脚本。

## Installation

使用项目现有 `Scripts/build-app.sh` 构建通用架构应用并安装到 `~/Applications/PicSee.app`。安装前终止旧 PicSee 进程，安装后验证可执行文件架构和应用版本信息。
