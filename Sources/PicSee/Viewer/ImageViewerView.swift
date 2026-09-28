import AppKit
import SwiftUI

struct ImageViewerView: View {
    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject private var preferences = ViewerPreferences.shared
    @ObservedObject var viewModel: ImageViewerViewModel
    let updateChecker: UpdateChecker?
    let onTitleBarVisibilityChanged: (Bool) -> Void
    let onFixedWindowChanged: (Bool) -> Void
    let onRequestDeletion: () -> Void
    var onToggleFullScreen: () -> Void = {}
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
    @State private var screenshotDocument: ScreenshotDocument?
    @State private var screenshotFailure: (() -> String)?
    private var screenshotError: String? {
        get { screenshotFailure?() }
        nonmutating set { screenshotFailure = newValue.map { value in { value } } }
    }
    @State private var clipboardNoticeID: UUID?
    @State private var latestVersionNoticeID: UUID?
    @State private var clipboardFailure: (() -> String)?
    private var clipboardError: String? {
        get { clipboardFailure?() }
        nonmutating set { clipboardFailure = newValue.map { value in { value } } }
    }
    @State private var deletionNoticeVisible = false
    @State private var slideshowControlsVisible = true
    @State private var slideshowControlsHovered = false
    @State private var slideshowActivityID = 0

    private var slideshowChromeVisible: Bool {
        !viewModel.slideshow.isActive || viewModel.slideshow.state == .paused || slideshowControlsVisible
    }
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
                    transformAnimationID: viewModel.transformAnimationID,
                    navigationDirection: viewModel.navigationDirection,
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
                            latestVersionNoticeID = nil
                            if await updateChecker?.checkForUpdatesManually() == true {
                                clipboardNoticeID = nil
                                latestVersionNoticeID = UUID()
                            }
                        }
                    },
                    canTrashImage: viewModel.canTrashCurrentImage,
                    canUndoDeletion: viewModel.canUndoDeletion,
                    onTrashImage: onRequestDeletion,
                    onUndoDeletion: viewModel.undoDeletion,
                    slideshow: viewModel.slideshow,
                    onStartSlideshow: viewModel.startSlideshow
                )
                .id(viewModel.sessionID)
                .overlay(alignment: .topLeading) {
                    if !titleBarVisible && screenshotDocument == nil && slideshowChromeVisible {
                        HStack(spacing: 8) {
                            Text(viewModel.zoomPercentageText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.42), in: Capsule())

                            if fileInfoVisible, let imageMetadataText = viewModel.imageMetadataText {
                                Text(imageMetadataText)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(.black.opacity(0.42), in: Capsule())
                            }
                        }
                        .padding(.top, hudPadding)
                        .padding(.leading, hudPadding)
                        .padding(.trailing, 56)
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let updateChecker, !viewModel.slideshow.isActive {
                        UpdatePromptView(updateChecker: updateChecker)
                            .padding(.leading, hudPadding)
                            .padding(.bottom, hudPadding)
                    }
                }
                .overlay(alignment: .bottom) {
                    if screenshotDocument == nil {
                        viewerControls
                            .padding(.bottom, hudPadding)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .trailing) {
                    if screenshotDocument == nil, slideshowChromeVisible, imageParametersVisible, let imageParametersText = viewModel.imageParametersText {
                        ImageParametersPanel(
                            usesFlatStyle: !titleBarVisible,
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
                            .opacity(screenshotDocument == nil && slideshowChromeVisible ? 1 : 0)
                            .allowsHitTesting(screenshotDocument == nil && slideshowChromeVisible)
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
                        revealSlideshowControls()
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
            } else if viewModel.isFolderEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(L10n.text("此文件夹中没有可浏览的图片"))
                        .font(.system(size: 18, weight: .semibold))
                    Text(viewModel.currentURL.deletingLastPathComponent().lastPathComponent)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        if viewModel.canUndoDeletion {
                            Button(L10n.text("撤销删除"), action: viewModel.undoDeletion)
                                .help(L10n.text("恢复上一张删除的图片（⌘Z）"))
                        }
                        Button(L10n.text("退出 PicSee")) { NSApp.terminate(nil) }
                    }
                }
                .padding(32)
            } else {
                VStack(spacing: 12) {
                    Text(L10n.text("无法打开图片"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(viewModel.errorMessage ?? L10n.text("PicSee 无法打开此文件。"))
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
            if !titleBarVisible && screenshotDocument == nil && slideshowChromeVisible {
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("关闭图片"))
                .padding(.top, hudPadding)
                .padding(.trailing, hudPadding)
            }
        }
        .overlay {
            if let screenshotDocument, let image = viewModel.image {
                GeometryReader { geometry in
                    ScreenshotEditorView(
                        document: screenshotDocument,
                        imageRect: ImageDisplayGeometry(
                            imageSize: image.size, viewportSize: geometry.size,
                            zoomScale: viewModel.zoomScale, panOffset: viewModel.panOffset,
                            rotationDegrees: viewModel.rotationDegrees
                        ).imageRect,
                        onClose: closeScreenshot,
                        onCopy: {
                            latestVersionNoticeID = nil
                            clipboardNoticeID = UUID()
                        }
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: screenshotDocument != nil)
        .overlay(alignment: .center) {
            if clipboardNoticeID != nil || latestVersionNoticeID != nil {
                VStack(spacing: 16) {
                    Image(nsImage: PhosphorImages.check)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(Color.green)
                        .accessibilityHidden(true)
                    Text(latestVersionNoticeID != nil ? L10n.text("已经是最新版本了") : L10n.text("已复制到剪贴板"))
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 28)
                .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(titleBarVisible ? 0.12 : 0), radius: 12, y: 4)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: clipboardNoticeID != nil || latestVersionNoticeID != nil)
        .overlay(alignment: .top) {
            if deletionNoticeVisible && !viewModel.isFolderEmpty && screenshotDocument == nil {
                DeletionNoticeView(canUndo: viewModel.canUndoDeletion, onUndo: viewModel.undoDeletion)
                .padding(.top, 56)
            }
        }
        .task(id: viewModel.deletionNoticeID) {
            deletionNoticeVisible = viewModel.deletionNoticeID != nil
            guard deletionNoticeVisible else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            deletionNoticeVisible = false
        }
        .alert(L10n.text("文件操作失败"), isPresented: Binding(
            get: { viewModel.fileOperationError != nil },
            set: { if !$0 { viewModel.fileOperationError = nil } }
        )) {
            Button(L10n.text("好")) { viewModel.fileOperationError = nil }
        } message: { Text(viewModel.fileOperationError ?? "") }
        .task(id: clipboardNoticeID) {
            guard clipboardNoticeID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            clipboardNoticeID = nil
        }
        .task(id: latestVersionNoticeID) {
            guard latestVersionNoticeID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            latestVersionNoticeID = nil
        }
        .alert(L10n.text("无法复制图片"), isPresented: Binding(
            get: { clipboardError != nil }, set: { if !$0 { clipboardError = nil } }
        )) {
            Button(L10n.text("好")) { clipboardError = nil }
        } message: { Text(clipboardError ?? "") }
        .environment(\.locale, L10n.locale)
        .onChange(of: viewModel.sessionID) { _, _ in
            closeScreenshot()
            screenshotError = nil
            clipboardError = nil
            clipboardNoticeID = nil
            latestVersionNoticeID = nil
            deletionNoticeVisible = false
            navigationPointerX = nil
            toolbarPointerY = nil
            slideshowControlsHovered = false
            slideshowControlsVisible = true
        }
        .onChange(of: viewModel.currentURL) { _, _ in closeScreenshot() }
        // AppKit temporarily detaches this view during native full-screen changes.
        // WindowDelegate owns stopping playback when the window actually closes.
        .onDisappear { closeScreenshot() }
        .onChange(of: viewModel.slideshow.state) { _, _ in revealSlideshowControls() }
        .task(id: slideshowActivityID) {
            guard viewModel.slideshow.state == .playing else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled, !slideshowControlsHovered else { return }
            withAnimation(.easeInOut(duration: navigationFadeDuration)) {
                slideshowControlsVisible = false
            }
        }
        .alert(L10n.text("无法开始截图"), isPresented: Binding(
            get: { screenshotError != nil }, set: { if !$0 { screenshotError = nil } }
        )) {
            Button(L10n.text("好")) { screenshotError = nil }
        } message: { Text(screenshotError ?? "") }
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
        // Initial @State values are read directly from defaults. A cached shared
        // snapshot must not overwrite newer values when a viewer first opens.
        .onReceive(preferences.$snapshot.dropFirst()) { snapshot in
            if titleBarVisible != snapshot.titleBarVisible {
                titleBarVisible = snapshot.titleBarVisible
                onTitleBarVisibilityChanged(snapshot.titleBarVisible)
            }
            if fixedWindowEnabled != snapshot.fixedWindowEnabled {
                fixedWindowEnabled = snapshot.fixedWindowEnabled
                onFixedWindowChanged(snapshot.fixedWindowEnabled)
            }
            fileInfoVisible = snapshot.fileInfoVisible
            toolbarVisible = snapshot.toolbarVisible
            imageParametersVisible = snapshot.imageParametersVisible
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerOverlayPreference.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerOverlayPreference.beginScreenshotNotification)) { _ in
            beginScreenshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: ViewerOverlayPreference.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }

    private func revealSlideshowControls() {
        guard viewModel.slideshow.isActive else { return }
        slideshowControlsVisible = true
        slideshowActivityID += 1
    }

    @ViewBuilder
    private var viewerControls: some View {
        if viewModel.slideshow.isActive {
            if slideshowChromeVisible {
                SlideshowControls(
                    slideshow: viewModel.slideshow,
                    isReady: viewModel.isNavigationOrderReady,
                    onPrevious: viewModel.navigateToPrevious,
                    onNext: viewModel.navigateToNext,
                    isFullScreen: isFullScreen,
                    onToggleFullScreen: onToggleFullScreen
                )
                .onHover { hovering in
                    slideshowControlsHovered = hovering
                    revealSlideshowControls()
                }
            }
        } else if toolbarEffectivelyVisible {
            ImageToolBar(
                onFitToWindow: viewModel.fitToWindow,
                onShowHundredPercent: viewModel.showActualSize,
                onZoomOut: viewModel.zoomOut,
                onZoomIn: viewModel.zoomIn,
                onRotateLeft: viewModel.rotateLeft,
                onRotateRight: viewModel.rotateRight,
                onCopy: copyCurrentImage,
                onScreenshot: beginScreenshot,
                onSlideshow: viewModel.startSlideshow
            )
        }
    }

    private func copyCurrentImage() {
        viewModel.slideshow.pause()
        guard let image = viewModel.image else { return }
        latestVersionNoticeID = nil
        clipboardNoticeID = nil
        do {
            let copiedImage = viewModel.rotationDegrees == 0
                ? image
                : try ScreenshotDocument(image: image, rotationDegrees: viewModel.rotationDegrees).image
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([copiedImage]) else {
                clipboardFailure = { L10n.text("无法写入剪贴板，请重试。") }
                return
            }
            clipboardNoticeID = UUID()
        } catch {
            clipboardFailure = { L10n.text("无法准备要复制的图片。\n%1$@", String(describing: L10n.errorDescription(error))) }
        }
    }

    private func closeScreenshot() {
        screenshotDocument = nil
        viewModel.isScreenshotEditing = false
    }

    private func beginScreenshot() {
        guard screenshotDocument == nil, let image = viewModel.image else { return }
        viewModel.slideshow.pause()
        do {
            screenshotDocument = try ScreenshotDocument(image: image, rotationDegrees: viewModel.rotationDegrees)
            viewModel.isScreenshotEditing = true
        } catch { screenshotFailure = { L10n.errorDescription(error) } }
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
                    accessibilityLabel: L10n.text("上一张图片"),
                    help: L10n.text("上一张图片"),
                    action: viewModel.navigateToPrevious
                )
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            if visibility.next {
                imageNavigationButton(
                    systemName: "chevron.right",
                    accessibilityLabel: L10n.text("下一张图片"),
                    help: L10n.text("下一张图片"),
                    action: viewModel.navigateToNext
                )
                .transition(.opacity)
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
                .overlay(Circle().stroke(.white.opacity(titleBarVisible ? 0.24 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(titleBarVisible ? 0.32 : 0), radius: 10, x: 0, y: 3)
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

struct ImageToolBar: View {
    @ObservedObject private var language = LanguageSettings.shared
    let onFitToWindow: () -> Void
    let onShowHundredPercent: () -> Void
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onRotateLeft: () -> Void
    let onRotateRight: () -> Void
    let onCopy: () -> Void
    let onScreenshot: () -> Void
    let onSlideshow: () -> Void

    var body: some View {
        HStack(spacing: ViewerToolbarMetrics.spacing) {
            // Keep the edit entry visible when a small image opens in a narrow window.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ViewerToolbarMetrics.spacing) {
                    toolbarButton(.fit, label: L10n.text("适合窗口显示图片"), action: onFitToWindow)
                        .help(L10n.text("适合窗口显示图片"))
                    toolbarButton(.actualSize, label: L10n.text("100% 显示图片"), action: onShowHundredPercent)
                        .help(L10n.text("100% 显示图片（1:1）"))
                    toolbarButton(.zoomOut, label: L10n.text("缩小图片"), action: onZoomOut)
                        .help(L10n.text("缩小图片"))
                    toolbarButton(.zoomIn, label: L10n.text("放大图片"), action: onZoomIn)
                        .help(L10n.text("放大图片"))
                    toolbarButton(.rotateLeft, label: L10n.text("向左旋转 90 度"), action: onRotateLeft)
                        .help(L10n.text("向左旋转 90 度"))
                    toolbarButton(.rotateRight, label: L10n.text("向右旋转 90 度"), action: onRotateRight)
                        .help(L10n.text("向右旋转 90 度"))
                    toolbarButton(.copy, label: L10n.text("复制图片"), action: onCopy)
                        .help(L10n.text("复制图片到剪贴板"))
                }
            }
            .frame(height: ViewerToolbarMetrics.viewerButtonHeight)
            toolbarButton(.play, label: L10n.text("播放幻灯片"), action: onSlideshow)
                .help(L10n.text("播放当前文件夹中的图片"))
            ViewerToolbarDivider(color: .white)
                .padding(.horizontal, ViewerToolbarMetrics.viewerDividerPadding)
            toolbarButton(.crop, label: L10n.text("截图与标注"), action: onScreenshot)
                .help(L10n.text("截取图片区域并标注（⌘⇧A）"))
        }
        .modifier(ViewerToolbarSurface(maxWidth: ViewerToolbarMetrics.viewerWidth))
    }

    private func toolbarButton(_ symbol: ViewerToolbarIcon.Symbol, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ViewerToolbarIcon(symbol: symbol)
                .frame(width: ViewerToolbarMetrics.buttonSize, height: ViewerToolbarMetrics.viewerButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(ViewerToolbarButtonStyle(foreground: .white.opacity(0.95)))
        .accessibilityLabel(label)
    }
}

private struct ImageParametersPanel: View {
    @ObservedObject private var language = LanguageSettings.shared
    let usesFlatStyle: Bool
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
            .accessibilityLabel(L10n.text("关闭图片参数"))
        }
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(usesFlatStyle ? 0 : 0.22), lineWidth: 1))
        .shadow(color: .black.opacity(usesFlatStyle ? 0 : 0.3), radius: 14, x: 0, y: 6)
        .frame(maxWidth: 260, alignment: .leading)
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

private struct UpdatePromptView: View {
    @ObservedObject private var language = LanguageSettings.shared
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
                        Text(L10n.text("忽略"))
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
            return L10n.text("下载中...")
        case .failed:
            return L10n.text("重试")
        default:
            return L10n.text("更新")
        }
    }

    private func message(for update: GitHubRelease) -> String {
        if updateChecker.status == .failed {
            return L10n.text("下载失败")
        }
        return L10n.text("发现新版本 %1$@", String(describing: update.version.displayString))
    }
}
