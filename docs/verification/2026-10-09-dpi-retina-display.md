# DPI 与 Retina 显示修复（2026-10-09）

## 问题与复现

Canvas 原先使用 NSImage.size（由像素和文件 DPI 换算的逻辑尺寸），并将适应比例限制在 1。5184×3888、350 DPI 图片因此按约1066×800点显示，6000×4000、180 DPI 图片按2400×1600点显示。在1920×1080点视口中分别报告100%与68%。

新增 ImageCanvasPixelScaleTests，直接经过实际 Canvas 布局，在普通屏幕与 Retina 屏幕下断言两种大图、72/180/350 DPI 都适应视口，以及小图保持原像素比例。修复前两个测试共12个断言失败，修复后通过。

## 实现

- Canvas 在图片变更时缓存原像素尺寸；显示几何的图片尺寸统一使用源像素，视口使用 AppKit 点。
- 根据所属窗口的 backingScaleFactor 转换屏幕绘制像素。适应窗口保留比例，小图不放大超过一个原像素对应一个 backing 像素。
- 显示百分比报告 backing 像素与源像素的比例；100% 表示一一对应。Retina 2×屏幕上100%图片宽度为源像素宽度的一半（点）。
- 窗口挂载和 backing 属性变化时重新布局；动画采样、旧图过渡、缩放锚点、迷你地图与裁剪叠层使用相同坐标约定。
- 原文件、DPI 元数据、原图表示与导出分辨率均未修改。

## 验证

- 新增5项实际 Canvas 回归：高 DPI 大图适应、普通/Retina 小图实际像素、100%命令及百分比回调、跨屏幕比例变化、窗口尺寸及90度旋转。
- 新增 Retina 几何缩放锚点回归，确保后续几何重建保留 backing 比例。
- `bash Scripts/test-swift.sh all` 全部通过；2项需要环境变量启用的性能基准明确跳过。完整日志：build/verification/dpi-retina-all-tests.log。
- 本地化271条双语字符串、git diff --check通过。

## 本地测试版安装

以 PICSEE_VERSION=0.2.73、PICSEE_BUILD_NUMBER=73 构建 arm64/x86_64 双架构本地测试版，使用 Developer ID Application: Baixing Co. ,Ltd. (3989F32QL4) 证书签名，带时间戳和 hardened runtime。严格深度签名验证通过。

正常退出旧版后安装到 /Applications/PicSee.app；安装后二进制与已验证构建完全一致，版本号0.2.73。旧版备份：/private/tmp/picsee-dpi-retina-install.TCeK8t/PicSee.previous.app。

通过 Finder 打开用户桌面的原始 JPEG，在安装版3840×2160像素、Retina2×全屏窗口实际核验：

- 5184×3888、350 DPI：显示56%（精确像素比例约55.56%），图片2880×2160屏幕绘制像素，四角及边框完整。
- 6000×4000、180 DPI：全屏切图后显示54%，图片3240×2160屏幕绘制像素，四角及边框完整。
- 已保持第二张图片的适应全屏状态，供用户继续测试。

这是本地正式证书签名的测试构建，未执行 Apple 公证或公开发布。
