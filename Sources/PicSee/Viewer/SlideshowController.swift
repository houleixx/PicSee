import AppKit
import Combine
import Foundation

/// Owns one cancellable delay at a time. Loading the next image finishes before
/// the next delay starts, so slow loads never consume its viewing interval.
@MainActor
final class SlideshowController: ObservableObject {
    enum State { case stopped, playing, paused }

    static let intervals = [2, 3, 5, 10]
    static let intervalKey = "PicSee.SlideshowInterval"
    static let loopsKey = "PicSee.SlideshowLoops"

    @Published private(set) var state: State = .stopped
    @Published private(set) var isFullScreenTransitioning = false
    @Published private(set) var interval: Int
    @Published var loops: Bool {
        didSet { defaults.set(loops, forKey: Self.loopsKey) }
    }
    var isActive: Bool { state != .stopped }
    var onAdvance: (() -> Bool)?

    private let defaults: UserDefaults
    private let sleep: @MainActor (Duration) async throws -> Void
    private var delay: Task<Void, Never>?
    private var revision = 0
    private var isReady = false
    private var activityObservations: Set<AnyCancellable> = []

    init(
        defaults: UserDefaults = .standard,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.defaults = defaults
        self.sleep = sleep
        let savedInterval = defaults.integer(forKey: Self.intervalKey)
        interval = Self.intervals.contains(savedInterval) ? savedInterval : 5
        loops = defaults.object(forKey: Self.loopsKey) as? Bool ?? true
        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.pause() }
            .store(in: &activityObservations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.pause() }
            .store(in: &activityObservations)
    }

    deinit { delay?.cancel() }

    func start(ready: Bool) {
        isReady = ready
        state = .playing
        restartInterval()
    }

    func setReady(_ ready: Bool) {
        isReady = ready
        restartInterval()
    }

    func togglePause() {
        switch state {
        case .stopped: break
        case .playing: pause()
        case .paused:
            state = .playing
            restartInterval()
        }
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
        cancelDelay()
    }

    // Native full-screen reconfiguration can briefly resign the key window.
    // Keep the user's playback state, and give the image a full interval once
    // the animation finishes. Explicit pauses and app deactivation still win.
    func beginFullScreenTransition() {
        guard !isFullScreenTransitioning else { return }
        isFullScreenTransitioning = true
        cancelDelay()
    }

    func endFullScreenTransition() {
        guard isFullScreenTransitioning else { return }
        isFullScreenTransitioning = false
        restartInterval()
    }

    func pauseForWindowDeactivation() {
        guard !isFullScreenTransitioning else { return }
        pause()
    }

    func stop() {
        state = .stopped
        cancelDelay()
    }

    func setInterval(_ seconds: Int) {
        guard Self.intervals.contains(seconds), seconds != interval else { return }
        interval = seconds
        defaults.set(seconds, forKey: Self.intervalKey)
        restartInterval()
    }

    func restartInterval() {
        cancelDelay()
        guard state == .playing, isReady, !isFullScreenTransitioning else { return }
        let expectedRevision = revision
        let duration = Duration.seconds(interval)
        let sleep = sleep
        delay = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do { try await sleep(duration) } catch { return }
            guard !Task.isCancelled, let self,
                  self.revision == expectedRevision, self.state == .playing else { return }
            guard self.onAdvance?() == true else {
                self.stop()
                return
            }
            self.restartInterval()
        }
    }

    private func cancelDelay() {
        revision += 1
        delay?.cancel()
        delay = nil
    }
}
