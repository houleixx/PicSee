import AppKit
import SwiftUI

/// Shared with the viewer's clipboard and up-to-date tips.
struct SuccessTip: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: PhosphorImages.check)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26)
        .padding(.vertical, 28)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }
}

@MainActor
final class SuccessTipPresenter {
    static func canPresent(in window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized
    }

    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(message: String, in window: NSWindow?, completion: @escaping @MainActor () -> Void) {
        dismissal?.cancel()
        dismiss()
        let content = NSHostingView(rootView: SuccessTip(message: message))
        let size = content.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        let anchor = window.flatMap { Self.canPresent(in: $0) ? $0 : nil }
        let frame = anchor?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        if let anchor { anchor.addChildWindow(panel, ordered: .above) }
        else { panel.level = .floating }
        self.panel = panel
        panel.orderFrontRegardless()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.dismiss()
            completion()
        }
    }

    private func dismiss() {
        if let panel { panel.parent?.removeChildWindow(panel) }
        panel?.orderOut(nil)
        panel = nil
    }
}
