import CoreGraphics
import Foundation
import Testing
@testable import PicSee

struct ImageCloseGestureTests {
    @Test(arguments: [16, 20, 24])
    func minimumSizedGestureCloses(right: Int) {
        var gesture = ImageCloseGesture(start: CGPoint(x: 100, y: 200))
        for down in 1...10 {
            gesture.move(to: CGPoint(x: 100, y: 200 - down))
        }
        for distance in 1...right {
            gesture.move(to: CGPoint(x: 100 + distance, y: 190))
        }
        #expect(gesture.result == .close)
    }

    @Test(arguments: [CGFloat(1), CGFloat(2)])
    func smallRoundedGestureFromScreenshotCloses(displayScale: CGFloat) {
        let screenPoints: [CGPoint] = [
            CGPoint(x: 515, y: 195), CGPoint(x: 516, y: 202),
            CGPoint(x: 519, y: 210), CGPoint(x: 524, y: 217),
            CGPoint(x: 531, y: 224), CGPoint(x: 541, y: 230),
            CGPoint(x: 554, y: 233), CGPoint(x: 570, y: 233)
        ]
        var gesture = ImageCloseGesture(start: CGPoint(x: 515 / displayScale, y: -195 / displayScale))
        for (previous, point) in zip(screenPoints, screenPoints.dropFirst()) {
            let steps = Int(ceil(max(abs(point.x - previous.x), abs(point.y - previous.y))))
            for step in 1...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                gesture.move(to: CGPoint(x: (previous.x + (point.x - previous.x) * fraction) / displayScale,
                    y: -(previous.y + (point.y - previous.y) * fraction) / displayScale))
            }
        }
        #expect(gesture.result == .close)
    }

    @Test(arguments: [1, 2, 4, 8, 16])
    func diagonalSwipeDoesNotClose(step: Int) {
        var gesture = ImageCloseGesture(start: CGPoint(x: 100, y: 200))
        for distance in stride(from: step, through: 80, by: step) {
            gesture.move(to: CGPoint(x: 100 + distance, y: 200 - distance))
        }
        #expect(gesture.result == .cancelled)
    }

    @Test(arguments: [10, 12, 16, 20, 24, 28])
    func shortDownwardLegCanClose(down: Int) {
        var gesture = ImageCloseGesture(start: CGPoint(x: 100, y: 200))
        for distance in 1...down {
            gesture.move(to: CGPoint(x: 100, y: 200 - distance))
        }
        for distance in 1...64 {
            gesture.move(to: CGPoint(x: 100 + distance, y: 200 - down))
        }
        #expect(gesture.result == .close)
    }

    @Test(arguments: [1, 2, 4, 8, 16])
    func denseMouseEventsKeepHorizontalDistance(step: Int) {
        var gesture = ImageCloseGesture(start: CGPoint(x: 100, y: 200))
        for down in stride(from: step, through: 48, by: step) {
            gesture.move(to: CGPoint(x: 100, y: 200 - down))
        }
        for right in stride(from: step, through: 80, by: step) {
            gesture.move(to: CGPoint(x: 100 + right, y: 152))
        }
        #expect(gesture.result == .close)
    }

    @Test func roundedTurnFromReportedGestureCloses() {
        // Screenshot coordinates, converted to AppKit's upward Y axis.
        let screenPoints: [CGPoint] = [
            CGPoint(x: 515, y: 173), CGPoint(x: 515, y: 193),
            CGPoint(x: 520, y: 209), CGPoint(x: 526, y: 224),
            CGPoint(x: 536, y: 236), CGPoint(x: 550, y: 244),
            CGPoint(x: 568, y: 249), CGPoint(x: 590, y: 252),
            CGPoint(x: 630, y: 252), CGPoint(x: 692, y: 253)
        ]
        var gesture = ImageCloseGesture(start: CGPoint(x: 515, y: -173))
        for (previous, point) in zip(screenPoints, screenPoints.dropFirst()) {
            // A real mouse generates many small events along the visible path.
            let steps = Int(ceil(max(abs(point.x - previous.x), abs(point.y - previous.y)) / 4))
            for step in 1...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                gesture.move(to: CGPoint(x: previous.x + (point.x - previous.x) * fraction,
                    y: -(previous.y + (point.y - previous.y) * fraction)))
            }
        }
        #expect(gesture.result == .close)
    }

    @Test(arguments: [
        ([CGPoint](), ImageCloseGesture.Result.menu),
        ([CGPoint(x: 103, y: 198), CGPoint(x: 100, y: 200)], .menu),
        ([CGPoint(x: 100, y: 160), CGPoint(x: 140, y: 160)], .close),
        ([CGPoint(x: 104, y: 164), CGPoint(x: 143, y: 158)], .close),
        ([CGPoint(x: 100, y: 168), CGPoint(x: 100, y: 140), CGPoint(x: 100, y: 100), CGPoint(x: 140, y: 100)], .close),
        ([CGPoint(x: 100, y: 100)], .cancelled),
        ([CGPoint(x: 150, y: 200)], .cancelled),
        ([CGPoint(x: 130, y: 170), CGPoint(x: 160, y: 140)], .cancelled),
        ([CGPoint(x: 100, y: 160), CGPoint(x: 112, y: 160)], .cancelled),
        ([CGPoint(x: 100, y: 160), CGPoint(x: 140, y: 160), CGPoint(x: 115, y: 160)], .cancelled),
        ([CGPoint(x: 100, y: 160), CGPoint(x: 140, y: 160), CGPoint(x: 140, y: 190)], .cancelled),
        ([CGPoint(x: 100, y: 160), CGPoint(x: 140, y: 160), CGPoint(x: 140, y: 130)], .cancelled),
        ([CGPoint(x: 100, y: 191), CGPoint(x: 140, y: 191)], .cancelled)
    ])
    func recognizesOnlyDownThenRight(input: ([CGPoint], ImageCloseGesture.Result)) {
        var gesture = ImageCloseGesture(start: CGPoint(x: 100, y: 200))
        for point in input.0 { gesture.move(to: point) }
        #expect(gesture.result == input.1)
    }

    @Test func cancelledGestureCannotBecomeReadyAgain() {
        var gesture = ImageCloseGesture(start: CGPoint(x: 100, y: 200))
        gesture.move(to: CGPoint(x: 100, y: 160))
        gesture.move(to: CGPoint(x: 140, y: 160))
        #expect(gesture.isReady)
        gesture.cancel()
        gesture.move(to: CGPoint(x: 180, y: 160))
        #expect(!gesture.isReady)
        #expect(gesture.result == .cancelled)
    }

    @Test func gestureIsDisabledByDefaultAndPreferencePersists() throws {
        let suite = "PicSee-GesturePreference-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!ImageCloseGesturePreference.isEnabled(in: defaults))
        ImageCloseGesturePreference.setEnabled(true, in: defaults)
        #expect(ViewerPreferencesSnapshot(defaults: defaults).rightMouseCloseGestureEnabled)
        ImageCloseGesturePreference.setEnabled(false, in: defaults)
        #expect(!ViewerPreferencesSnapshot(defaults: defaults).rightMouseCloseGestureEnabled)
    }
}
