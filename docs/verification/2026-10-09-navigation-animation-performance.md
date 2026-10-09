# 大图切换动画性能对比（2026-10-09）

这份数据对应长 PNG 预览表示优化之前的加载器；后续长图打开修复的复测见 `2026-10-09-long-png-opening.md`。表中 PNG 的绝对加载耗时不应当作修复后版本的当前数据。

本机：Apple M1 Pro，32 GiB 内存，macOS 15.8.2；4K 屏幕。测试窗口为 1600×900 点，Retina 2 倍，即 3200×1800 像素。

## 测量方法

- 使用真实 AppKit 窗口和当前 CanvasNSView 切图代码。使用 Release 优化，并通过 `-DDEBUG` 保留现有测试观测接口。
- 固定随机种子 38402160，生成两张 960×540 RGB 纹理图，再用双三次插值放大到 3840×2160 / 7680×4320；分别保存为质量 92 的 JPEG 和 PNG。4K JPEG 约 4.3 MiB，4K PNG 约 17 MiB，8K JPEG 约 11 MiB，8K PNG 约 58 MiB。
- 每个尺寸、格式、加载模式测试开启/关闭各 14 次，丢弃前两次预热，保留各 12 次，中位数汇总；AB/BA 交替次序。
- decoded：复用已解码并经显示热身的 NSImage，近似图片缓存命中。reload：每次使用 ImageLoadWorker 重新加载目标文件，系统文件缓存已热身，不代表冷磁盘读取。
- 每次模拟单次翻页（不触发 220ms 内的连续切换免动画逻辑）；减少动态效果关闭。取消 OCR，单独比较图片加载/显示准备及切换动画。
- 软件侧完成耗时：从取图开始，到渲染事务完成回调且切换动画从图层移除。开启时确认确实创建了动画，关闭时确认没有动画。
- 渲染事务完成回调可能早于显式动画结束，因此另行等待动画移除。读图返回后，AppKit 仍可能进行懒解码或显示准备，不能把 decodeMS 独立解释为完整像素解码耗时。
- 结果不含输入事件、完整 SwiftUI/导航路径、Finder 排序、屏幕扫描输出或 OCR；不是按键到屏幕首帧的精确延迟，也不能据此计算 CPU/GPU 利用率。

## 中位数结果

| 尺寸 | 格式 | 加载模式 | 开启完成 ms | 关闭完成 ms | 缩短 ms | 完成耗时降低 | 开启事务回调 ms | 关闭事务回调 ms |
|---|---|---|---:|---:|---:|---:|---:|---:|
| 4K | JPG | decoded | 165.25 | 2.55 | 162.70 | 98.5% | 2.65 | 2.55 |
| 4K | JPG | reload | 177.22 | 14.34 | 162.87 | 91.9% | 14.55 | 14.34 |
| 4K | PNG | decoded | 165.04 | 2.49 | 162.56 | 98.5% | 2.68 | 2.48 |
| 4K | PNG | reload | 299.62 | 140.22 | 159.40 | 53.2% | 140.36 | 140.21 |
| 8K | JPG | decoded | 164.70 | 2.47 | 162.23 | 98.5% | 2.65 | 2.47 |
| 8K | JPG | reload | 191.76 | 28.62 | 163.15 | 85.1% | 29.16 | 28.61 |
| 8K | PNG | decoded | 165.38 | 2.50 | 162.88 | 98.5% | 2.69 | 2.50 |
| 8K | PNG | reload | 698.78 | 545.96 | 152.82 | 21.9% | 548.00 | 545.96 |

## 解读

关闭动画主要省掉约 153～163ms 的过渡完成时间。读取/提交至渲染事务回调的耗时差约 0.1～2.0ms，远小于过渡时长；本次测试没有体现出大幅提高图片加载速度。百分比针对含过渡的完成耗时，不是解码吞吐量提升。

图片已准备好时，软件侧完成耗时由约 165ms 降至约 2.5ms；需要重新读取的大 PNG 准备时间更长，8K PNG 从约 699ms 降至约 546ms，降低约 22%。真实照片、磁盘和全屏尺寸变化会改变绝对值。

## 复测与原始结果

```bash
PICSEE_NAVIGATION_BENCHMARK="$PWD/build/verification/navigation-benchmark" swift test -c release -Xswiftc -DDEBUG --disable-swift-testing --filter ImageCanvasAnimationTests/testLargeImageNavigationBenchmark
```

- 原始逐次结果：`build/verification/navigation-benchmark/results.json`（192 条有效样本）
- 测试日志：`build/verification/navigation-benchmark/run-release.log`（性能测试通过，约48秒）
- 环境信息：`build/verification/navigation-benchmark/environment.txt`
- 图片素材保留于同一目录。
- 测试默认不运行，需上述环境变量启用。此次只增加测试观测和基准，不改变已安装应用的 Release 行为。
