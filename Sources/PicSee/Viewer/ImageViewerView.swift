import AppKit
import SwiftUI

struct ImageViewerView: View {
    @ObservedObject var viewModel: ImageViewerViewModel
    let updateChecker: UpdateChecker?
    let onTitleBarVisibilityChanged: (Bool) -> Void
    let onFixedWindowChanged: (Bool) -> Void
    @State private var titleBarVisible = ViewerTitleBarPreference.isVisible()
    @State private var fileInfoVisible = UserDefaults.standard.object(forKey: "PicSee.FileInfoVisible") as? Bool ?? true
    @State private var fixedWindowEnabled = WindowFramePreference.isFixedEnabled()
    private let hudPadding: CGFloat = 12

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            if let image = viewModel.image {
                ImageCanvasView(
                    image: image,
                    imageURL: viewModel.currentURL,
                    zoomScale: $viewModel.zoomScale,
                    panOffset: $viewModel.panOffset,
                    onPrevious: viewModel.navigateToPrevious,
                    onNext: viewModel.navigateToNext,
                    onReset: viewModel.resetViewTransform,
                    onClose: { NSApp.terminate(nil) },
                    onDisplayScaleChanged: {
                        if abs(viewModel.displayScale - $0) > 0.0001 {
                            viewModel.displayScale = $0
                        }
                    },
                    titleBarVisible: titleBarVisible,
                    fileInfoVisible: fileInfoVisible,
                    onTitleBarVisibilityChanged: { visible in
                        titleBarVisible = visible
                        onTitleBarVisibilityChanged(visible)
                    },
                    onFileInfoVisibilityChanged: { visible in
                        fileInfoVisible = visible
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
        .task {
            if let updateChecker {
                await updateChecker.checkForUpdatesIfNeeded()
            }
        }
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
