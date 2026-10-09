# 图片切换动画开关

- 位置：设置 → 显示设置 → 图片浏览 → 图片切换动画，默认开启，中英文均已覆盖。
- 使用现有 ViewerPreferences 通知机制保存并同步偏好；新建窗口在展示图片前读取设置。
- 关闭时取消正在播放或等待布局的过渡、释放旧图，并清空连续切换时间记录；重新开启后下一次切换可恢复动画。
- 缩放、旋转和系统减少动态效果的原有逻辑保留；快速连续切换仍直接展示图片。

验证：

- 现有 ImageCanvasAnimationTests、ViewerPreferencesTests、SettingsWindowTests：30 项 XCTest 通过。
- 新增 ImageCanvasAnimationPreferenceTests：3 项测试（包含待播放/播放中两个参数案例）通过，覆盖默认值、重新读取设置、多窗口实时响应、旧图清理、重新开启和缩放旋转隔离。
- `bash Scripts/test-swift.sh logic` 通过。
- `python3 Scripts/check-localizations.py`：271 条双语文案通过。
- `git diff --check` 通过。
- `PICSEE_SKIP_LOCAL_INSTALL=1 Scripts/build-app.sh` 完成 arm64 / x86_64 release 构建及签名。
- 已安装到 `/Applications/PicSee.app`，深度严格签名校验通过，安装后二进制与构建产物一致。
- 已启动安装版，在真实设置窗口确认分组、开关、默认开启状态及说明排版正常。

日志位于 `build/verification/navigation-animation-toggle-*.log`。
