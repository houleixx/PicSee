import AppKit
import SwiftUI
import XCTest
@testable import PicSee

@MainActor
final class ImageCanvasAnimationTests: XCTestCase {
    private func canvas() -> CanvasNSView {
        let view = CanvasNSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), backend: .vision)
        view.motionPreference = { false }
        view.image = NSImage(size: NSSize(width: 1000, height: 500))
        view.zoomScale = 2
        view.panOffset = CGSize(width: -100, height: 0)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testRepeatedToolbarZoomAccumulatesTargetsWithoutQueuing() {
        let view = canvas()
        for id in 1...4 {
            view.applyToolbarZoom(request: ImageZoomRequest(id: id, multiplier: 1.25))
        }
        XCTAssertEqual(view.zoomScale, 2 * pow(1.25, 4), accuracy: 0.001)
        XCTAssertEqual(view.panOffset.width, -100 * pow(1.25, 4), accuracy: 0.001)
        XCTAssertEqual(view.debugMotionLayer?.animationKeys(), ["PicSee.ZoomAnimation"])
        let animation = view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation")
        XCTAssertEqual(animation?.duration, 0.18)
        // Re-delivery by SwiftUI must not apply the same request twice.
        view.applyToolbarZoom(request: ImageZoomRequest(id: 4, multiplier: 1.25))
        XCTAssertEqual(view.zoomScale, 2 * pow(1.25, 4), accuracy: 0.001)
    }

    func testFitAndActualSizeCommitExactTargetsAndAnimateTogether() {
        let view = canvas()
        view.updateTransform(zoom: 1, pan: .zero, rotation: 0, animationID: 1, imageChanged: false)
        XCTAssertEqual(view.zoomScale, 1)
        XCTAssertEqual(view.panOffset, .zero)
        XCTAssertEqual(view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation")?.duration, 0.20)
        view.updateTransform(zoom: 2.5, pan: .zero, rotation: 0, animationID: 2, imageChanged: false)
        XCTAssertEqual(view.zoomScale, 2.5)
        XCTAssertEqual(view.panOffset, .zero)
        XCTAssertEqual(view.debugMotionLayer?.animationKeys()?.count, 1)
    }

    func testInterruptCommitsPresentationAndRemovesTween() {
        let view = canvas()
        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
        let visual = view.debugVisualTransform
        var reportedZoom: CGFloat?
        var reportedPan: CGSize?
        view.onZoomChanged = { reportedZoom = $0 }
        view.onPanChanged = { reportedPan = $0 }
        view.debugInterruptMotion()
        XCTAssertEqual(view.zoomScale, visual.zoomScale, accuracy: 0.001)
        XCTAssertEqual(view.panOffset.width, visual.panOffset.width, accuracy: 0.001)
        XCTAssertEqual(reportedZoom, view.zoomScale)
        XCTAssertEqual(reportedPan, view.panOffset)
        XCTAssertNil(view.debugMotionLayer?.animationKeys())
    }

    func testToolbarZoomRemainsVisibleThroughSwiftUIUpdates() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/ocr-test.png")
        let model = ImageViewerViewModel(imageURL: url)
        let host = NSHostingView(rootView: ImageViewerView(viewModel: model, updateChecker: nil,
            onTitleBarVisibilityChanged: { _ in }, onFixedWindowChanged: { _ in }, onRequestDeletion: {}))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        func findCanvas(_ view: NSView) -> CanvasNSView? {
            if let canvas = view as? CanvasNSView { return canvas }
            return view.subviews.lazy.compactMap { findCanvas($0) }.first
        }
        let canvas = try XCTUnwrap(findCanvas(host))
        canvas.motionPreference = { false }
        func clickZoomButton(zoomIn: Bool = true) throws {
            // Share toolbar metrics so spacing changes do not silently turn this
            // mouse-event regression into clicks on empty space.
            let buttonIndex: CGFloat = zoomIn ? 3 : 2
            let x = host.bounds.midX - ViewerToolbarMetrics.viewerWidth / 2
                + ViewerToolbarMetrics.horizontalPadding + ViewerToolbarMetrics.buttonSize / 2
                + buttonIndex * (ViewerToolbarMetrics.buttonSize + ViewerToolbarMetrics.spacing)
            let point = CGPoint(x: x, y: 40)
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                NSApp.postEvent(event, atStart: true)
                let queued = try XCTUnwrap(NSApp.nextEvent(matching: NSEvent.EventTypeMask(rawValue: 1 << type.rawValue),
                    until: Date().addingTimeInterval(0.1), inMode: .default, dequeue: true))
                NSApp.sendEvent(queued)
            }
        }
        try clickZoomButton()
        RunLoop.current.run(until: Date().addingTimeInterval(0.055))
        XCTAssertEqual(model.zoomScale, 1.25, accuracy: 0.001)
        XCTAssertNotNil(canvas.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation"))
        XCTAssertGreaterThan(canvas.debugVisualTransform.zoomScale, 1.001)
        XCTAssertLessThan(canvas.debugVisualTransform.zoomScale, 1.249,
                          "Toolbar zoom must still be visibly between start and target after SwiftUI updates")
        var previousVisual = canvas.debugVisualTransform.zoomScale
        for click in 2...4 {
            try clickZoomButton()
            for _ in 0..<5 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                let visual = canvas.debugVisualTransform.zoomScale
                XCTAssertGreaterThanOrEqual(visual + 0.002, previousVisual,
                    "Repeated zoom-in clicks must never briefly shrink the image")
                previousVisual = visual
            }
            XCTAssertEqual(model.zoomScale, pow(1.25, CGFloat(click)), accuracy: 0.001,
                "A toolbar mouse-down must not cancel the previous target")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        previousVisual = canvas.debugVisualTransform.zoomScale
        for click in 1...4 {
            try clickZoomButton(zoomIn: false)
            for _ in 0..<5 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                let visual = canvas.debugVisualTransform.zoomScale
                XCTAssertLessThanOrEqual(visual - 0.002, previousVisual,
                    "Repeated zoom-out clicks must never briefly enlarge the image")
                previousVisual = visual
            }
            XCTAssertEqual(model.zoomScale, pow(1.25, CGFloat(4 - click)), accuracy: 0.001)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        for zoomIn in [true, false, true, false] {
            let before = canvas.debugVisualTransform.zoomScale
            let target = model.zoomScale * (zoomIn ? 1.25 : 0.8)
            try clickZoomButton(zoomIn: zoomIn)
            for _ in 0..<5 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                let visual = canvas.debugVisualTransform.zoomScale
                XCTAssertGreaterThanOrEqual(visual, min(before, target) - 0.01)
                XCTAssertLessThanOrEqual(visual, max(before, target) + 0.01)
            }
            XCTAssertEqual(model.zoomScale, target, accuracy: 0.001)
        }
    }

    func testRepeatedZoomPreservesSpeedAtTakeover() throws {
        for multiplier: CGFloat in [1.25, 0.8] {
            let view = canvas()
            let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            CATransaction.flush()
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: multiplier))
            CATransaction.flush()
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
            let visual = view.debugVisualTransform.zoomScale
            let delta = 2 * (multiplier - 1)
            let progress = (visual - 2) / delta
            XCTAssertGreaterThan(progress, 0.01)
            XCTAssertLessThan(progress, 0.99)
            // Initial easeInEaseOut: invert y(t) = 3t² - 2t³ at the displayed position.
            var low: CGFloat = 0
            var high: CGFloat = 1
            for _ in 0..<24 {
                let t = (low + high) / 2
                if t * t * (3 - 2 * t) < progress { low = t } else { high = t }
            }
            let t = (low + high) / 2
            let dx = 3 * (0.42 * (1 - t) * (1 - t) + 0.32 * (1 - t) * t + 0.42 * t * t)
            let expectedSpeed = delta / 0.18 * (6 * t * (1 - t)) / dx
            view.applyToolbarZoom(request: ImageZoomRequest(id: 2, multiplier: multiplier))
            let animation = try XCTUnwrap(view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation") as? CABasicAnimation)
            let timing = try XCTUnwrap(animation.timingFunction)
            var control: [Float] = [0, 0]
            timing.getControlPoint(at: 1, values: &control)
            let incomingSpeed = (view.zoomScale - visual) / animation.duration * CGFloat(control[1] / control[0])
            XCTAssertEqual(incomingSpeed, expectedSpeed, accuracy: 0.03,
                "A repeated click must inherit the visible zoom speed instead of braking to zero")
            // Another request before the next frame must preserve that inherited speed too.
            view.applyToolbarZoom(request: ImageZoomRequest(id: 3, multiplier: multiplier))
            let replacement = try XCTUnwrap(view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation") as? CABasicAnimation)
            replacement.timingFunction?.getControlPoint(at: 1, values: &control)
            let replacementSpeed = (view.zoomScale - visual) / replacement.duration * CGFloat(control[1] / control[0])
            XCTAssertEqual(replacementSpeed, expectedSpeed, accuracy: 0.03)
            XCTAssertTrue((0...1).contains(control[1]), "The continuation must not overshoot its new target")
            XCTAssertEqual(view.debugMotionLayer?.animationKeys(), ["PicSee.ZoomAnimation"])

            // A target in the opposite direction must not carry momentum away from it.
            view.applyToolbarZoom(request: ImageZoomRequest(id: 4, multiplier: multiplier > 1 ? 0.1 : 10))
            let reversed = try XCTUnwrap(view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation") as? CABasicAnimation)
            reversed.timingFunction?.getControlPoint(at: 1, values: &control)
            XCTAssertEqual(control[1], 0)
        }
    }

    func testRapidZoomRetargetBeforeNextFramePreservesVisualScale() throws {
        let view = canvas()
        let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.045))
        let before = view.debugVisualTransform
        // Both requests arrive before Core Animation has presented the replacement.
        view.applyToolbarZoom(request: ImageZoomRequest(id: 2, multiplier: 1.25))
        view.applyToolbarZoom(request: ImageZoomRequest(id: 3, multiplier: 0.8))
        let animation = try XCTUnwrap(view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation") as? CABasicAnimation)
        let from = try XCTUnwrap(animation.fromValue as? CATransform3D)
        XCTAssertEqual(from.m11 * view.zoomScale, before.zoomScale, accuracy: 0.03,
                       "Retargeting within one frame must not jump by a zoom step")
        XCTAssertEqual(view.panOffset.width * from.m11 + from.m41, before.panOffset.width, accuracy: 1.5)
    }

    func testRenderedZoomAndRotationAreTakenOverFromPresentation() throws {
        let view = canvas()
        let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))

        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 2))
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let visual = view.debugVisualTransform
        XCTAssertGreaterThan(visual.zoomScale, 2)
        XCTAssertLessThan(visual.zoomScale, 4)
        view.applyToolbarZoom(request: ImageZoomRequest(id: 2, multiplier: 1.25))
        let animation = try XCTUnwrap(view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation") as? CABasicAnimation)
        let start = try XCTUnwrap(animation.fromValue as? CATransform3D)
        XCTAssertEqual(start.m11 * view.zoomScale, visual.zoomScale, accuracy: 0.05)
        view.debugInterruptMotion()

        view.rotationDegrees = 90
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let visibleAngle = try XCTUnwrap(view.debugRotationLayer?.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat)
        view.rotationDegrees = 180
        view.layoutSubtreeIfNeeded()
        let rotation = try XCTUnwrap(view.debugRotationLayer?.animation(forKey: "PicSee.RotationAnimation") as? CABasicAnimation)
        let fromAngle = try XCTUnwrap(rotation.fromValue as? CGFloat)
        XCTAssertEqual(sin(fromAngle), sin(visibleAngle), accuracy: 0.1)
        XCTAssertEqual(cos(fromAngle), cos(visibleAngle), accuracy: 0.1)
    }

    func testWheelAndPinchInterruptAnimationAndApplyImmediately() {
        for isPinch in [false, true] {
            let view = canvas()
            view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
            let before = view.debugVisualTransform.zoomScale
            let event = ContinuousZoomEvent()
            if isPinch {
                view.magnify(with: event)
            } else {
                view.scrollWheel(with: event)
            }
            let multiplier: CGFloat = isPinch ? 1.1 : exp(0.018)
            XCTAssertEqual(view.zoomScale, before * multiplier, accuracy: 0.001)
            XCTAssertNil(view.debugMotionLayer?.animationKeys())
        }
    }

    func testMouseDownAndDragInterruptFitWithoutStartingAnotherAnimation() throws {
        let view = canvas()
        view.updateTransform(zoom: 1, pan: .zero, rotation: 0, animationID: 1, imageChanged: false)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 180, y: 150), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        let before = view.panOffset
        let drag = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDragged,
            location: CGPoint(x: 200, y: 150), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
        view.mouseDragged(with: drag)
        XCTAssertEqual(view.panOffset.width, before.width + 20, accuracy: 0.001)
        XCTAssertNil(view.debugMotionLayer?.animationKeys())
    }

    func testDoubleClickResetsZoomAndPanWithShortAnimation() throws {
        let view = canvas()
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 180, y: 150), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
        view.mouseDown(with: event)
        XCTAssertEqual(view.zoomScale, 1)
        XCTAssertEqual(view.panOffset, .zero)
        XCTAssertEqual(view.debugMotionLayer?.animation(forKey: "PicSee.ZoomAnimation")?.duration, 0.20)
        view.mouseDown(with: event)
        XCTAssertEqual(view.zoomScale, 1)
        XCTAssertEqual(view.debugMotionLayer?.animationKeys()?.count, 1)
    }

    func testNavigationDirectionAndFastRepeatDoNotRetainOutgoingImages() throws {
        for direction in [-1, 1] {
            let view = canvas()
            view.navigationDirection = direction
            view.image = NSImage(size: NSSize(width: 800, height: 600))
            view.layoutSubtreeIfNeeded()
            let group = try XCTUnwrap(view.debugMotionLayer?.animation(forKey: "PicSee.NavigationAnimation") as? CAAnimationGroup)
            let movement = try XCTUnwrap(group.animations?.first as? CABasicAnimation)
            XCTAssertEqual(movement.fromValue as? CGFloat, CGFloat(direction * 24))
            XCTAssertEqual(group.duration, 0.16)
            XCTAssertNotNil(view.debugOutgoingImage)
            view.image = NSImage(size: NSSize(width: 600, height: 800))
            view.layoutSubtreeIfNeeded()
            XCTAssertNil(view.debugMotionLayer?.animationKeys())
            XCTAssertNil(view.debugOutgoingImage)
            XCTAssertEqual(view.zoomScale, 1)
            XCTAssertEqual(view.panOffset, .zero)
        }
    }

    func testNavigationBurstStaysImmediateIncludingDirectionChanges() {
        let view = canvas()
        var time: CFTimeInterval = 10
        view.navigationTime = { time }
        view.navigationDirection = 1
        view.image = NSImage(size: NSSize(width: 800, height: 600))
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view.debugMotionLayer?.animation(forKey: "PicSee.NavigationAnimation"))
        for direction in [1, 1, 1, -1, -1, 1, -1] {
            time += 0.05
            view.navigationDirection = direction
            let nextImage = NSImage(size: NSSize(width: direction > 0 ? 800 : 600, height: 500))
            view.image = nextImage
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(view.image === nextImage)
            XCTAssertNil(view.debugMotionLayer?.animationKeys(),
                         "Every repeat in a burst must remain immediate, not alternate with animations")
            XCTAssertNil(view.debugOutgoingImage)
        }
    }

    func testNavigationResumesAfterPauseAndKeepsOldImageHiddenAfterFade() throws {
        let view = canvas()
        var time: CFTimeInterval = 10
        view.navigationTime = { time }
        view.navigationDirection = 1
        view.image = NSImage(size: NSSize(width: 800, height: 600))
        view.layoutSubtreeIfNeeded()
        time += 0.05
        view.image = NSImage(size: NSSize(width: 600, height: 800))
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(view.debugMotionLayer?.animationKeys())
        time += 0.23
        view.navigationDirection = -1
        let oldImage = view.image
        view.image = NSImage(size: NSSize(width: 1000, height: 300))
        view.layoutSubtreeIfNeeded()
        let incoming = try XCTUnwrap(view.debugMotionLayer?.animation(forKey: "PicSee.NavigationAnimation") as? CAAnimationGroup)
        XCTAssertEqual((incoming.animations?.first as? CABasicAnimation)?.fromValue as? CGFloat, -24)
        XCTAssertTrue(view.debugOutgoingImage === oldImage)
        let outgoing = try XCTUnwrap(view.debugOutgoingLayer)
        XCTAssertEqual(outgoing.animation(forKey: "PicSee.NavigationAnimation")?.duration, 0.10)
        outgoing.removeAllAnimations()
        XCTAssertEqual(outgoing.opacity, 0, "The old image must not reappear while awaiting cleanup")
        XCTAssertEqual(view.zoomScale, 1)
        XCTAssertEqual(view.panOffset, .zero)
        XCTAssertEqual(view.rotationDegrees, 0)
    }

    func testImageReplacementClearsOldRotationAndZoom() {
        let view = canvas()
        view.rotationDegrees = 90
        view.layoutSubtreeIfNeeded()
        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
        view.image = NSImage(size: NSSize(width: 500, height: 400))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.rotationDegrees, 0)
        XCTAssertEqual(view.zoomScale, 1)
        XCTAssertEqual(view.panOffset, .zero)
        XCTAssertFalse(view.debugHasRotationAnimation)
        XCTAssertNil(view.debugMotionLayer?.animationKeys())
    }

    func testReduceMotionDisablesZoomRotationAndNavigationTranslation() throws {
        let view = canvas()
        view.motionPreference = { true }
        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
        view.rotationDegrees = 90
        view.layoutSubtreeIfNeeded()
        XCTAssertNil(view.debugMotionLayer?.animationKeys())
        XCTAssertFalse(view.debugHasRotationAnimation)
        XCTAssertEqual(view.zoomScale, 2.5)
        view.navigationDirection = 1
        view.image = NSImage(size: NSSize(width: 800, height: 600))
        view.layoutSubtreeIfNeeded()
        let group = try XCTUnwrap(view.debugMotionLayer?.animation(forKey: "PicSee.NavigationAnimation") as? CAAnimationGroup)
        XCTAssertEqual((group.animations?.first as? CABasicAnimation)?.fromValue as? CGFloat, 0)
        XCTAssertEqual(group.duration, 0.12)
    }

    func testChangingReduceMotionStopsExistingAnimations() {
        let view = canvas()
        view.applyToolbarZoom(request: ImageZoomRequest(id: 1, multiplier: 1.25))
        view.rotationDegrees = 90
        view.layoutSubtreeIfNeeded()
        view.motionPreference = { true }
        view.debugMotionPreferenceChanged()
        XCTAssertNil(view.debugMotionLayer?.animationKeys())
        XCTAssertFalse(view.debugHasRotationAnimation)
        XCTAssertEqual(view.zoomScale, 2.5)
        XCTAssertEqual(view.rotationDegrees, 90)
    }

    func testRotationWrapsViaShortestPath() throws {
        let view = canvas()
        for target in [270, 0, 90, 180, 270, 0] {
            view.rotationDegrees = target
            view.layoutSubtreeIfNeeded()
            let animation = try XCTUnwrap(view.debugRotationLayer?.animation(forKey: "PicSee.RotationAnimation") as? CABasicAnimation)
            let start = try XCTUnwrap(animation.fromValue as? CGFloat)
            let end = try XCTUnwrap(animation.toValue as? CGFloat)
            XCTAssertLessThanOrEqual(abs(end - start), .pi + 0.001)
            XCTAssertEqual(animation.duration, 0.22)
        }
    }
}

private final class ContinuousZoomEvent: NSEvent {
    override var magnification: CGFloat { 0.1 }
    override var scrollingDeltaY: CGFloat { 1 }
    override var scrollingDeltaX: CGFloat { 0 }
    override var hasPreciseScrollingDeltas: Bool { false }
}
