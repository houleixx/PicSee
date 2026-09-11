import AppKit
import XCTest
@testable import PicSee

final class ScreenshotDocumentTests: XCTestCase {
    @MainActor
    private func document(rotation: Int = 0) throws -> ScreenshotDocument {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 80, height: 40).fill()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 20).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: CGSize(width: 40, height: 20)) // Retina / non-pixel logical size
        image.addRepresentation(bitmap)
        return try ScreenshotDocument(image: image, rotationDegrees: rotation)
    }

    @MainActor
    func testCropUsesSourcePixelsAndBottomLeftCoordinates() throws {
        let document = try document()
        XCTAssertEqual(document.pixelSize, CGSize(width: 80, height: 40))
        document.state.selection = CGRect(x: 0, y: 0, width: 20, height: 10)
        let result = try document.renderedImage()
        XCTAssertEqual(ImageExporter.pixelSize(of: result), CGSize(width: 20, height: 10))
        let bitmap = try XCTUnwrap(result.representations.first as? NSBitmapImageRep)
        let color = try XCTUnwrap(bitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertLessThan(color.blueComponent, 0.1)
    }

    @MainActor
    func testRotationPreservesPixelOrientation() throws {
        let document = try document(rotation: 90)
        XCTAssertEqual(document.pixelSize, CGSize(width: 40, height: 80))
        document.state.selection = CGRect(x: 20, y: 0, width: 20, height: 40)
        let result = try document.renderedImage()
        let bitmap = try XCTUnwrap(result.representations.first as? NSBitmapImageRep)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 10, y: 20)).redComponent, 0.9)
    }

    @MainActor
    func testUndoRedoRestoresCropAndAnnotationsAndNewEditClearsRedo() throws {
        let document = try document()
        document.selectAll()
        document.checkpoint()
        document.state.annotations.append(ScreenshotAnnotation(tool: .line,
            points: [CGPoint(x: 2, y: 2), CGPoint(x: 10, y: 10)], color: .white, width: 2))
        document.undo()
        XCTAssertTrue(document.state.annotations.isEmpty)
        document.redo()
        XCTAssertEqual(document.state.annotations.count, 1)
        document.undo()
        document.undo()
        XCTAssertEqual(document.state.selection, document.bounds)
        XCTAssertTrue(document.undoStates.isEmpty)
        _ = document.resizeSelection(width: 20)
        XCTAssertTrue(document.redoStates.isEmpty)
    }

    @MainActor
    func testInitialCropIsNotUndoable() throws {
        let document = try document()
        document.checkpoint()
        let crop = CGRect(x: 5, y: 5, width: 30, height: 20)
        document.state.selection = crop
        XCTAssertTrue(document.undoStates.isEmpty)
        document.undo()
        XCTAssertEqual(document.state.selection, crop)
        _ = document.resizeSelection(width: 25)
        document.undo()
        XCTAssertEqual(document.state.selection, crop)
        XCTAssertTrue(document.undoStates.isEmpty)
    }

    @MainActor
    func testDrawingIsIncludedAndClippedToCrop() throws {
        let document = try document()
        document.state.selection = CGRect(x: 40, y: 20, width: 20, height: 10)
        document.state.annotations = [ScreenshotAnnotation(tool: .pen,
            points: [CGPoint(x: 0, y: 25), CGPoint(x: 80, y: 25)], color: .green, width: 6)]
        let result = try document.renderedImage()
        let bitmap = try XCTUnwrap(result.representations.first as? NSBitmapImageRep)
        let color = try XCTUnwrap(bitmap.colorAt(x: 10, y: 5)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.greenComponent, 0.9)
        XCTAssertEqual(bitmap.pixelsWide, 20)
        XCTAssertEqual(bitmap.pixelsHigh, 10)
    }

    @MainActor
    func testAllDrawingToolsRenderAndEraseWithoutChangingSource() throws {
        let document = try document()
        document.selectAll()
        for tool in ScreenshotTool.allCases where tool != .crop && tool != .eraser {
            document.state.annotations = [ScreenshotAnnotation(tool: tool,
                points: [CGPoint(x: 5, y: 5), CGPoint(x: 30, y: 25)], color: .white,
                width: 3, text: "截图", fontSize: 16)]
            XCTAssertNoThrow(try document.renderedImage(), tool.title)
            document.erase(at: CGPoint(x: 10, y: 10))
            XCTAssertTrue(document.state.annotations.isEmpty, tool.title)
        }
        XCTAssertEqual(ImageExporter.pixelSize(of: document.image), CGSize(width: 80, height: 40))
    }

    @MainActor
    func testEmptySelectionCannotExportAndFractionalSelectionRoundsOutward() throws {
        let document = try document()
        XCTAssertThrowsError(try document.renderedImage())
        document.state.selection = CGRect(x: 1.2, y: 2.3, width: 10.2, height: 5.2)
        XCTAssertEqual(ImageExporter.pixelSize(of: try document.renderedImage()), CGSize(width: 11, height: 6))
    }
    @MainActor
    func testCanvasUsesArrowOverToolbarAndRestoresSelectionCursor() throws {
        _ = NSApplication.shared
        let canvas = ScreenshotCanvasNSView(document: try document())
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved,
            location: CGPoint(x: 100, y: 100), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        defer { NSCursor.arrow.set() }
        canvas.mouseMoved(with: event)
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair)
        canvas.isPointerOverControls = true
        canvas.mouseMoved(with: event)
        XCTAssertEqual(NSCursor.current, NSCursor.arrow)
        // Further canvas tracking events must not overwrite the toolbar's arrow.
        canvas.mouseMoved(with: event)
        XCTAssertEqual(NSCursor.current, NSCursor.arrow)
        canvas.isPointerOverControls = false
        canvas.mouseMoved(with: event)
        XCTAssertEqual(NSCursor.current, NSCursor.crosshair)
    }

    @MainActor
    func testSelectionReadoutMatchesScreenPixelsAndStaysVisibleAtTopEdge() throws {
        let document = try document()
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        canvas.screenScale = 2
        document.state.selection = CGRect(x: 10, y: 5, width: 20, height: 10)
        XCTAssertEqual(canvas.selectionSizeText, "400 × 200 px")
        let label = try XCTUnwrap(canvas.selectionSizeLabelRect)
        XCTAssertGreaterThan(label.minY, 170)
        XCTAssertTrue(canvas.bounds.contains(label))
        document.selectAll()
        XCTAssertTrue(canvas.bounds.contains(try XCTUnwrap(canvas.selectionSizeLabelRect)))
        canvas.frame = CGRect(x: 0, y: 0, width: 440, height: 240)
        XCTAssertEqual(canvas.selectionSizeText, "800 × 400 px")
        XCTAssertTrue(canvas.bounds.contains(try XCTUnwrap(canvas.selectionSizeLabelRect)))
    }

    @MainActor
    func testCanvasSelectMoveResizeAndDraw() throws {
        let document = try document()
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440) // 10 screen points per pixel
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 20 + x * 10, y: 20 + y * 10),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        func drag(_ start: CGPoint, _ end: CGPoint) throws {
            canvas.mouseDown(with: try event(.leftMouseDown, start.x, start.y))
            canvas.mouseDragged(with: try event(.leftMouseDragged, end.x, end.y))
            canvas.mouseUp(with: try event(.leftMouseUp, end.x, end.y))
        }
        try drag(CGPoint(x: 10, y: 5), CGPoint(x: 50, y: 25))
        XCTAssertEqual(document.state.selection, CGRect(x: 10, y: 5, width: 40, height: 20))
        try drag(CGPoint(x: 30, y: 15), CGPoint(x: 35, y: 20))
        XCTAssertEqual(document.state.selection, CGRect(x: 15, y: 10, width: 40, height: 20))
        try drag(CGPoint(x: 55, y: 30), CGPoint(x: 70, y: 35))
        XCTAssertEqual(document.state.selection, CGRect(x: 15, y: 10, width: 55, height: 25))
        canvas.mouseDown(with: try event(.leftMouseDown, 5, 5))
        canvas.mouseUp(with: try event(.leftMouseUp, 5, 5))
        XCTAssertEqual(document.state.selection, CGRect(x: 15, y: 10, width: 55, height: 25))
        document.tool = .pen
        try drag(CGPoint(x: 20, y: 15), CGPoint(x: 30, y: 20))
        XCTAssertEqual(document.state.annotations.count, 1)
        document.undo()
        XCTAssertTrue(document.state.annotations.isEmpty)
    }

    @MainActor
    func testSelectionCanStartInBlankSpaceAndClipsToImage() throws {
        let document = try document()
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 480, height: 320)
        canvas.displayImageRect = CGRect(x: 200, y: 140, width: 80, height: 40)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: 200 + point.x, y: 140 + point.y), modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let cases: [(CGPoint, CGPoint, CGRect)] = [
            (CGPoint(x: -15, y: -10), CGPoint(x: 30, y: 20), CGRect(x: 0, y: 0, width: 30, height: 20)),
            (CGPoint(x: 95, y: 50), CGPoint(x: 35, y: 10), CGRect(x: 35, y: 10, width: 45, height: 30)),
            (CGPoint(x: -10, y: 50), CGPoint(x: 90, y: -10), document.bounds),
            (CGPoint(x: -15, y: 10), CGPoint(x: 30, y: 30), CGRect(x: 0, y: 10, width: 30, height: 20)),
            (CGPoint(x: 95, y: 30), CGPoint(x: 50, y: 10), CGRect(x: 50, y: 10, width: 30, height: 20))
        ]
        for (start, end, expected) in cases {
            document.state.selection = nil
            canvas.mouseDown(with: try event(.leftMouseDown, start))
            XCTAssertNil(document.state.selection)
            canvas.mouseDragged(with: try event(.leftMouseDragged, end))
            XCTAssertEqual(document.state.selection, expected, "Show the clipped selection during the drag")
            canvas.mouseUp(with: try event(.leftMouseUp, end))
            XCTAssertEqual(document.state.selection, expected)
        }
    }

    @MainActor
    func testBlankSpaceMissPreservesSelectionToolAndHistory() throws {
        let document = try document()
        let original = CGRect(x: 20, y: 10, width: 30, height: 20)
        document.state.selection = original
        document.tool = .pen
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 480, height: 320)
        canvas.displayImageRect = CGRect(x: 200, y: 140, width: 80, height: 40)
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 200 + x, y: 140 + y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        for end in [CGPoint(x: -5, y: 30), CGPoint(x: -10, y: -5)] {
            canvas.mouseDown(with: try event(.leftMouseDown, -20, -20))
            canvas.mouseDragged(with: try event(.leftMouseDragged, end.x, end.y))
            canvas.mouseUp(with: try event(.leftMouseUp, end.x, end.y))
            XCTAssertEqual(document.state.selection, original)
            XCTAssertEqual(document.tool, .pen)
            XCTAssertTrue(document.undoStates.isEmpty)
        }
        canvas.mouseDown(with: try event(.leftMouseDown, -20, -20))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 60, 35))
        canvas.mouseUp(with: try event(.leftMouseUp, 60, 35))
        XCTAssertEqual(document.state.selection, CGRect(x: 0, y: 0, width: 60, height: 35))
        XCTAssertEqual(document.tool, .crop)
        XCTAssertTrue(document.state.annotations.isEmpty)
        XCTAssertEqual(document.undoStates.count, 1)
        document.undo()
        XCTAssertEqual(document.state.selection, original)
    }

    @MainActor
    func testInlineCanvasMapsZoomedPannedImageAndReselectsWhileAnnotating() throws {
        let document = try document()
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 480, height: 320)
        canvas.displayImageRect = CGRect(x: -100, y: 30, width: 800, height: 400)
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, 0, 80))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 200, 180))
        canvas.mouseUp(with: try event(.leftMouseUp, 200, 180))
        XCTAssertEqual(document.state.selection, CGRect(x: 10, y: 5, width: 20, height: 10))
        document.tool = .pen
        canvas.mouseDown(with: try event(.leftMouseDown, 250, 200))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 400, 280))
        canvas.mouseUp(with: try event(.leftMouseUp, 400, 280))
        XCTAssertEqual(document.state.selection, CGRect(x: 35, y: 17, width: 15, height: 8))
        XCTAssertEqual(document.tool, .crop)
        XCTAssertTrue(document.state.annotations.isEmpty)
    }

    @MainActor
    func testReselectCanBeUndoneAndEscapeCancelsInlineEditor() throws {
        let document = try document()
        document.selectAll()
        document.reselect()
        XCTAssertNil(document.state.selection)
        XCTAssertEqual(document.tool, .crop)
        document.undo()
        XCTAssertEqual(document.state.selection, document.bounds)
        let canvas = ScreenshotCanvasNSView(document: document)
        var cancelled = false
        canvas.onCancel = { cancelled = true }
        canvas.cancelOperation(nil)
        XCTAssertTrue(cancelled)
    }

    @MainActor
    func testTextToolStartsInlineInputAndFocusLossCommitsOneUndoableAnnotation() throws {
        let document = try document()
        document.selectAll()
        document.tool = .text
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 120, y: 120), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: click)
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertTrue(document.state.annotations.isEmpty)
        XCTAssertEqual(field.frame.minX, 120, accuracy: 0.001)
        XCTAssertEqual(field.frame.midY, 120, accuracy: 0.001)
        XCTAssertEqual(document.pendingText?.points, [CGPoint(x: (field.frame.minX + 10 - 20) / 10,
            y: (field.frame.minY + 8 - 20) / 10)])
        field.stringValue = "中文标注 T"
        canvas.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        canvas.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertNil(document.pendingText)
        XCTAssertTrue(canvas.subviews.isEmpty)
        XCTAssertEqual(document.state.annotations.count, 1)
        XCTAssertEqual(document.state.annotations.first?.text, "中文标注 T")
        document.undo()
        XCTAssertTrue(document.state.annotations.isEmpty)
        document.redo()
        XCTAssertEqual(document.state.annotations.first?.text, "中文标注 T")
    }

    @MainActor
    func testConfirmedTextMovesOnDragAndDoubleClickReopensEditor() throws {
        let document = try document()
        document.selectAll(); document.tool = .text
        let point = CGPoint(x: 10, y: 10)
        document.beginText(at: point, displayScale: 10)
        document.pendingText?.text = "移动文字"
        document.commitPendingText()
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, clicks: Int = 1) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
        }
        let count = document.undoStates.count
        canvas.mouseDown(with: try event(.leftMouseDown, 120, 120))
        canvas.mouseUp(with: try event(.leftMouseUp, 120, 120))
        XCTAssertNil(document.pendingText)
        XCTAssertEqual(document.undoStates.count, count)
        canvas.mouseDown(with: try event(.leftMouseDown, 120, 120))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 140, 140))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 160, 150))
        canvas.mouseUp(with: try event(.leftMouseUp, 160, 150))
        XCTAssertEqual(document.state.annotations.first?.points.first, CGPoint(x: 14, y: 13))
        XCTAssertEqual(document.undoStates.count, count + 1)
        document.undo()
        XCTAssertEqual(document.state.annotations.first?.points.first, point)
        document.redo()
        canvas.mouseDown(with: try event(.leftMouseDown, 160, 150, clicks: 2))
        XCTAssertEqual(document.pendingText?.text, "移动文字")
        XCTAssertFalse(canvas.subviews.isEmpty)
        canvas.mouseDown(with: try event(.leftMouseDown, 500, 300))
        XCTAssertNil(document.pendingText, "Outside click only confirms; it must not create another input")
        XCTAssertEqual(document.state.annotations.count, 1)
    }

    @MainActor
    func testTextInputGrowsWithContentAndReturnInsertsNewline() throws {
        let document = try document()
        document.selectAll()
        document.tool = .text
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 120, y: 220), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: click)
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertLessThanOrEqual(field.frame.width, 100)
        let initialHeight = field.frame.height
        field.stringValue = "输入一段更长的文字内容"
        canvas.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertGreaterThan(field.frame.width, 80)
        let editor = NSTextView()
        editor.string = field.stringValue
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        XCTAssertTrue(canvas.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(field.stringValue.hasSuffix("\n"))
        XCTAssertNotNil(document.pendingText)
        XCTAssertTrue(document.state.annotations.isEmpty)
        XCTAssertGreaterThan(field.frame.height, initialHeight)
        field.stringValue += "第二行"
        canvas.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        canvas.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertEqual(document.state.annotations.first?.text, "输入一段更长的文字内容\n第二行")
        document.undo()
        XCTAssertTrue(document.state.annotations.isEmpty)
        document.redo()
        XCTAssertTrue(document.state.annotations.first?.text.contains("\n") == true)
    }

    @MainActor
    func testTextInputHasRoomForScaledFontWithoutNativeBezelClipping() throws {
        for fontSize: CGFloat in [16, 28, 96] {
            for zoom: CGFloat in [0.5, 1, 2] {
                let document = try document()
                document.selectAll()
                document.tool = .text
                document.fontSize = fontSize
                let canvas = ScreenshotCanvasNSView(document: document)
                canvas.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
                canvas.displayImageRect = CGRect(x: 0, y: 0, width: 80 * zoom, height: 40 * zoom)
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                    location: CGPoint(x: 10 * zoom, y: 10 * zoom), modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                canvas.mouseDown(with: event)
                let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
                let font = try XCTUnwrap(field.font)
                XCTAssertEqual(font.pointSize, fontSize, accuracy: 0.001)
                let content = try XCTUnwrap(field.cell).drawingRect(forBounds: field.bounds)
                XCTAssertGreaterThanOrEqual(content.height, ceil(font.ascender - font.descender + font.leading))
                XCTAssertGreaterThanOrEqual(content.minX - field.bounds.minX, 10)
                XCTAssertGreaterThanOrEqual(content.minY - field.bounds.minY, 8)
                XCTAssertFalse(field.isBezeled)
                XCTAssertFalse(field.drawsBackground)
                XCTAssertEqual(field.focusRingType, .none)
            }
        }
    }

    @MainActor
    func testAnnotationSizesRemainConstantOnScreenAcrossZoomLevels() throws {
        let document = try document()
        document.fontSize = 18
        document.strokeWidth = 6
        document.mosaicDiameter = 40
        for zoom: CGFloat in [0.25, 0.73, 1, 2, 4] {
            for tool in [ScreenshotTool.pen, .highlighter, .line, .arrow, .rectangle, .ellipse, .mosaic, .text] {
                let annotation = document.makeAnnotation(tool: tool, points: [.zero], displayScale: zoom)
                XCTAssertEqual(annotation.fontSize * zoom, 18, accuracy: 0.001)
                XCTAssertEqual(annotation.width * zoom, tool == .mosaic ? 40 : 6, accuracy: 0.001)
                XCTAssertEqual(annotation.sourceUnitsPerPoint * zoom, 1, accuracy: 0.001)
            }
        }
        document.selectAll()
        document.beginText(at: CGPoint(x: 5, y: 5), displayScale: 0.5)
        document.pendingText?.text = "文字"
        document.commitPendingText()
        XCTAssertEqual(document.state.annotations.first?.fontSize, 36)
        document.beginText(at: CGPoint(x: 5, y: 5), displayScale: 0.5)
        XCTAssertEqual(document.pendingText?.fontSize, 36, "Editing must not apply conversion a second time")
    }

    @MainActor
    func testExistingTextCanBeEditedWithoutDuplicatesAndUndoRestoresOriginal() throws {
        let document = try document()
        document.selectAll()
        let point = CGPoint(x: 5, y: 5)
        document.beginText(at: point)
        document.pendingText?.text = "原文字"
        document.commitPendingText()
        let count = document.undoStates.count
        document.beginText(at: point)
        XCTAssertEqual(document.pendingText?.text, "原文字")
        document.commitPendingText()
        XCTAssertEqual(document.undoStates.count, count)
        document.beginText(at: point)
        document.pendingText?.text = "修改后"
        document.commitPendingText()
        XCTAssertEqual(document.state.annotations.count, 1)
        XCTAssertEqual(document.state.annotations.first?.text, "修改后")
        document.undo()
        XCTAssertEqual(document.state.annotations.first?.text, "原文字")
        document.redo()
        XCTAssertEqual(document.state.annotations.first?.text, "修改后")
        document.beginText(at: point)
        document.pendingText?.text = "取消修改"
        document.cancelPendingText()
        XCTAssertEqual(document.state.annotations.first?.text, "修改后")
    }

    @MainActor
    func testEscapeCancelsOnlyCurrentTextInput() throws {
        let document = try document()
        document.selectAll()
        document.tool = .text
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        var closed = false
        canvas.onCancel = { closed = true }
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 120, y: 120), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: click)
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "不保存"
        XCTAssertTrue(canvas.control(field, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertNil(document.pendingText)
        XCTAssertTrue(document.state.annotations.isEmpty)
        XCTAssertFalse(closed)
        canvas.cancelOperation(nil)
        XCTAssertTrue(closed)
    }

    @MainActor
    func testExportCommitsPendingTextAndIgnoresBlankInput() throws {
        let document = try document()
        document.selectAll()
        document.pendingText = ScreenshotAnnotation(tool: .text, points: [CGPoint(x: 2, y: 2)],
            color: .white, width: 2, text: "导出文字", fontSize: 12)
        XCTAssertNoThrow(try document.renderedImage())
        XCTAssertNil(document.pendingText)
        XCTAssertEqual(document.state.annotations.first?.text, "导出文字")
        document.pendingText = ScreenshotAnnotation(tool: .text, points: [CGPoint(x: 2, y: 2)],
            color: .white, width: 2, text: "  ", fontSize: 12)
        document.commitPendingText()
        XCTAssertEqual(document.state.annotations.count, 1)
    }

    @MainActor
    func testPixelDimensionsResizeSelectionFromTopLeftAndSupportUndo() throws {
        let document = try document()
        document.state.selection = CGRect(x: 10, y: 10, width: 20, height: 20)
        document.resizeSelection(width: 35)
        XCTAssertEqual(document.state.selection, CGRect(x: 10, y: 10, width: 35, height: 20))
        document.resizeSelection(height: 10)
        XCTAssertEqual(document.state.selection, CGRect(x: 10, y: 20, width: 35, height: 10))
        XCTAssertEqual(ImageExporter.pixelSize(of: try document.renderedImage()), CGSize(width: 35, height: 10))
        document.undo()
        XCTAssertEqual(document.state.selection, CGRect(x: 10, y: 10, width: 35, height: 20))
        document.redo()
        XCTAssertEqual(document.state.selection?.size, CGSize(width: 35, height: 10))
    }

    @MainActor
    func testDisplayedDimensionsResizeOriginalSelectionAndMatchSaveOptions() throws {
        for scale: CGFloat in [0.25, 0.5, 1, 2] {
            let document = try document()
            document.state.selection = CGRect(x: 10, y: 0, width: 20, height: 40)
            XCTAssertTrue(document.resizeSelection(width: 8, height: 6, displayScale: scale))
            let size = try XCTUnwrap(document.state.selection).size
            XCTAssertEqual(size, CGSize(width: 8 / scale, height: 6 / scale))
            let accessory = ScreenshotExportAccessoryView(sourceSize: size, displayScale: scale)
            XCTAssertEqual(accessory.exportOptions.pixelSize, CGSize(width: 8, height: 6))
            accessory.selectedMode = .imageScale
            XCTAssertEqual(accessory.exportOptions.pixelSize, size)
            document.undo()
            XCTAssertEqual(document.state.selection, CGRect(x: 10, y: 0, width: 20, height: 40))
        }
    }

    @MainActor
    func testCommittingRoundedDisplayDimensionsPreservesOriginalSelection() throws {
        let document = try document()
        let selection = CGRect(x: 10, y: 10, width: 21, height: 17)
        document.state.selection = selection
        XCTAssertFalse(document.resizeSelection(width: 5, height: 4, displayScale: 0.25))
        XCTAssertEqual(document.state.selection, selection)
        XCTAssertTrue(document.undoStates.isEmpty)
    }

    @MainActor
    func testScaledRenderingKeepsOffsetCropAndAnnotationAligned() throws {
        let document = try document()
        document.state.selection = CGRect(x: 20, y: 10, width: 20, height: 20)
        document.state.annotations = [ScreenshotAnnotation(tool: .pen,
            points: [CGPoint(x: 24, y: 20), CGPoint(x: 36, y: 20)], color: .red, width: 4)]
        let image = try document.renderedImage(pixelSize: CGSize(width: 80, height: 80))
        XCTAssertEqual(ImageExporter.pixelSize(of: image), CGSize(width: 80, height: 80))
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let pixels = NSBitmapImageRep(cgImage: cgImage)
        let center = try XCTUnwrap(pixels.colorAt(x: 40, y: 40))
        XCTAssertGreaterThan(center.redComponent, 0.9)
        XCTAssertLessThan(center.greenComponent, 0.1)
        XCTAssertGreaterThan(center.alphaComponent, 0.9)
        XCTAssertThrowsError(try document.renderedImage(pixelSize: CGSize(width: 0, height: 80)))
    }

    @MainActor
    func testScreenSizeExportUsesLinearSamplingForFineStrokesAtElevenPercent() throws {
        let source = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<64 {
            for x in 0..<128 {
                let value: CGFloat = x % 7 < 2 ? 0 : 1
                source.setColor(NSColor(deviceRed: value, green: value, blue: value, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: CGSize(width: 128, height: 64))
        image.addRepresentation(source)
        let document = try ScreenshotDocument(image: image, rotationDegrees: 0)
        document.selectAll()
        let scale = ScreenshotExportSizeMode.displayPixelScale(imageDisplayScale: 0.11, screenScale: 2)
        let exported = try document.exportImage(mode: .selectedSize, displayPixelScale: scale)
        let actual = try XCTUnwrap(exported.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(actual.pixelsWide, 28)
        XCTAssertEqual(actual.pixelsHigh, 14)
        for x in 0..<28 {
            let actualColor = try XCTUnwrap(actual.colorAt(x: x, y: 7))
            let sourceX = (CGFloat(x) + 0.5) * 128 / 28 - 0.5
            let left = Int(floor(sourceX))
            let fraction = sourceX - CGFloat(left)
            let leftValue: CGFloat = left % 7 < 2 ? 0 : 1
            let rightValue: CGFloat = (left + 1) % 7 < 2 ? 0 : 1
            let expectedValue = leftValue * (1 - fraction) + rightValue * fraction
            XCTAssertEqual(actualColor.redComponent, expectedValue, accuracy: 0.01,
                           "Fine strokes must not be averaged away at screen size, pixel \(x)")
        }
    }

    @MainActor
    func testScreenSamplingPreservesOffsetCropAndRotationAtNativeScale() throws {
        for rotation in [0, 90, 180, 270] {
            let document = try document(rotation: rotation)
            document.state.selection = CGRect(x: 5, y: 7, width: 25, height: 23)
            let original = try document.exportImage(mode: .imageScale, displayPixelScale: 1)
            let screen = try document.exportImage(mode: .selectedSize, displayPixelScale: 1)
            let expected = try XCTUnwrap(original.representations.first as? NSBitmapImageRep)
            let actual = try XCTUnwrap(screen.representations.first as? NSBitmapImageRep)
            for y in 0..<23 {
                for x in 0..<25 {
                    let lhs = try XCTUnwrap(expected.colorAt(x: x, y: y))
                    let rhs = try XCTUnwrap(actual.colorAt(x: x, y: y))
                    XCTAssertEqual(lhs.redComponent, rhs.redComponent, accuracy: 0.01)
                    XCTAssertEqual(lhs.greenComponent, rhs.greenComponent, accuracy: 0.01)
                    XCTAssertEqual(lhs.blueComponent, rhs.blueComponent, accuracy: 0.01)
                    XCTAssertEqual(lhs.alphaComponent, rhs.alphaComponent, accuracy: 0.01)
                }
            }
        }
    }

    @MainActor
    func testResizeShiftsAtEdgesAndClampsToImageSize() throws {
        let document = try document()
        document.state.selection = CGRect(x: 60, y: 5, width: 20, height: 10)
        document.resizeSelection(width: 40, height: 25)
        XCTAssertEqual(document.state.selection, CGRect(x: 40, y: 0, width: 40, height: 25))
        document.resizeSelection(width: Int.max, height: Int.max)
        XCTAssertEqual(document.state.selection, document.bounds)
    }

    @MainActor
    func testResizeRejectsInvalidSizesAndAlignsFractionalSelectionToExportPixels() throws {
        let document = try document()
        document.resizeSelection(width: 10)
        XCTAssertNil(document.state.selection)
        document.state.selection = CGRect(x: 1.2, y: 2.3, width: 10.2, height: 5.2)
        let original = document.state.selection
        document.resizeSelection(width: 0)
        document.resizeSelection(height: -10)
        XCTAssertEqual(document.state.selection, original)
        XCTAssertTrue(document.undoStates.isEmpty)
        document.resizeSelection(width: 20)
        XCTAssertEqual(document.state.selection, CGRect(x: 1, y: 2, width: 20, height: 6))
        XCTAssertEqual(ImageExporter.pixelSize(of: try document.renderedImage()), CGSize(width: 20, height: 6))
        let count = document.undoStates.count
        document.resizeSelection(width: 20)
        XCTAssertEqual(document.undoStates.count, count)
    }

    @MainActor
    func testLiveDimensionTypingSharesOneUndoStep() throws {
        let document = try document()
        document.state.selection = CGRect(x: 10, y: 10, width: 20, height: 20)
        document.resizeSelection(width: 3)
        document.resizeSelection(width: 35, recordUndo: false)
        XCTAssertEqual(document.undoStates.count, 1)
        document.undo()
        XCTAssertEqual(document.state.selection, CGRect(x: 10, y: 10, width: 20, height: 20))
    }

    @MainActor
    func testMosaicBrushUsesRoundDabsAndContinuousStrokeInsteadOfBoundingRectangle() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        for y in 0..<40 {
            for x in 0..<80 {
                ((x + y).isMultiple(of: 2) ? NSColor.white : NSColor.black).setFill()
                CGRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: CGSize(width: 80, height: 40))
        image.addRepresentation(bitmap)
        let document = try ScreenshotDocument(image: image, rotationDegrees: 0)
        document.selectAll()
        let original = try XCTUnwrap(document.image.representations.first as? NSBitmapImageRep)
        func difference(_ rendered: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> CGFloat {
            let before = try XCTUnwrap(original.colorAt(x: x, y: 39 - y)?.usingColorSpace(.deviceRGB))
            let after = try XCTUnwrap(rendered.colorAt(x: x, y: 39 - y)?.usingColorSpace(.deviceRGB))
            return abs(before.redComponent - after.redComponent)
        }
        document.state.annotations = [ScreenshotAnnotation(tool: .mosaic,
            points: [CGPoint(x: 40, y: 20)], color: .red, width: 12)]
        let dab = try XCTUnwrap(try document.renderedImage().representations.first as? NSBitmapImageRep)
        XCTAssertGreaterThan(try max(difference(dab, 40, 20), difference(dab, 41, 20)), 0.2)
        XCTAssertLessThan(try difference(dab, 45, 25), 0.01) // Outside circle, inside its bounding square
        document.state.annotations = [ScreenshotAnnotation(tool: .mosaic,
            points: [CGPoint(x: 12, y: 12), CGPoint(x: 40, y: 12), CGPoint(x: 40, y: 30)],
            color: .red, width: 8)]
        let stroke = try XCTUnwrap(try document.renderedImage().representations.first as? NSBitmapImageRep)
        XCTAssertGreaterThan(try max(difference(stroke, 25, 12), difference(stroke, 26, 12)), 0.2) // No gap between mouse samples
        XCTAssertGreaterThan(try max(difference(stroke, 40, 22), difference(stroke, 41, 22)), 0.2)
        XCTAssertLessThan(try difference(stroke, 25, 25), 0.01) // Interior of bounding rectangle stays intact
    }

    @MainActor
    func testMovingTypedSelectionPreserves300PixelSizeAtDifferentZooms() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: CGSize(width: 600, height: 600))
        image.addRepresentation(bitmap)
        for scale: CGFloat in [0.73, 2] {
            let document = try ScreenshotDocument(image: image, rotationDegrees: 0)
            document.selectAll()
            _ = document.resizeSelection(width: 300, height: 300)
            let canvas = ScreenshotCanvasNSView(document: document)
            canvas.frame = CGRect(x: 0, y: 0, width: 1300, height: 1300)
            canvas.displayImageRect = CGRect(x: 0, y: 0, width: 600 * scale, height: 600 * scale)
            func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x * scale, y: point.y * scale),
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
            }
            for delta in [CGPoint(x: 10.4, y: -10.4), CGPoint(x: 8.7, y: -9.3), CGPoint(x: 900, y: -900)] {
                let before = try XCTUnwrap(document.state.selection)
                let start = CGPoint(x: before.midX, y: before.midY)
                let end = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
                canvas.mouseDown(with: try event(.leftMouseDown, start))
                canvas.mouseDragged(with: try event(.leftMouseDragged, end))
                let moved = try XCTUnwrap(document.state.selection)
                XCTAssertEqual(moved.integral.size, CGSize(width: 300, height: 300))
                XCTAssertTrue(document.bounds.contains(moved))
                canvas.mouseUp(with: try event(.leftMouseUp, end))
                let result = try document.renderedImage()
                let pixels = try XCTUnwrap(result.representations.first as? NSBitmapImageRep)
                XCTAssertEqual(pixels.pixelsWide, 300)
                XCTAssertEqual(pixels.pixelsHigh, 300)
                document.undo()
                XCTAssertEqual(document.state.selection, before)
                document.redo()
                XCTAssertEqual(document.state.selection, moved)
            }
        }
    }

    @MainActor
    func testArrowRequiresDragAndClickPreservesHistory() throws {
        let document = try document()
        document.selectAll()
        document.tool = .arrow
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 20 + x * 10, y: 20 + y * 10),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, 10, 10))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 10.1, 10.1))
        canvas.mouseUp(with: try event(.leftMouseUp, 10.1, 10.1))
        XCTAssertTrue(document.state.annotations.isEmpty)
        XCTAssertTrue(document.undoStates.isEmpty)
        canvas.mouseDown(with: try event(.leftMouseDown, 10, 10))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 20, 20))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 30, 25))
        canvas.mouseUp(with: try event(.leftMouseUp, 30, 25))
        XCTAssertEqual(document.state.annotations.count, 1)
        XCTAssertEqual(document.state.annotations.first?.points, [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 25)])
        XCTAssertEqual(document.undoStates.count, 1)
        document.undo()
        canvas.mouseDown(with: try event(.leftMouseDown, 10, 10))
        canvas.mouseUp(with: try event(.leftMouseUp, 10, 10))
        XCTAssertTrue(document.state.annotations.isEmpty)
        XCTAssertTrue(document.undoStates.isEmpty)
        XCTAssertEqual(document.redoStates.count, 1)
        document.redo()
        XCTAssertEqual(document.state.annotations.count, 1)
    }

    @MainActor
    func testMosaicDragRecordsEntirePathAndIndependentDiameterWithOneUndo() throws {
        let document = try document()
        document.selectAll()
        document.tool = .mosaic
        document.mosaicDiameter = 16
        document.strokeWidth = 3
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 20 + x * 10, y: 20 + y * 10),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, 10, 10))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 30, 10))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 30, 25))
        canvas.mouseUp(with: try event(.leftMouseUp, 30, 25))
        let stroke = try XCTUnwrap(document.state.annotations.first)
        XCTAssertEqual(stroke.width * 10, 16, accuracy: 0.001)
        XCTAssertEqual(stroke.points.count, 3)
        document.undo()
        XCTAssertTrue(document.state.annotations.isEmpty)
        document.redo()
        XCTAssertEqual(document.state.annotations.first?.points.count, 3)
    }

    @MainActor
    func testOutsideClickNeverClearsSelectionOrChangesToolbarBeforeMouseUp() throws {
        let document = try document()
        let canvas = ScreenshotCanvasNSView(document: document)
        canvas.frame = CGRect(x: 0, y: 0, width: 840, height: 440)
        let selection = CGRect(x: 20, y: 10, width: 30, height: 20)
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 20 + x * 10, y: 20 + y * 10),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        for tool in [ScreenshotTool.crop, .text, .mosaic] {
            document.state.selection = selection
            document.tool = tool
            let historyCount = document.undoStates.count
            canvas.mouseDown(with: try event(.leftMouseDown, 5, 5))
            XCTAssertEqual(document.state.selection, selection, "Mouse-down must not hide the selection/toolbar")
            XCTAssertTrue(document.canExport)
            XCTAssertEqual(document.tool, tool, "Do not collapse tool-specific controls on a plain click")
            canvas.mouseDragged(with: try event(.leftMouseDragged, 5.1, 5.1))
            XCTAssertEqual(document.state.selection, selection, "Ignore small pointer jitter")
            canvas.mouseUp(with: try event(.leftMouseUp, 5.1, 5.1))
            XCTAssertEqual(document.state.selection, selection)
            XCTAssertEqual(document.tool, tool)
            XCTAssertEqual(document.undoStates.count, historyCount)
        }
        canvas.mouseDown(with: try event(.leftMouseDown, 5, 5))
        let historyCount = document.undoStates.count
        canvas.mouseDragged(with: try event(.leftMouseDragged, 15, 9))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 17, 9))
        canvas.mouseUp(with: try event(.leftMouseUp, 17, 9))
        XCTAssertEqual(document.state.selection, CGRect(x: 5, y: 5, width: 12, height: 4))
        XCTAssertEqual(document.tool, .crop)
        XCTAssertEqual(document.undoStates.count, historyCount + 1)
        document.undo()
        XCTAssertEqual(document.state.selection, selection)
    }

}
