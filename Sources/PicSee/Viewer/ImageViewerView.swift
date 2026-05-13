import SwiftUI

struct ImageViewerView: View {
    @ObservedObject var viewModel: ImageViewerViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = viewModel.image {
                ImageCanvasView(
                    image: image,
                    zoomScale: $viewModel.zoomScale,
                    panOffset: $viewModel.panOffset,
                    onPrevious: viewModel.navigateToPrevious,
                    onNext: viewModel.navigateToNext,
                    onReset: viewModel.resetViewTransform
                )
            } else {
                VStack(spacing: 12) {
                    Text("Cannot Open Image")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(viewModel.errorMessage ?? "PicSee could not open this file.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(viewModel.currentFilename)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(32)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
