import AppKit
import CoreServices
import Testing
@testable import PicSee

@MainActor
struct AuthorizationFocusRecoveryTests {
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
private final class AuthorizationTestWindow: NSWindow {
    var simulatedVisible = true
    var simulatedMinimized = false
    var simulatedOnActiveSpace = true
    override var isVisible: Bool { simulatedVisible }
    override var isMiniaturized: Bool { simulatedMinimized }
    override var isOnActiveSpace: Bool { simulatedOnActiveSpace }
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
