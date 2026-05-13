import SwiftUI

struct ImageViewerView: View {
    @ObservedObject var viewModel: ImageViewerViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Text(viewModel.currentFilename)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(32)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
