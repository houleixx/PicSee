import AppKit
import Testing
@testable import PicSee

@Suite(.serialized)
@MainActor
struct ImageCanvasAnimationPreferenceTests {
    private func canvas(defaults: UserDefaults) -> CanvasNSView {
        let view = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                                backend: .vision, defaults: defaults)
        view.motionPreference = { false }
        view.image = NSImage(size: NSSize(width: 800, height: 600))
        view.layoutSubtreeIfNeeded()
        view.navigationDirection = 1
        return view
    }

    private func waitForPreference(_ enabled: Bool, in views: [CanvasNSView]) async throws {
        for _ in 0..<200 {
            if views.allSatisfy({ $0.debugNavigationAnimationEnabled == enabled }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Open canvases did not receive the animation preference")
    }

    @Test
    func defaultsToEnabledAndPersistsAcrossReopening() throws {
        let suite = "PicSee.NavigationAnimationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        #expect(preferences.snapshot.imageNavigationAnimationEnabled)
        preferences.set(\.imageNavigationAnimationEnabled, to: false)
        let reopened = ViewerPreferences(defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(!reopened.snapshot.imageNavigationAnimationEnabled)
        let view = canvas(defaults: defaults)
        view.image = NSImage(size: NSSize(width: 600, height: 800))
        view.layoutSubtreeIfNeeded()
        #expect(view.debugMotionLayer?.animationKeys() == nil)
        #expect(view.debugOutgoingImage == nil)
    }

    @Test(arguments: [false, true])
    func disablingCancelsPendingOrPlayingTransitionAndUpdatesAllCanvases(playing: Bool) async throws {
        let suite = "PicSee.NavigationAnimationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        let views = [canvas(defaults: defaults), canvas(defaults: defaults)]
        for view in views {
            view.image = NSImage(size: NSSize(width: 600, height: 800))
            if playing { view.layoutSubtreeIfNeeded() }
            #expect(view.debugOutgoingImage != nil)
        }
        preferences.set(\.imageNavigationAnimationEnabled, to: false)
        try await waitForPreference(false, in: views)
        for view in views {
            view.layoutSubtreeIfNeeded()
            #expect(view.debugOutgoingImage == nil)
            #expect(view.debugOutgoingLayer?.animationKeys() == nil)
            #expect(view.debugMotionLayer?.animationKeys() == nil)
            view.image = NSImage(size: NSSize(width: 1000, height: 500))
            view.layoutSubtreeIfNeeded()
            #expect(view.debugOutgoingImage == nil)
            #expect(view.debugMotionLayer?.animationKeys() == nil)
        }
        preferences.set(\.imageNavigationAnimationEnabled, to: true)
        try await waitForPreference(true, in: views)
        for view in views {
            view.image = NSImage(size: NSSize(width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            #expect(view.debugMotionLayer?.animation(forKey: "PicSee.NavigationAnimation") != nil)
        }
    }

    @Test
    func disablingNavigationKeepsZoomAndRotationAnimations() async throws {
        let suite = "PicSee.NavigationAnimationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        let view = canvas(defaults: defaults)
        preferences.set(\.imageNavigationAnimationEnabled, to: false)
        try await waitForPreference(false, in: [view])
        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
        view.rotationDegrees = 90
        view.layoutSubtreeIfNeeded()
        #expect(view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation") != nil)
        #expect(view.debugHasRotationAnimation)
        #expect(view.rotationDegrees == 90)
        #expect(view.zoomScale == 1.25)
    }
}
