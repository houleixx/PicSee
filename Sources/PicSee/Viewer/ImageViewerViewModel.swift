import AppKit
import Combine
import Foundation
import ImageIO
import SwiftUI

struct ImageZoomRequest: Equatable {
    let id: Int
    let multiplier: CGFloat
}

@MainActor
final class ImageViewerViewModel: ObservableObject {
    @Published private(set) var sessionID = UUID()
    @Published private(set) var currentURL: URL
    @Published private(set) var isImageLoading = false
    @Published private(set) var image: NSImage?
    private var loadedMetadata: ImageParameterMetadata?
    private var loadedByteCount: Int64?
    private var loadedPixelSize: CGSize?
    var imagePixelSize: CGSize? { loadedPixelSize }
    private let loadingMode: ImageLoadingMode
    private let readImage: @Sendable (URL) async -> LoadedImage?
    private let prefetchCache: ImagePrefetchCache
    private var imageLoadTask: Task<Void, Never>?
    private var imageLoadRevision = 0
    private var requestedURL: URL?

    @Published private var imageOpenFailed = false
    var errorMessage: String? { imageOpenFailed ? L10n.text("PicSee 无法打开此图片。") : nil }
    @Published private(set) var isFolderEmpty = false
    @Published private(set) var deletionNoticeID: UUID?
    @Published private var fileOperationMessage: (() -> String)?
    var fileOperationError: String? {
        get { fileOperationMessage?() }
        set { fileOperationMessage = newValue.map { value in { value } } }
    }
    @Published private var deletions: [DeletedImage] = []
    @Published var isScreenshotEditing = false {
        didSet { if isScreenshotEditing { slideshow.pause() } }
    }
    let slideshow: SlideshowController
    private var slideshowObservation: AnyCancellable?
    @Published var zoomScale: CGFloat = 1
    @Published var panOffset: CGSize = .zero
    @Published var displayScale: CGFloat = 1
    @Published var rotationDegrees: Int = 0
    @Published var zoomRequest: ImageZoomRequest?
    @Published private(set) var transformAnimationID = 0
    @Published private(set) var navigationDirection: Int?
    @Published private(set) var isNavigationOrderReady: Bool
    private let finderOrderProvider: any FinderFolderOrderProviding

    @Published private var navigator: FolderImageNavigator?
    private let fileManager: FileManager
    private let imageTrash: any ImageTrashing
    private struct DeletedImage {
        let originalURL: URL
        let trashedURL: URL
        let order: [URL]
    }
    private var finderOrderTask: Task<Void, Never>?
    private var pendingNavigationDirections: [NavigationDirection] = []
    private var navigationRevision = 0
    private var nextZoomRequestID = 0

    init(
        loadingMode: ImageLoadingMode = .background,
        imageURL: URL,
        finderOrderProvider: any FinderFolderOrderProviding = FilenameFolderOrderProvider(),
        fileManager: FileManager = .default,
        imageTrash: any ImageTrashing = ImageTrash(),
        slideshow: SlideshowController = SlideshowController(),
        readImage: @escaping @Sendable (URL) async -> LoadedImage? = ImageLoadWorker.load,
        prefetchImage: @escaping @Sendable (URL, Int) async -> LoadedImage? = ImageLoadWorker.prefetch
    ) {
        self.loadingMode = loadingMode
        self.readImage = readImage
        self.prefetchCache = ImagePrefetchCache(prefetchReader: prefetchImage)
        self.slideshow = slideshow
        self.finderOrderProvider = finderOrderProvider
        self.currentURL = imageURL.standardizedFileURL
        self.fileManager = fileManager
        self.imageTrash = imageTrash
        self.isNavigationOrderReady = finderOrderProvider.isOrderingAvailableImmediately
        if loadingMode == .immediate {
            establishNavigator(for: imageURL, preferredOrder: nil)
            _ = load(imageURL: imageURL)
        } else {
            isNavigationOrderReady = false
            requestImage(imageURL) { model, loaded in
                _ = model.applyLoad(imageURL: imageURL, loaded: loaded)
                if model.isNavigationOrderReady { model.applyPendingNavigation() }
            }
        }

        slideshow.onAdvance = { [weak self] in
            guard let self else { return false }
            return self.advanceSlideshow(forward: true, wrapping: self.slideshow.loops)
        }
        slideshowObservation = slideshow.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        startImageOrder(waitForResult: false)
    }

    deinit {
        finderOrderTask?.cancel()
        imageLoadTask?.cancel()
    }

    private func startImageOrder(waitForResult: Bool) {
        slideshow.setReady(false)
        finderOrderTask?.cancel()
        navigationRevision += 1
        pendingNavigationDirections.removeAll()
        let initialURL = currentURL
        let initialRevision = navigationRevision
        let folderURL = initialURL.deletingLastPathComponent()
        let provider = finderOrderProvider
        isNavigationOrderReady = loadingMode == .immediate && !waitForResult && provider.isOrderingAvailableImmediately
        let mode = loadingMode
        let files = fileManager
        finderOrderTask = Task { [weak self] in
            let result = await provider.ordering(for: folderURL)
            guard !Task.isCancelled else { return }
            let snapshot: [URL]?
            if mode == .background {
                let preferredOrder = result.urls
                snapshot = await Task.detached(priority: .userInitiated) {
                    try? FolderImageNavigator(currentImageURL: initialURL, fileManager: FileManager(), preferredOrder: preferredOrder).images
                }.value
            } else { snapshot = nil }
            guard !Task.isCancelled, let self,
                  self.navigationRevision == initialRevision,
                  self.currentURL == initialURL else { return }
            if let snapshot {
                self.navigator = FolderImageNavigator(currentImageURL: initialURL, snapshot: snapshot, fileManager: files)
            } else { self.establishNavigator(for: initialURL, preferredOrder: result.urls) }
            self.isNavigationOrderReady = true
            if !self.isImageLoading { self.applyPendingNavigation() }
            self.slideshow.setReady(!self.isImageLoading)
        }
    }

    var currentFilename: String {
        if isFolderEmpty { return currentURL.deletingLastPathComponent().lastPathComponent }
        return currentURL.lastPathComponent
    }

    var zoomPercentageText: String {
        "\(Int((displayScale * 100).rounded()))%"
    }

    var imagePixelSizeText: String? {
        guard image != nil, let size = loadedPixelSize else { return nil }
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }

    var fileSizeText: String? {
        guard let byteCount = loadedByteCount else { return nil }
        return ByteCountFormatStyle(style: .file, spellsOutZero: false, locale: L10n.locale).format(byteCount)
    }

    var imageMetadataText: String? {
        [currentFilename, fileSizeText, imagePixelSizeText]
            .compactMap { $0 }
            .joined(separator: " | ")
    }

    var imageParametersText: String? {
        loadedMetadata?.displayText
    }

    var titleBarText: String {
        if isFolderEmpty { return L10n.text("%1$@ — 此文件夹中没有可浏览的图片", String(describing: currentFilename)) }
        return [imageMetadataText, zoomPercentageText]
            .compactMap { $0 }
            .joined(separator: " | ")
    }

    var previousURL: URL? {
        guard isNavigationOrderReady else { return nil }
        return navigator?.previousURL()
    }

    var nextURL: URL? {
        guard isNavigationOrderReady else { return nil }
        return navigator?.nextURL()
    }

    var canTrashCurrentImage: Bool {
        image != nil && isNavigationOrderReady && !isImageLoading && !isScreenshotEditing && !isFolderEmpty
    }

    var canUndoDeletion: Bool { !deletions.isEmpty && !isScreenshotEditing && !isImageLoading }

    func trashCurrentImage() {
        guard canTrashCurrentImage else { return }
        prefetchCache.clear()
        slideshow.pause()
        let originalURL = currentURL
        let order = navigator?.images ?? [originalURL]
        let index = order.firstIndex(of: originalURL) ?? 0
        do {
            let trashedURL = try imageTrash.trash(originalURL)
            if let trashedURL {
                deletions.append(DeletedImage(originalURL: originalURL, trashedURL: trashedURL, order: order))
            }
            navigationRevision += 1
            finderOrderTask?.cancel()
            pendingNavigationDirections.removeAll()
            deletionNoticeID = UUID()
            fileOperationError = nil

            continueAfterDeletion(originalURL: originalURL, order: order, index: index)
        } catch {
            fileOperationMessage = { L10n.text("无法将“%1$@”移到废纸篓。\n%2$@", String(describing: originalURL.lastPathComponent), String(describing: L10n.errorDescription(error))) }
        }
    }

    private func continueAfterDeletion(originalURL: URL, order: [URL], index: Int) {
        let folder = originalURL.deletingLastPathComponent()
        let files = fileManager
        let readAdded: @Sendable (FileManager) -> [URL] = { files in
            let existing = Set(order)
            let contents = (try? files.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            return contents.map(\.standardizedFileURL).filter {
                !existing.contains($0) && FolderImageNavigator.isSupportedImage($0)
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        if loadingMode == .immediate {
            completeDeletion(originalURL: originalURL, order: order, index: index, added: readAdded(files))
        } else {
            imageLoadRevision += 1
            let revision = imageLoadRevision
            imageLoadTask?.cancel()
            isImageLoading = true
            imageLoadTask = Task { [weak self] in
                let added = await Task.detached(priority: .userInitiated) { readAdded(FileManager()) }.value
                guard !Task.isCancelled, let self, self.imageLoadRevision == revision else { return }
                self.isImageLoading = false
                self.completeDeletion(originalURL: originalURL, order: order, index: index, added: added)
            }
        }
    }

    private func completeDeletion(originalURL: URL, order: [URL], index: Int, added: [URL]) {
        let candidates = Array(order.dropFirst(index + 1)) + Array(order.prefix(index).reversed()) + added
        if loadingMode == .background {
            loadAfterDeletion(candidates, order: order + added, originalURL: originalURL)
            return
        }
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            if load(imageURL: candidate) {
                establishNavigator(for: candidate, preferredOrder: order + added)
                return
            }
        }
        showEmptyFolder(originalURL: originalURL)
    }

    private func loadAfterDeletion(_ candidates: [URL], order: [URL], originalURL: URL) {
        guard let candidate = candidates.first else {
            showEmptyFolder(originalURL: originalURL)
            return
        }
        requestImage(candidate) { model, loaded in
            if model.applyLoad(imageURL: candidate, loaded: loaded, preservesCurrentImageOnFailure: true) {
                model.navigator = FolderImageNavigator(currentImageURL: candidate,
                    snapshot: order.filter { $0 != originalURL }, fileManager: model.fileManager)
            } else {
                model.loadAfterDeletion(Array(candidates.dropFirst()), order: order, originalURL: originalURL)
            }
        }
    }

    private func showEmptyFolder(originalURL: URL) {
        slideshow.stop()
        navigator = nil
        currentURL = originalURL
        isFolderEmpty = true
        loadedMetadata = nil
        loadedByteCount = nil
        loadedPixelSize = nil
        image = nil
        imageOpenFailed = false
        resetViewTransform()
        rotationDegrees = 0
        zoomRequest = nil
    }

    func undoDeletion() {
        guard canUndoDeletion, let deletion = deletions.last else { return }
        prefetchCache.clear()
        slideshow.pause()
        do {
            try imageTrash.restore(deletion.trashedURL, to: deletion.originalURL)
            deletions.removeLast()
            navigationRevision += 1
            finderOrderTask?.cancel()
            pendingNavigationDirections.removeAll()
            isNavigationOrderReady = true
            if loadingMode == .immediate {
                establishNavigator(for: deletion.originalURL, preferredOrder: deletion.order)
                _ = load(imageURL: deletion.originalURL)
            } else {
                navigator = FolderImageNavigator(currentImageURL: deletion.originalURL, snapshot: deletion.order, fileManager: fileManager)
                requestImage(deletion.originalURL) { model, loaded in
                    _ = model.applyLoad(imageURL: deletion.originalURL, loaded: loaded)
                }
            }
            deletionNoticeID = nil
            fileOperationError = nil
        } catch {
            fileOperationMessage = { L10n.text("无法恢复“%1$@”。\n%2$@", String(describing: deletion.originalURL.lastPathComponent), String(describing: L10n.errorDescription(error))) }
        }
    }

    func navigateToPrevious() {
        guard isNavigationOrderReady else {
            pendingNavigationDirections.append(.previous)
            return
        }
        navigationRevision += 1
        navigateUsingSnapshot(direction: .previous)
        slideshow.restartInterval()
    }

    func navigateToNext() {
        guard isNavigationOrderReady else {
            pendingNavigationDirections.append(.next)
            return
        }
        navigationRevision += 1
        navigateUsingSnapshot(direction: .next)
        slideshow.restartInterval()
    }

    func navigate(to url: URL) {
        if loadingMode == .background {
            requestExternalImage(url, startsNewSession: false)
            return
        }
        slideshow.stop()
        let standardizedURL = url.standardizedFileURL
        let changedFolder = standardizedURL.deletingLastPathComponent() != currentURL.deletingLastPathComponent()
        let needsOrder = changedFolder || !isNavigationOrderReady || navigator?.images.contains(standardizedURL) != true
        navigationRevision += 1
        pendingNavigationDirections.removeAll()
        if needsOrder { establishNavigator(for: standardizedURL, preferredOrder: nil) }
        _ = load(imageURL: standardizedURL)
        if needsOrder { startImageOrder(waitForResult: true) }
    }

    /// External opens start a fresh browsing session; failed loads leave it intact.
    @discardableResult
    func openImage(_ url: URL) -> Bool {
        if loadingMode == .background {
            // Accepted asynchronously. Session state changes only after a valid load.
            requestExternalImage(url, startsNewSession: true)
            return true
        }
        let url = url.standardizedFileURL
        if url == currentURL, image != nil, !isFolderEmpty { return true }
        guard load(imageURL: url, preservesCurrentImageOnFailure: true) else {
            fileOperationMessage = { L10n.text("无法打开“%1$@”，当前图片已保留。", String(describing: url.lastPathComponent)) }
            return false
        }
        slideshow.stop()
        isScreenshotEditing = false
        deletions.removeAll()
        deletionNoticeID = nil
        fileOperationError = nil
        displayScale = 1
        transformAnimationID = 0
        sessionID = UUID()
        establishNavigator(for: url, preferredOrder: nil)
        startImageOrder(waitForResult: true)
        return true
    }

    func resetViewTransform() {
        zoomScale = 1
        panOffset = .zero
    }

    func fitToWindow() {
        slideshow.pause()
        transformAnimationID += 1
        resetViewTransform()
    }

    func showActualSize() {
        slideshow.pause()
        transformAnimationID += 1
        guard displayScale > 0 else {
            resetViewTransform()
            return
        }
        zoomScale = ImageZoomAdjustment.clampedZoom(currentZoom: zoomScale, multiplier: 1 / displayScale,
            automaticPixelScale: displayScale / max(CGFloat.leastNormalMagnitude, zoomScale))
        panOffset = .zero
    }

    func zoomIn() {
        requestZoom(multiplier: 1.25)
    }

    func zoomOut() {
        requestZoom(multiplier: 0.8)
    }

    func clearZoomRequest(id: Int) {
        if zoomRequest?.id == id {
            zoomRequest = nil
        }
    }

    func rotateLeft() {
        slideshow.pause()
        rotationDegrees = (rotationDegrees + 90) % 360
        panOffset = .zero
    }

    func rotateRight() {
        slideshow.pause()
        rotationDegrees = (rotationDegrees + 270) % 360
        panOffset = .zero
    }

    private enum NavigationDirection {
        case previous
        case next
    }

    private func establishNavigator(for imageURL: URL, preferredOrder: [URL]?) {
        let standardizedURL = imageURL.standardizedFileURL
        navigator = try? FolderImageNavigator(
            currentImageURL: standardizedURL,
            fileManager: fileManager,
            preferredOrder: preferredOrder
        )
    }

    private func navigateUsingSnapshot(direction: NavigationDirection) {
        if loadingMode == .background {
            requestNavigation(direction: direction, wrapping: true, skipsInvalid: slideshow.isActive)
            return
        }
        if slideshow.isActive {
            if !advanceSlideshow(forward: direction == .next, wrapping: true) { slideshow.stop() }
            return
        }
        while let candidate = direction == .previous ? navigator?.previousURL() : navigator?.nextURL() {
            if load(imageURL: candidate, preservesCurrentImageWhenMissing: true, direction: direction == .next ? 1 : -1) {
                return
            }
            guard !fileManager.fileExists(atPath: candidate.path) else { return }
            navigator?.removeFromSnapshot(candidate)
        }
    }

    private func applyPendingNavigation() {
        let directions = pendingNavigationDirections
        pendingNavigationDirections.removeAll()
        for direction in directions {
            navigationRevision += 1
            navigateUsingSnapshot(direction: direction)
        }
    }

    func startSlideshow() {
        guard image != nil, !isFolderEmpty, !isScreenshotEditing, !isImageLoading else { return }
        resetViewTransform()
        slideshow.start(ready: isNavigationOrderReady)
    }

    /// A bounded snapshot avoids wrapping forever when every remaining file is bad.
    private func advanceSlideshow(forward: Bool, wrapping: Bool) -> Bool {
        if loadingMode == .background {
            return requestNavigation(direction: forward ? .next : .previous, wrapping: wrapping, skipsInvalid: true)
        }
        guard isNavigationOrderReady, !isScreenshotEditing, let navigator else { return false }
        let images = navigator.images
        guard let index = images.firstIndex(of: currentURL) else { return false }
        let candidates: [URL]
        if forward {
            candidates = Array(images.dropFirst(index + 1)) + (wrapping ? Array(images.prefix(index)) : [])
        } else {
            candidates = Array(images.prefix(index).reversed()) + (wrapping ? Array(images.dropFirst(index + 1).reversed()) : [])
        }
        for candidate in candidates {
            if load(imageURL: candidate, preservesCurrentImageOnFailure: true, direction: forward ? 1 : -1) {
                navigationRevision += 1
                return true
            }
            navigator.removeFromSnapshot(candidate)
        }
        return false
    }

    @discardableResult
    private func load(
        imageURL: URL,
        preservesCurrentImageWhenMissing: Bool = false,
        preservesCurrentImageOnFailure: Bool = false,
        direction: Int? = nil
    ) -> Bool {
        applyLoad(imageURL: imageURL, loaded: LoadedImage.read(imageURL),
                  preservesCurrentImageWhenMissing: preservesCurrentImageWhenMissing,
                  preservesCurrentImageOnFailure: preservesCurrentImageOnFailure, direction: direction)
    }

    @discardableResult
    private func applyLoad(
        imageURL: URL, loaded: LoadedImage?,
        preservesCurrentImageWhenMissing: Bool = false,
        preservesCurrentImageOnFailure: Bool = false,
        direction: Int? = nil
    ) -> Bool {
        let standardizedURL = imageURL.standardizedFileURL
        guard let loaded else {
            if preservesCurrentImageOnFailure { return false }
            if preservesCurrentImageWhenMissing,
               !fileManager.fileExists(atPath: standardizedURL.path) {
                return false
            }
            isFolderEmpty = false
            if loadingMode == .background {
                prefetchCache.didDisplay(standardizedURL, image: nil, retainingPrevious: direction != nil && !slideshow.isActive)
            }
            currentURL = standardizedURL
            resetViewTransform()
            rotationDegrees = 0
            zoomRequest = nil
            loadedMetadata = nil
            loadedByteCount = nil
            loadedPixelSize = nil
            image = nil
            imageOpenFailed = true
            navigator?.move(to: standardizedURL)
            return false
        }

        if loadingMode == .background {
            prefetchCache.didDisplay(standardizedURL, image: loaded, retainingPrevious: direction != nil && !slideshow.isActive)
        }
        isFolderEmpty = false
        currentURL = standardizedURL
        resetViewTransform()
        rotationDegrees = 0
        zoomRequest = nil
        navigationDirection = direction
        TransparencyBackground.remember(loaded.containsTransparency, for: loaded.image)
        loadedMetadata = loaded.metadata
        loadedByteCount = loaded.byteCount
        loadedPixelSize = loaded.pixelSize
        image = loaded.image
        imageOpenFailed = false
        navigator?.move(to: standardizedURL)
        return true
    }

    /// Revision checks apply even when a decoder cannot stop midway through a file.
    private func requestImage(_ url: URL, completion: @escaping @MainActor (ImageViewerViewModel, LoadedImage?) -> Void) {
        imageLoadRevision += 1
        let revision = imageLoadRevision
        imageLoadTask?.cancel()
        requestedURL = url.standardizedFileURL
        isImageLoading = true
        slideshow.setReady(false)
        let reader = readImage
        let cache = prefetchCache
        imageLoadTask = Task { [weak self] in
            let loaded = await cache.load(url, reader: reader)
            guard !Task.isCancelled, let self, self.imageLoadRevision == revision else { return }
            self.requestedURL = nil
            self.isImageLoading = false
            completion(self, loaded)
            self.slideshow.setReady(self.isNavigationOrderReady && !self.isImageLoading)
        }
    }

    private func requestExternalImage(_ url: URL, startsNewSession: Bool) {
        prefetchCache.clear()
        let url = url.standardizedFileURL
        if url == currentURL, image != nil, !isFolderEmpty {
            // Reopening the displayed file supersedes a pending replacement,
            // while preserving its zoom, editing state and session identity.
            imageLoadRevision += 1
            imageLoadTask?.cancel()
            imageLoadTask = nil
            requestedURL = nil
            isImageLoading = false
            slideshow.setReady(isNavigationOrderReady)
            return
        }
        slideshow.pause()
        requestImage(url) { model, loaded in
            guard model.applyLoad(imageURL: url, loaded: loaded, preservesCurrentImageOnFailure: true) else {
                model.fileOperationMessage = { L10n.text("无法打开“%1$@”，当前图片已保留。", String(describing: url.lastPathComponent)) }
                return
            }
            model.slideshow.stop()
            if startsNewSession {
                model.isScreenshotEditing = false
                model.deletions.removeAll()
                model.deletionNoticeID = nil
                model.displayScale = 1
                model.transformAnimationID = 0
                model.sessionID = UUID()
            }
            model.fileOperationError = nil
            model.startImageOrder(waitForResult: true)
        }
    }

    @discardableResult
    private func requestNavigation(direction: NavigationDirection, wrapping: Bool, skipsInvalid: Bool) -> Bool {
        guard isNavigationOrderReady, !isScreenshotEditing, let navigator else { return false }
        let images = navigator.images
        guard let index = images.firstIndex(of: requestedURL ?? currentURL) else { return false }
        let candidates: [URL]
        if direction == .next {
            candidates = Array(images.dropFirst(index + 1)) + (wrapping ? Array(images.prefix(index + 1)) : [])
        } else {
            candidates = Array(images.prefix(index).reversed()) + (wrapping ? Array(images.dropFirst(index).reversed()) : [])
        }
        guard images.count > 1, !candidates.isEmpty else { return false }
        let eligible = skipsInvalid ? candidates.filter { $0 != currentURL } : candidates
        guard !eligible.isEmpty else { return false }
        loadNavigationCandidates(eligible, direction: direction, skipsInvalid: skipsInvalid)
        return true
    }

    private func loadNavigationCandidates(_ candidates: [URL], direction: NavigationDirection, skipsInvalid: Bool) {
        guard let candidate = candidates.first else {
            if slideshow.isActive { slideshow.stop() }
            return
        }
        requestImage(candidate) { model, loaded in
            let exists = model.fileManager.fileExists(atPath: candidate.path)
            if loaded == nil, !exists || skipsInvalid {
                model.navigator?.removeFromSnapshot(candidate)
                model.loadNavigationCandidates(Array(candidates.dropFirst()), direction: direction, skipsInvalid: skipsInvalid)
                return
            }
            let displayed = model.applyLoad(imageURL: candidate, loaded: loaded, direction: direction == .next ? 1 : -1)
            if displayed, !model.slideshow.isActive {
                model.prefetchCache.prefetch(direction == .next ? model.navigator?.nextURL() : model.navigator?.previousURL())
            }
        }
    }

    private func requestZoom(multiplier: CGFloat) {
        slideshow.pause()
        nextZoomRequestID += 1
        zoomRequest = ImageZoomRequest(id: nextZoomRequestID, multiplier: multiplier)
    }
}
