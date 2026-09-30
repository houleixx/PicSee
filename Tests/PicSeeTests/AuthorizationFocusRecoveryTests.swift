import AppKit
import CoreServices
import Testing
@testable import PicSee

@MainActor
@Suite(.serialized)
struct AuthorizationFocusRecoveryTests {
    @Test func initialImageLayoutFinishesBeforeRecoveryOrdersFront() async {
        _ = NSApplication.shared
        let scheduler = PendingAuthorizationRestoration()
        let manager = WindowManager(authorizationRestorationScheduler: scheduler.schedule)
        let window = AuthorizationTestWindow()
        window.initialLayoutFinished = false
        manager.debugRestoreViewerAfterFolderConsent(window)
        // Image loading publishes completion before scheduling its initial
        // window sizing, just as the view model and image observer do.
        DispatchQueue.main.async { window.initialLayoutFinished = true }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(window.frontOrderCount == 0)
        scheduler.finishSettling()
        #expect(window.frontOrderCount == 1)
        #expect(!window.orderedBeforeInitialLayout)
    }

    @Test func repeatedConsentCompletionsCoalesceBeforeOrderingFront() async {
        _ = NSApplication.shared
        let scheduler = PendingAuthorizationRestoration()
        let manager = WindowManager(authorizationRestorationScheduler: scheduler.schedule)
        let window = AuthorizationTestWindow()
        manager.debugRestoreViewerAfterFolderConsent(window)
        manager.debugRestoreViewerAfterFolderConsent(window)
        #expect(window.frontOrderCount == 0, "Do not reorder while the system dialog is still being dismissed")
        scheduler.finishSettling()
        #expect(window.frontOrderCount == 1)
    }

    @Test func minimizingBeforeDeferredRecoveryCancelsFrontOrdering() async {
        _ = NSApplication.shared
        let scheduler = PendingAuthorizationRestoration()
        let manager = WindowManager(authorizationRestorationScheduler: scheduler.schedule)
        let window = AuthorizationTestWindow()
        manager.debugRestoreViewerAfterFolderConsent(window)
        window.simulatedMinimized = true
        scheduler.finishSettling()
        #expect(window.frontOrderCount == 0)
    }

    @Test func folderConsentOrdersViewerFrontOnlyOnce() async {
        _ = NSApplication.shared
        let scheduler = PendingAuthorizationRestoration()
        let manager = WindowManager(authorizationRestorationScheduler: scheduler.schedule)
        let window = AuthorizationTestWindow()
        manager.debugRestoreViewerAfterFolderConsent(window)
        scheduler.finishSettling()
        #expect(window.frontOrderCount == 1, "Permission recovery must not repeatedly reorder the viewer")
    }

    @Test(arguments: ["com.apple.UserNotificationCenter", "com.apple.SecurityAgent"])
    func folderConsentRestoresViewerWhenFileAccessResumes(agent: String) {
        _ = NSApplication.shared
        let window = AuthorizationTestWindow()
        var restored: [NSWindow] = []
        let recovery = ViewerAuthorizationFocusRecovery { restored.append($0) }
        recovery.setFileAccessPending(true, for: window)
        recovery.applicationActivated(bundleIdentifier: agent)
        // Dismissing the system dialog can first hand activation back to Finder.
        recovery.applicationActivated(bundleIdentifier: "com.apple.finder")
        recovery.setFileAccessPending(true, for: window)
        #expect(restored.isEmpty)
        recovery.setFileAccessPending(false, for: window)
        #expect(restored.count == 1)
        #expect(restored.first === window)
        recovery.setFileAccessPending(false, for: window)
        #expect(restored.count == 1)
    }

    @Test func ordinaryFileLoadingAndManualApplicationSwitchDoNotReclaimFocus() {
        _ = NSApplication.shared
        let window = AuthorizationTestWindow()
        var restores = 0
        let recovery = ViewerAuthorizationFocusRecovery { _ in restores += 1 }
        recovery.setFileAccessPending(true, for: window)
        recovery.setFileAccessPending(false, for: window)
        #expect(restores == 0)
        recovery.setFileAccessPending(true, for: window)
        recovery.applicationActivated(bundleIdentifier: "com.apple.UserNotificationCenter")
        recovery.applicationActivated(bundleIdentifier: "com.apple.Safari")
        recovery.setFileAccessPending(false, for: window)
        #expect(restores == 0)
    }

    @Test func folderConsentDoesNotRaiseClosedOrMinimizedViewer() {
        _ = NSApplication.shared
        let window = AuthorizationTestWindow()
        var restores = 0
        let recovery = ViewerAuthorizationFocusRecovery { _ in restores += 1 }
        recovery.setFileAccessPending(true, for: window)
        recovery.applicationActivated(bundleIdentifier: "com.apple.UserNotificationCenter")
        window.simulatedVisible = false
        recovery.setFileAccessPending(false, for: window)
        window.simulatedVisible = true
        recovery.setFileAccessPending(true, for: window)
        recovery.applicationActivated(bundleIdentifier: "com.apple.UserNotificationCenter")
        window.simulatedMinimized = true
        recovery.setFileAccessPending(false, for: window)
        #expect(restores == 0)
    }

    @Test(arguments: [OSStatus(noErr), OSStatus(errAEEventNotPermitted)])
    func completingInteractiveConsentRestoresTheRequestingWindow(response: OSStatus) async {
        _ = NSApplication.shared
        let window = AuthorizationTestWindow()
        var restored: [NSWindow] = []
        let recovery = ViewerAuthorizationFocusRecovery { restored.append($0) }
        let check = AuthorizationCheckRecorder(initial: OSStatus(errAEEventWouldRequireUserConsent), response: response)

        let allowed = await FinderFolderOrderProvider.requestPermission(
            check: { await check.check($0) },
            onPromptWillBegin: { recovery.begin(for: window) },
            onPromptFinished: { recovery.finish() }
        )

        #expect(allowed == (response == noErr))
        #expect(await check.requests == [false, true])
        #expect(restored.count == 1, "Closing the consent dialog must return focus to the requesting viewer")
        #expect(restored.first === window)
        recovery.finish()
        #expect(restored.count == 1, "A completed prompt must not keep reclaiming focus")
    }

    @Test(arguments: [OSStatus(noErr), OSStatus(errAEEventNotPermitted), OSStatus(procNotFound)])
    func decidedPermissionOrUnavailableFinderDoesNotRestoreFocus(status: OSStatus) async {
        var promptCallbacks = 0
        let check = AuthorizationCheckRecorder(initial: status, response: noErr)
        let allowed = await FinderFolderOrderProvider.requestPermission(
            check: { await check.check($0) },
            onPromptWillBegin: { promptCallbacks += 1 },
            onPromptFinished: { promptCallbacks += 1 }
        )
        #expect(allowed == (status == noErr))
        #expect(await check.requests == [false])
        #expect(promptCallbacks == 0)
    }

    @Test func closedWindowIsNotRestoredWhenConsentFinishes() async {
        _ = NSApplication.shared
        let window = AuthorizationTestWindow()
        var restores = 0
        let recovery = ViewerAuthorizationFocusRecovery { _ in restores += 1 }
        _ = await FinderFolderOrderProvider.requestPermission(
            check: { askUser in
                if askUser { await MainActor.run { window.simulatedVisible = false } }
                return askUser ? noErr : OSStatus(errAEEventWouldRequireUserConsent)
            },
            onPromptWillBegin: { recovery.begin(for: window) },
            onPromptFinished: { recovery.finish() }
        )
        #expect(restores == 0)
    }

    @Test func minimizedWindowOrDifferentSpaceIsNotRestored() {
        _ = NSApplication.shared
        let window = AuthorizationTestWindow()
        var restores = 0
        let recovery = ViewerAuthorizationFocusRecovery { _ in restores += 1 }
        recovery.begin(for: window)
        window.simulatedMinimized = true
        recovery.finish()
        window.simulatedMinimized = false
        recovery.begin(for: window)
        window.simulatedOnActiveSpace = false
        recovery.finish()
        #expect(restores == 0)
    }

    @Test func aWindowThatWasNotVisibleBeforePromptIsNotRaisedLater() {
        _ = NSApplication.shared
        let window = AuthorizationTestWindow()
        var restores = 0
        let recovery = ViewerAuthorizationFocusRecovery { _ in restores += 1 }
        window.simulatedVisible = false
        recovery.begin(for: window)
        window.simulatedVisible = true
        recovery.finish()
        #expect(restores == 0)
    }

    @Test func cancelledConsentDoesNotReclaimFocus() async {
        let prompt = PendingAuthorizationResponse()
        var completions = 0
        let task = Task {
            await FinderFolderOrderProvider.requestPermission(
                check: { askUser in
                    askUser ? await prompt.waitForResponse() : OSStatus(errAEEventWouldRequireUserConsent)
                },
                onPromptFinished: { completions += 1 }
            )
        }
        await prompt.waitUntilPrompting()
        task.cancel()
        await prompt.respond()
        #expect(await task.value == false)
        #expect(completions == 0)
    }
}

@MainActor
private final class PendingAuthorizationRestoration {
    private var actions: [@MainActor @Sendable () -> Void] = []

    func schedule(_ action: @escaping @MainActor @Sendable () -> Void) { actions.append(action) }

    func finishSettling() {
        let pending = actions
        actions.removeAll()
        for action in pending { action() }
    }
}

@MainActor
private final class AuthorizationTestWindow: NSWindow {
    var frontOrderCount = 0
    var initialLayoutFinished = true
    var orderedBeforeInitialLayout = false
    var simulatedVisible = true
    var simulatedMinimized = false
    var simulatedOnActiveSpace = true
    override var isVisible: Bool { simulatedVisible }
    override var isMiniaturized: Bool { simulatedMinimized }
    override var isOnActiveSpace: Bool { simulatedOnActiveSpace }
    override func orderFrontRegardless() { frontOrderCount += 1 }
    override func makeKey() {}
    override func makeKeyAndOrderFront(_ sender: Any?) {
        frontOrderCount += 1
        if !initialLayoutFinished { orderedBeforeInitialLayout = true }
    }
}

private actor AuthorizationCheckRecorder {
    private let initial: OSStatus
    private let response: OSStatus
    private(set) var requests: [Bool] = []

    init(initial: OSStatus, response: OSStatus) {
        self.initial = initial
        self.response = response
    }

    func check(_ askUser: Bool) -> OSStatus {
        requests.append(askUser)
        return askUser ? response : initial
    }
}

private actor PendingAuthorizationResponse {
    private var response: CheckedContinuation<OSStatus, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func waitForResponse() async -> OSStatus {
        await withCheckedContinuation {
            response = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilPrompting() async {
        guard response == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func respond() {
        response?.resume(returning: noErr)
        response = nil
    }
}
