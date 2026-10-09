# 长 PNG 打开性能修复（2026-10-09）

样本为用户指定的桌面 picsee.png，2427×8956，RGBA，5,457,962 字节。原像素展开约 82.9 MiB。用户原文件未修改。

## 复现与原因

使用真实 CanvasNSView 窗口、生产 ImageLoadWorker 加载路径，沿用模型的透明度结果记忆。取消 OCR，导航方向为空，不运行切图动画。Release 优化构建保留 DEBUG 测试观测接口。在 M1 Pro / 32 GiB / macOS 15.8.2 上，每次重新加载原文件，共六次，系统文件缓存已热身。

复现命令：

```bash
PICSEE_OPEN_BENCHMARK_FILE="$HOME/Desktop/picsee.png" swift test -c release -Xswiftc -DDEBUG --disable-swift-testing --filter ImageCanvasAnimationTests/testLongPNGOpeningAvoidsMainThreadStall
```

修复前该命令失败：主线程绘制中位数约153ms，高于100ms门限。文件加载已在后台执行，但原 PNG 文件表示在 AppKit 首次绘制时仍有大量像素准备工作。

对照实验：仅包装 CGImage 仍约151ms；独立原像素缓冲约72ms；直接 ImageIO 立即解码把绘制降至约8ms，但后台耗时增至约310ms，未明显减少合计等待。加入适合窗口的预览表示后，绘制降至约5～6ms，合计等待也减少。

## 最终实现

- 静态 RGB、8位、长边超过2048像素的 PNG：读取源像素到独立 CGImage，在后台附加长边最多2048像素的预览 NSBitmapImageRep。
- 原始色彩空间、逻辑尺寸和全分辨率表示保留。原图与预览均采用 NSBitmapImageRep，确保导出默认尺寸取原图像素；AppKit 可为适合窗口的显示选择预览，放大和导出仍有原像素可用。
- 导出、OCR、裁剪与壁纸统一通过 fullResolutionCGImage 获取最大位图表示，避免普通屏幕环境将预览误作原始像素。云端测试发现此屏幕差异后补充原图导出颜色与普通屏幕上下文回归。
- 透明度检测基于原图完整像素，避免缩略预览漏检小透明区域。
- 多帧 GIF/APNG、高位深、灰度和其他格式保持原生路径。超过现有全分辨率位图预算的图片也保留原生路径。
- 所有实验分支已从测试代码删除；保留原图的可选性能回归测试和原样本测量记录。

## 六次中位数

| 阶段 | 修复前 | 修复后 | 降低 |
|---|---:|---:|---:|
| 后台加载/准备 | 171.21 ms | 229.12 ms | -33.8% |
| 主线程首次绘制/提交 | 153.24 ms | 5.80 ms | 96.2% |
| 合计 | 324.82 ms | 235.16 ms | 27.6% |

合计是后台准备加主线程首次绘制/提交，不是 Finder 双击到屏幕扫描输出的完整延迟；未测首次进程启动、冷磁盘缓存和 OCR。增加后台预览准备使后台阶段略长，但主线程等待明显减少。测试窗口1400×850点，Retina2倍。

## 验证与安装

- 原图性能复现修复前失败，正式加载器修复后通过。
- ImageLoaderRepresentationTests：高 DPI 逻辑尺寸、原分辨率像素/颜色/透明度、导出默认尺寸及实际 PNG 导出尺寸、16位精度、多帧 GIF/APNG 均通过。导出尺寸新增用例先复现失败，再验证修复通过。
- 加载、预取、导出、切图动画及开关回归通过：39项 XCTest（另2项需环境变量启用的基准测试明确跳过）、16项 Swift Testing。
- 项目逻辑回归通过；本地化271条双语字符串通过；git diff --check通过。
- 双架构应用构建完成，安装到 /Applications/PicSee.app；严格深度签名与安装后二进制一致性校验通过。
- 正常退出旧版后，通过 Finder 打开原图，在安装版窗口中确认2427×8956元数据和完整页面显示。

原始数据和日志位于 build/verification/long-png-*；长图性能测试结果为long-png-opening-results.json，基线为long-png-opening-baseline.json。
