import AppKit
import SwiftUI

struct ImageViewerView: View {
    @ObservedObject var viewModel: ImageViewerViewModel
    let updateChecker: UpdateChecker?
    let onTitleBarVisibilityChanged: (Bool) -> Void
    let onFixedWindowChanged: (Bool) -> Void
    @State private var titleBarVisible = ViewerTitleBarPreference.isVisible()
    @State private var fileInfoVisible = ViewerOverlayPreference.isFileInfoVisible()
    @State private var toolbarVisible = ViewerOverlayPreference.isToolbarVisible()
    @State private var imageParametersVisible = ViewerOverlayPreference.isImageParametersVisible()
    @State private var fixedWindowEnabled = WindowFramePreference.isFixedEnabled()
    @State private var navigationPointerX: CGFloat?
    @State private var toolbarPointerY: CGFloat?
    @State private var viewerHeight: CGFloat = 1
    @State private var revealsAvailableNavigationDirections = true
    @State private var hasPresentedNavigationDiscovery = false
    @State private var isFullScreen = false
    private let hudPadding: CGFloat = 12
    private let navigationFadeDuration = 0.18
    private let toolbarEdgeFraction: CGFloat = 0.20
    private let navigationDiscoveryDuration = 1.2

    private var toolbarEffectivelyVisible: Bool {
        guard toolbarVisible else { return false }
        guard isFullScreen else { return true }
        guard let toolbarPointerY, viewerHeight > 0 else { return false }
        let fraction = 1 - toolbarPointerY / viewerHeight
        return fraction >= 0 && fraction <= toolbarEdgeFraction
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            if let image = viewModel.image {
                ImageCanvasView(
                    image: image,
                    imageURL: viewModel.currentURL,
                    zoomScale: $viewModel.zoomScale,
                    panOffset: $viewModel.panOffset,
                    rotationDegrees: $viewModel.rotationDegrees,
                    zoomRequest: $viewModel.zoomRequest,
                    onPrevious: viewModel.navigateToPrevious,
                    onNext: viewModel.navigateToNext,
                    onReset: viewModel.resetViewTransform,
                    onClose: { NSApp.terminate(nil) },
                    onZoomRequestHandled: viewModel.clearZoomRequest,
                    onDisplayScaleChanged: {
                        if abs(viewModel.displayScale - $0) > 0.0001 {
                            viewModel.displayScale = $0
                        }
                    },
                    titleBarVisible: titleBarVisible,
                    fileInfoVisible: fileInfoVisible,
                    toolbarVisible: toolbarVisible,
                    imageParametersVisible: imageParametersVisible,
                    onTitleBarVisibilityChanged: { visible in
                        titleBarVisible = visible
                        onTitleBarVisibilityChanged(visible)
                    },
                    onFileInfoVisibilityChanged: { visible in
                        fileInfoVisible = visible
                    },
                    onToolbarVisibilityChanged: { visible in
                        toolbarVisible = visible
                    },
                    onImageParametersVisibilityChanged: { visible in
                        imageParametersVisible = visible
                    },
                    fixedWindowEnabled: fixedWindowEnabled,
                    onFixedWindowChanged: { fixed in
                        fixedWindowEnabled = fixed
                        onFixedWindowChanged(fixed)
                    },
                    onCheckForUpdates: {
                        Task {
                            await updateChecker?.checkForUpdatesManually()
                        }
                    }
                )
                .overlay(alignment: .topLeading) {
                    if !titleBarVisible {
                        HStack(spacing: 8) {
                            Text(viewModel.zoomPercentageText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.42), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))

                            if fileInfoVisible, let imageMetadataText = viewModel.imageMetadataText {
                                Text(imageMetadataText)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(.black.opacity(0.42), in: Capsule())
                                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                            }
                        }
                        .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 3)
                        .padding(.top, hudPadding)
                        .padding(.leading, hudPadding)
                        .padding(.trailing, 56)
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let updateChecker {
                        UpdatePromptView(updateChecker: updateChecker)
                            .padding(.leading, hudPadding)
                            .padding(.bottom, hudPadding)
                    }
                }
                .overlay(alignment: .bottom) {
                    if toolbarEffectivelyVisible {
                        ImageToolBar(
                            onFitToWindow: viewModel.fitToWindow,
                            onShowHundredPercent: viewModel.showActualSize,
                            onZoomOut: viewModel.zoomOut,
                            onZoomIn: viewModel.zoomIn,
                            onRotateLeft: viewModel.rotateLeft,
                            onRotateRight: viewModel.rotateRight
                        )
                        .padding(.bottom, hudPadding)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .overlay(alignment: .trailing) {
                    if imageParametersVisible, let imageParametersText = viewModel.imageParametersText {
                        ImageParametersPanel(
                            text: imageParametersText,
                            onClose: {
                                imageParametersVisible = false
                                ViewerOverlayPreference.setImageParametersVisible(false)
                            }
                        )
                            .padding(
                                .trailing,
                                ImageParametersPanelLayout.trailingPadding
                            )
                            .offset(
                                y: ImageParametersPanelLayout.verticalOffset(
                                    viewerHeight: viewerHeight
                                )
                            )
                    }
                }
                .overlay {
                    GeometryReader { geometry in
                        imageNavigationControls(viewerWidth: geometry.size.width)
                            .onAppear { viewerHeight = geometry.size.height }
                            .onChange(of: geometry.size.height) { _, newValue in
                                viewerHeight = newValue
                            }
                    }
                }
                .onContinuousHover { phase in
                    let pointerX: CGFloat?
                    switch phase {
                    case .active(let location):
                        pointerX = location.x
                    case .ended:
                        pointerX = nil
                    }
                    withAnimation(.easeInOut(duration: navigationFadeDuration)) {
                        navigationPointerX = pointerX
                    }
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let location):
                        withAnimation(.easeInOut(duration: navigationFadeDuration)) {
                            toolbarPointerY = location.y
                        }
                    case .ended:
                        withAnimation(.easeInOut(duration: navigationFadeDuration)) {
                            toolbarPointerY = nil
                        }
                    }
                }
                .task {
                    await presentNavigationDiscoveryIfNeeded()
                }
            } else {
                VStack(spacing: 12) {
                    Text("Cannot Open Image")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(viewModel.errorMessage ?? "PicSee could not open this file.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(viewModel.currentFilename)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(32)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !titleBarVisible {
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.42), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                        .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭图片")
                .padding(.top, hudPadding)
                .padding(.trailing, hudPadding)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .animation(.easeInOut(duration: navigationFadeDuration), value: toolbarEffectivelyVisible)
        .task {
            if let updateChecker {
                await updateChecker.checkForUpdatesIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerOverlayPreference.toggleImageParametersNotification)) { _ in
            imageParametersVisible.toggle()
            ViewerOverlayPreference.setImageParametersVisible(imageParametersVisible)
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerOverlayPreference.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerOverlayPreference.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }

    @ViewBuilder
    private func imageNavigationControls(viewerWidth: CGFloat) -> some View {
        let visibility = ImageNavigationVisibilityPolicy.visibility(
            pointerX: navigationPointerX,
            viewerWidth: viewerWidth,
            hasPrevious: viewModel.previousURL != nil,
            hasNext: viewModel.nextURL != nil,
            revealsAvailableDirections: revealsAvailableNavigationDirections
        )

        HStack(spacing: 0) {
            if visibility.previous {
                imageNavigationButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "上一张图片",
                    help: "上一张图片",
                    action: viewModel.navigateToPrevious
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            Spacer(minLength: 0)

            if visibility.next {
                imageNavigationButton(
                    systemName: "chevron.right",
                    accessibilityLabel: "下一张图片",
                    help: "下一张图片",
                    action: viewModel.navigateToNext
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: navigationFadeDuration), value: visibility)
    }

    private func imageNavigationButton(
        systemName: String,
        accessibilityLabel: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.46), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
                .shadow(color: .black.opacity(0.32), radius: 10, x: 0, y: 3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }

    @MainActor
    private func presentNavigationDiscoveryIfNeeded() async {
        guard !hasPresentedNavigationDiscovery else { return }
        hasPresentedNavigationDiscovery = true
        revealsAvailableNavigationDirections = true

        try? await Task.sleep(for: .seconds(navigationDiscoveryDuration))
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: navigationFadeDuration)) {
            revealsAvailableNavigationDirections = false
        }
    }

}

enum ImageParametersPanelLayout {
    static let trailingPadding: CGFloat = 12
    static let verticalCenterFraction: CGFloat = 0.25

    static func verticalOffset(viewerHeight: CGFloat) -> CGFloat {
        guard viewerHeight > 0 else { return 0 }
        return -viewerHeight * (0.5 - verticalCenterFraction)
    }
}

private struct ImageToolBar: View {
    let onFitToWindow: () -> Void
    let onShowHundredPercent: () -> Void
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            toolbarButton(iconName: "corners-out-bold", accessibilityLabel: "适合窗口显示图片", action: onFitToWindow)
                .help("适合窗口显示图片")
            toolbarButton(iconName: "number-square-one-bold", accessibilityLabel: "100% 显示图片", action: onShowHundredPercent)
                .help("100% 显示图片（1:1）")
            toolbarButton(iconName: "magnifying-glass-minus-bold", accessibilityLabel: "缩小图片", action: onZoomOut)
                .help("缩小图片")
            toolbarButton(iconName: "magnifying-glass-plus-bold", accessibilityLabel: "放大图片", action: onZoomIn)
                .help("放大图片")
            toolbarButton(iconName: "arrow-counter-clockwise-bold", accessibilityLabel: "向左旋转 90 度", action: onRotateLeft)
                .help("向左旋转 90 度")
            toolbarButton(iconName: "arrow-clockwise-bold", accessibilityLabel: "向右旋转 90 度", action: onRotateRight)
                .help("向右旋转 90 度")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.46), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
    }

    private func toolbarButton(iconName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PhosphorToolbarIcon(name: iconName)
                .aspectRatio(contentMode: .fit)
                .frame(width: 17, height: 17)
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 34, height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(ImageToolBarButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ImageParametersPanel: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.leading, 10)
                .padding(.trailing, 26)
                .padding(.bottom, 10)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 18, height: 18)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .padding(.trailing, 4)
            .accessibilityLabel("关闭图片参数")
        }
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 6)
        .frame(maxWidth: 260, alignment: .leading)
    }
}

private struct PhosphorToolbarIcon: View {
    let name: String

    var body: some View {
        if let image = Self.image(named: name) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .interpolation(.medium)
        } else {
            Image(systemName: "circle")
                .resizable()
                .renderingMode(.template)
        }
    }

    private static func image(named name: String) -> NSImage? {
        guard let url = PicSeeResourceBundle.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: "Phosphor.xcassets/\(name).imageset"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

enum PicSeeResourceBundle {
    static func url(forResource name: String, withExtension fileExtension: String, subdirectory: String) -> URL? {
        candidateBundles.compactMap {
            $0.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
        }
        .first
    }

    private static var candidateBundles: [Bundle] {
        var bundles: [Bundle] = []
        if let appResourcesURL = Bundle.main.resourceURL?
            .appendingPathComponent("PicSee_PicSee.bundle"),
           let bundle = Bundle(url: appResourcesURL) {
            bundles.append(bundle)
        }
        if !bundles.isEmpty { return bundles }
        bundles.append(.module)
        bundles.append(.main)
        return bundles
    }
}

private struct ImageToolBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                (configuration.isPressed ? Color.white.opacity(0.20) : Color.white.opacity(0.08)),
                in: Capsule()
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct UpdatePromptView: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        if let update = updateChecker.availableUpdate, updateChecker.status != .downloaded {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(message(for: update))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)

                    Button(action: {
                        Task { await updateChecker.downloadAvailableUpdate() }
                    }) {
                        Text(updateButtonTitle)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                    .disabled(updateChecker.status == .downloading)

                    Button(action: updateChecker.ignoreAvailableUpdate) {
                        Text("忽略")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.78))
                    .disabled(updateChecker.status == .downloading)
                }

                if updateChecker.status == .downloading {
                    ProgressView(value: updateChecker.downloadProgress ?? 0)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .tint(Color(red: 0.18, green: 0.48, blue: 0.95))
                        .frame(width: 180)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var updateButtonTitle: String {
        switch updateChecker.status {
        case .downloading:
            return "下载中..."
        case .failed:
            return "重试"
        default:
            return "更新"
        }
    }

    private func message(for update: GitHubRelease) -> String {
        if updateChecker.status == .failed {
            return "下载失败"
        }
        return "发现新版本 \(update.version.displayString)"
    }
}
