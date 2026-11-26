import SwiftUI

struct UpdateErrorDetails: View {
    let message: String
    private let maximumHeight: CGFloat = 96

    var body: some View {
        ViewThatFits(in: .vertical) {
            messageText
            ScrollView {
                messageText
            }
            .frame(height: maximumHeight)
        }
        .frame(maxHeight: maximumHeight, alignment: .topLeading)
    }

    private var messageText: some View {
        Text(verbatim: message)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
