import Foundation
import Testing
@testable import PicSee

struct FinderAuthorizationTests {
    @Test func deniedPermissionDoesNotRunFinderScriptOrReadDirectory() async {
        let calls = FinderCallRecorder()
        let provider = FinderFolderOrderProvider(
            { _ in
                calls.record("script")
                return "ORDERED\nfile:///tmp/photos/1.png"
            },
            directoryReader: { _ in
                calls.record("directory")
                return []
            },
            permissionRequester: { false }
        )

        let result = await provider.orderedURLs(for: URL(fileURLWithPath: "/tmp/photos"))

        #expect(result == nil)
        #expect(provider.isOrderingAvailableImmediately)
        #expect(calls.values.isEmpty, "Unauthorized scripts would start the one-second permission timeout")
    }

    @Test(.timeLimit(.minutes(1)))
    func consentCanTakeLongerThanTheSortingTimeout() async throws {
        let permission = PendingFinderPermission()
        let calls = FinderCallRecorder()
        let image = URL(fileURLWithPath: "/tmp/photos/1.png")
        let provider = FinderFolderOrderProvider(
            { source in
                calls.record("script")
                #expect(source.contains("with timeout of 1 second"))
                return "ORDERED\n\(image.absoluteString)"
            },
            directoryReader: { _ in [image] },
            permissionRequester: { await permission.request() }
        )
        let lookup = Task { await provider.orderedURLs(for: image.deletingLastPathComponent()) }
        await permission.waitUntilRequested()

        // Reproduce a person taking more than the old one-second limit to respond.
        try await Task.sleep(for: .milliseconds(1200))
        #expect(provider.isOrderingAvailableImmediately)
        #expect(calls.values.isEmpty)

        await permission.resolve(true)
        #expect(await lookup.value == [image])
        #expect(calls.values == ["script"])
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledLookupDoesNotRunScriptAfterConsent() async {
        let permission = PendingFinderPermission()
        let calls = FinderCallRecorder()
        let provider = FinderFolderOrderProvider(
            { _ in
                calls.record("script")
                return nil
            },
            permissionRequester: { await permission.request() }
        )
        let lookup = Task {
            await provider.orderedURLs(for: URL(fileURLWithPath: "/tmp/photos"))
        }
        await permission.waitUntilRequested()
        lookup.cancel()
        await permission.resolve(true)

        #expect(await lookup.value == nil)
        #expect(calls.values.isEmpty)
    }
}

private actor PendingFinderPermission {
    private var response: CheckedContinuation<Bool, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func request() async -> Bool {
        await withCheckedContinuation {
            response = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilRequested() async {
        guard response == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func resolve(_ allowed: Bool) {
        response?.resume(returning: allowed)
        response = nil
    }
}

private final class FinderCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []

    var values: [String] { lock.withLock { calls } }

    func record(_ call: String) {
        lock.withLock { calls.append(call) }
    }
}
