import AppKit
import ImageIO
import Vision
@preconcurrency import VisionKit

struct RecognizedTextFragment: Sendable {
    let text: String
    let boundingBox: CGRect
    let lineIndex: Int
    let fragmentIndex: Int
}

struct RecognizedTextLine: Sendable {
    let text: String
    let boundingBox: CGRect
    let fragments: [RecognizedTextFragment]
}

private struct RecognizedObservationLine {
    let text: String
    let boundingBox: CGRect
    let candidate: VNRecognizedText
}

/// Owns debounce, cancellation and stale-result protection independently of
/// canvas gestures/layout. Only settled images start recognition.
@MainActor
final class ImageTextRecognizer {
    private let analyzer = ImageAnalyzer()
    private var task: Task<Void, Never>?
    private var revision = 0
    private(set) var startedCount = 0

    func cancel() {
        revision += 1
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }

    func schedule(image: NSImage?, url: URL?, backend: TextRecognitionBackend,
                  liveText: @escaping @MainActor (ImageAnalysis?) -> Void,
                  vision: @escaping @MainActor ([RecognizedTextLine]) -> Void) {
        cancel()
        guard let image else { return }
        let revision = revision
        let analyzer = analyzer
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            guard !Task.isCancelled, self?.revision == revision,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            self?.startedCount += 1
            switch backend {
            case .liveText:
                guard ImageAnalyzer.isSupported else { return }
                do {
                    let orientation = await VisionTextRecognitionWorker.shared.orientation(for: url)
                    guard !Task.isCancelled else { return }
                    let result = try await analyzer.analyze(cgImage, orientation: orientation,
                        configuration: ImageAnalyzer.Configuration([.text, .machineReadableCode, .visualLookUp]))
                    guard !Task.isCancelled, self?.revision == revision else { return }
                    liveText(result)
                } catch {
                    guard !Task.isCancelled, self?.revision == revision else { return }
                    liveText(nil)
                }
            case .vision:
                let lines = await VisionTextRecognitionWorker.shared.recognize(cgImage, url: url)
                guard !Task.isCancelled, self?.revision == revision else { return }
                vision(lines)
            }
        }
    }
}

private actor VisionTextRecognitionWorker {
    static let shared = VisionTextRecognitionWorker()

    func orientation(for url: URL?) -> CGImagePropertyOrientation {
        Self.exifOrientation(for: url)
    }

    func recognize(_ cgImage: CGImage, url: URL?) -> [RecognizedTextLine] {
        guard !Task.isCancelled else { return [] }
        let orientation = Self.exifOrientation(for: url)
        do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

            try handler.perform([request])
            let observations = request.results ?? []
            let sortedObservations = observations.compactMap { observation -> RecognizedObservationLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return RecognizedObservationLine(text: text, boundingBox: observation.boundingBox, candidate: candidate)
            }.sorted(by: Self.sortObservationLines)
            let lines = sortedObservations.enumerated().map { lineOffset, line in
                RecognizedTextLine(text: line.text, boundingBox: line.boundingBox,
                    fragments: Self.makeFragments(from: line.candidate, text: line.text, lineIndex: lineOffset))
            }

            return Task.isCancelled ? [] : lines
        } catch { return [] }
    }

    nonisolated private static func sortObservationLines(_ lhs: RecognizedObservationLine, _ rhs: RecognizedObservationLine) -> Bool {
        let leftY = lhs.boundingBox.midY
        let rightY = rhs.boundingBox.midY
        if abs(leftY - rightY) > 0.01 {
            return leftY > rightY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    nonisolated private static func makeFragments(
        from candidate: VNRecognizedText,
        text: String,
        lineIndex: Int
    ) -> [RecognizedTextFragment] {
        var fragments: [RecognizedTextFragment] = []
        var fragmentIndex = 0
        var index = text.startIndex

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let range = index ..< nextIndex

            if let observation = try? candidate.boundingBox(for: range) {
                let rect = observation.boundingBox
                guard !rect.isEmpty else {
                    fragmentIndex += 1
                    index = nextIndex
                    continue
                }
                fragments.append(
                    RecognizedTextFragment(
                        text: String(text[range]),
                        boundingBox: rect,
                        lineIndex: lineIndex,
                        fragmentIndex: fragmentIndex
                    )
                )
            }

            fragmentIndex += 1
            index = nextIndex
        }

        return fragments
    }

    nonisolated static func exifOrientation(for url: URL?) -> CGImagePropertyOrientation {
        guard
            let url,
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
            let orientation = CGImagePropertyOrientation(rawValue: rawValue)
        else {
            return .up
        }
        return orientation
    }
}
