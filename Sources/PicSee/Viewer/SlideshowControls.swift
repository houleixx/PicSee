import SwiftUI

struct SlideshowControls: View {
    @ObservedObject var slideshow: SlideshowController
    let isReady: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    var body: some View {
        HStack(spacing: ViewerToolbarMetrics.spacing) {
            HStack(spacing: 0) {
                icon(.previous, label: "上一张", action: onPrevious)
                icon(slideshow.state == .playing ? .pause : .play,
                     label: slideshow.state == .playing ? "暂停幻灯片" : "继续幻灯片",
                     action: slideshow.togglePause)
                    .help("空格：暂停或继续幻灯片")
                icon(.next, label: "下一张", action: onNext)
            }
            ViewerToolbarDivider(color: .white)
                .padding(.horizontal, ViewerToolbarMetrics.viewerDividerPadding)
            intervalMenu
            HStack(spacing: 0) {
                icon(.repeatImages, label: "循环播放", selected: slideshow.loops) {
                    slideshow.loops.toggle()
                }
                .accessibilityValue(slideshow.loops ? "已开启" : "已关闭")
                .help(slideshow.loops ? "关闭循环播放" : "开启循环播放")
                icon(isFullScreen ? .exitFullScreen : .enterFullScreen,
                     label: isFullScreen ? "退出全屏" : "全屏播放",
                     action: onToggleFullScreen)
                    .disabled(slideshow.isFullScreenTransitioning)
                icon(.exitSlideshow, label: "退出幻灯片（Esc）", action: slideshow.stop)
                    .help("退出幻灯片，返回看图（Esc）")
            }
        }
        .modifier(ViewerToolbarSurface())
    }

    private var intervalMenu: some View {
        Menu {
            Picker("播放间隔", selection: Binding(
                get: { slideshow.interval }, set: { slideshow.setInterval($0) }
            )) {
                ForEach(SlideshowController.intervals, id: \.self) { seconds in
                    Text("\(seconds) 秒").tag(seconds)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(isReady ? "\(slideshow.interval) 秒" : "准备中…")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white.opacity(0.95))
            // Bring dense text closer to the divider for optical balance with
            // the outline arrow. Keep the label intrinsic so no spare gap grows.
            .padding(.leading, 8)
            .padding(.trailing, 2.5)
            .frame(height: ViewerToolbarMetrics.viewerButtonHeight)
            .fixedSize()
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ViewerToolbarButtonStyle(foreground: .white.opacity(0.95)))
        .accessibilityLabel("播放间隔")
        .accessibilityValue(isReady ? "\(slideshow.interval) 秒" : "准备中")
        .help("每张图片的展示时间")
    }

    private func icon(
        _ symbol: ViewerToolbarIcon.Symbol,
        label: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ViewerToolbarIcon(symbol: symbol)
                .frame(width: ViewerToolbarMetrics.buttonSize, height: ViewerToolbarMetrics.viewerButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(ViewerToolbarButtonStyle(
            selected: selected,
            foreground: .white.opacity(0.95)
        ))
        .accessibilityLabel(label)
        .help(label)
    }
}
