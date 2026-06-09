import AppKit
import Foundation
import ImageIO
import SwiftUI

struct ImageZoomRequest: Equatable {
    let id: Int
    let multiplier: CGFloat
}

@MainActor
final class ImageViewerViewModel: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var image: NSImage?
    @Published private(set) var errorMessage: String?
    @Published var zoomScale: CGFloat = 1
    @Published var panOffset: CGSize = .zero
    @Published var displayScale: CGFloat = 1
    @Published var rotationDegrees: Int = 0
    @Published var zoomRequest: ImageZoomRequest?

    private var navigator: FolderImageNavigator?
    private var nextZoomRequestID = 0

    init(imageURL: URL) {
        self.currentURL = imageURL.standardizedFileURL
        load(imageURL: imageURL)
    }

    var currentFilename: String {
        currentURL.lastPathComponent
    }

    var zoomPercentageText: String {
        "\(Int((displayScale * 100).rounded()))%"
    }

    var imagePixelSizeText: String? {
        guard let image, let pixelSize = image.pixelSize else { return nil }
        return "\(pixelSize.width) × \(pixelSize.height) px"
    }

    var fileSizeText: String? {
        guard let byteCount = currentURL.fileByteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var imageMetadataText: String? {
        [currentFilename, fileSizeText, imagePixelSizeText]
            .compactMap { $0 }
            .joined(separator: " | ")
    }

    var imageParametersText: String? {
        ImageParameterMetadata(url: currentURL)?.displayText
    }

    var titleBarText: String {
        [imageMetadataText, zoomPercentageText]
            .compactMap { $0 }
            .joined(separator: " | ")
    }

    var previousURL: URL? {
        navigator?.previousURL()
    }

    var nextURL: URL? {
        navigator?.nextURL()
    }

    func navigateToPrevious() {
        guard let previousURL else { return }
        navigate(to: previousURL)
    }

    func navigateToNext() {
        guard let nextURL else { return }
        navigate(to: nextURL)
    }

    func navigate(to url: URL) {
        load(imageURL: url)
    }

    func resetViewTransform() {
        zoomScale = 1
        panOffset = .zero
    }

    func fitToWindow() {
        resetViewTransform()
    }

    func showActualSize() {
        guard displayScale > 0 else {
            resetViewTransform()
            return
        }
        zoomScale = ImageZoomAdjustment.clampedZoom(currentZoom: zoomScale, multiplier: 1 / displayScale)
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
        rotationDegrees = (rotationDegrees + 90) % 360
        panOffset = .zero
    }

    func rotateRight() {
        rotationDegrees = (rotationDegrees + 270) % 360
        panOffset = .zero
    }

    private func load(imageURL: URL) {
        let standardizedURL = imageURL.standardizedFileURL
        currentURL = standardizedURL
        resetViewTransform()
        rotationDegrees = 0
        zoomRequest = nil

        do {
            navigator = try FolderImageNavigator(currentImageURL: standardizedURL)
        } catch {
            navigator = nil
        }

        guard let loadedImage = NSImage(contentsOf: standardizedURL), loadedImage.isValid else {
            image = nil
            errorMessage = "PicSee could not open this image."
            return
        }

        image = loadedImage
        errorMessage = nil
    }

    private func requestZoom(multiplier: CGFloat) {
        nextZoomRequestID += 1
        zoomRequest = ImageZoomRequest(id: nextZoomRequestID, multiplier: multiplier)
    }
}

struct ImageParameterMetadata: Equatable {
    let size: String?
    let creationTime: String?
    let colorSpace: String?
    let resolution: String?
    let camera: String?
    let lens: String?
    let shutterSpeed: String?
    let aperture: String?
    let iso: String?
    let focalLength: String?
    let exposureCompensation: String?
    let flash: String?

    init?(url: URL) {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        self.init(url: url, properties: properties)
    }

    init?(url: URL, properties: [CFString: Any]) {
        let width = Self.pixelDimension(properties[kCGImagePropertyPixelWidth])
        let height = Self.pixelDimension(properties[kCGImagePropertyPixelHeight])
        let sizeValue = Self.imageSize(width: width, height: height)

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let creationTimeValue = Self.creationTime(
            exifDate: exif?[kCGImagePropertyExifDateTimeOriginal],
            digitizedDate: exif?[kCGImagePropertyExifDateTimeDigitized],
            tiffDate: tiff?[kCGImagePropertyTIFFDateTime],
            fileURL: url
        )
        let colorSpaceValue = Self.colorSpace(
            profileName: properties[kCGImagePropertyProfileName],
            colorModel: properties[kCGImagePropertyColorModel]
        )
        let resolutionValue = Self.resolution(
            width: Self.doubleValue(properties[kCGImagePropertyDPIWidth]),
            height: Self.doubleValue(properties[kCGImagePropertyDPIHeight])
        )
        let cameraValue = Self.camera(make: tiff?[kCGImagePropertyTIFFMake], model: tiff?[kCGImagePropertyTIFFModel])
        let lensValue = Self.stringValue(exif?[kCGImagePropertyExifLensModel])
        let shutterSpeedValue = Self.shutterSpeed(exif?[kCGImagePropertyExifExposureTime])
        let apertureValue = Self.aperture(exif?[kCGImagePropertyExifFNumber])
        let isoValue = Self.iso(exif?[kCGImagePropertyExifISOSpeedRatings])
        let focalLengthValue = Self.focalLength(exif?[kCGImagePropertyExifFocalLength])
        let exposureCompensationValue = Self.exposureCompensation(exif?[kCGImagePropertyExifExposureBiasValue])
        let flashValue = Self.flash(exif?[kCGImagePropertyExifFlash])

        guard [
            creationTimeValue,
            sizeValue,
            resolutionValue,
            colorSpaceValue,
            cameraValue,
            lensValue,
            shutterSpeedValue,
            apertureValue,
            isoValue,
            focalLengthValue,
            exposureCompensationValue,
            flashValue
        ].contains(where: { $0 != nil }) else { return nil }

        size = sizeValue
        creationTime = creationTimeValue
        colorSpace = colorSpaceValue
        resolution = resolutionValue
        camera = cameraValue
        lens = lensValue
        shutterSpeed = shutterSpeedValue
        aperture = apertureValue
        iso = isoValue
        focalLength = focalLengthValue
        exposureCompensation = exposureCompensationValue
        flash = flashValue
    }

    init?(properties: [CFString: Any]) {
        let width = Self.pixelDimension(properties[kCGImagePropertyPixelWidth])
        let height = Self.pixelDimension(properties[kCGImagePropertyPixelHeight])
        let sizeValue = Self.imageSize(width: width, height: height)

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let creationTimeValue = Self.creationTime(
            exifDate: exif?[kCGImagePropertyExifDateTimeOriginal],
            digitizedDate: exif?[kCGImagePropertyExifDateTimeDigitized],
            tiffDate: tiff?[kCGImagePropertyTIFFDateTime],
            fileURL: nil
        )
        let colorSpaceValue = Self.colorSpace(
            profileName: properties[kCGImagePropertyProfileName],
            colorModel: properties[kCGImagePropertyColorModel]
        )
        let resolutionValue = Self.resolution(
            width: Self.doubleValue(properties[kCGImagePropertyDPIWidth]),
            height: Self.doubleValue(properties[kCGImagePropertyDPIHeight])
        )
        let cameraValue = Self.camera(make: tiff?[kCGImagePropertyTIFFMake], model: tiff?[kCGImagePropertyTIFFModel])
        let lensValue = Self.stringValue(exif?[kCGImagePropertyExifLensModel])
        let shutterSpeedValue = Self.shutterSpeed(exif?[kCGImagePropertyExifExposureTime])
        let apertureValue = Self.aperture(exif?[kCGImagePropertyExifFNumber])
        let isoValue = Self.iso(exif?[kCGImagePropertyExifISOSpeedRatings])
        let focalLengthValue = Self.focalLength(exif?[kCGImagePropertyExifFocalLength])
        let exposureCompensationValue = Self.exposureCompensation(exif?[kCGImagePropertyExifExposureBiasValue])
        let flashValue = Self.flash(exif?[kCGImagePropertyExifFlash])

        guard [
            creationTimeValue,
            sizeValue,
            resolutionValue,
            colorSpaceValue,
            cameraValue,
            lensValue,
            shutterSpeedValue,
            apertureValue,
            isoValue,
            focalLengthValue,
            exposureCompensationValue,
            flashValue
        ].contains(where: { $0 != nil }) else { return nil }

        size = sizeValue
        creationTime = creationTimeValue
        colorSpace = colorSpaceValue
        resolution = resolutionValue
        camera = cameraValue
        lens = lensValue
        shutterSpeed = shutterSpeedValue
        aperture = apertureValue
        iso = isoValue
        focalLength = focalLengthValue
        exposureCompensation = exposureCompensationValue
        flash = flashValue
    }

    var displayRows: [(label: String, value: String)] {
        [
            ("创建时间", creationTime),
            ("尺寸", size),
            ("分辨率", resolution),
            ("色彩空间", colorSpace),
            ("相机", camera),
            ("镜头", lens),
            ("快门", shutterSpeed),
            ("光圈", aperture),
            ("ISO", iso),
            ("焦距", focalLength),
            ("曝光补偿", exposureCompensation),
            ("闪光灯", flash)
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    var displayText: String {
        return displayRows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    private static func camera(make: Any?, model: Any?) -> String? {
        let makeText = stringValue(make)
        let modelText = stringValue(model)

        switch (makeText, modelText) {
        case let (make?, model?) where model.localizedCaseInsensitiveContains(make):
            return model
        case let (make?, model?):
            return "\(make) \(model)"
        case let (make?, nil):
            return make
        case let (nil, model?):
            return model
        case (nil, nil):
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return "\(value)"
    }

    private static func shutterSpeed(_ value: Any?) -> String? {
        guard let seconds = doubleValue(value), seconds > 0 else { return nil }
        if seconds < 1 {
            let denominator = max(1, Int((1 / seconds).rounded()))
            return "1/\(denominator) s"
        }
        return "\(formatNumber(seconds)) s"
    }

    private static func aperture(_ value: Any?) -> String? {
        guard let number = doubleValue(value), number > 0 else { return nil }
        return "f/\(formatNumber(number))"
    }

    private static func iso(_ value: Any?) -> String? {
        if let values = value as? [Any], let first = values.first {
            return integerString(first)
        }
        return integerString(value)
    }

    private static func focalLength(_ value: Any?) -> String? {
        guard let number = doubleValue(value), number > 0 else { return nil }
        return "\(formatNumber(number)) mm"
    }

    private static func exposureCompensation(_ value: Any?) -> String? {
        guard let number = doubleValue(value) else { return nil }
        let formatted = formatNumber(number)
        return number > 0 ? "+\(formatted) EV" : "\(formatted) EV"
    }

    private static func flash(_ value: Any?) -> String? {
        guard let number = doubleValue(value) else { return nil }
        switch Int(number.rounded()) {
        case 0:
            return "否"
        case 1:
            return "闪光"
        default:
            return "\(Int(number.rounded()))"
        }
    }

    private static func pixelDimension(_ value: Any?) -> Int? {
        guard let number = doubleValue(value), number > 0 else { return nil }
        return Int(number.rounded())
    }

    private static func imageSize(width: Int?, height: Int?) -> String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width) × \(height) px"
    }

    private static func creationTime(exifDate: Any?, digitizedDate: Any?, tiffDate: Any?, fileURL: URL?) -> String? {
        [exifDate, digitizedDate, tiffDate]
            .compactMap { $0 }
            .compactMap(parseExifDate)
            .first
            .map(formatDate)
        ?? fileURL.flatMap(fileCreationDate).map(formatDate)
    }

    private static func colorSpace(profileName: Any?, colorModel: Any?) -> String? {
        stringValue(profileName) ?? stringValue(colorModel)
    }

    private static func resolution(width: Double?, height: Double?) -> String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(formatNumber(width))×\(formatNumber(height))"
    }

    private static func parseExifDate(_ value: Any) -> Date? {
        guard let string = stringValue(value) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm"
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return formatter.string(from: date)
    }

    private static func fileCreationDate(_ url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return values.creationDate ?? values.contentModificationDate
    }

    private static func integerString(_ value: Any?) -> String? {
        guard let number = doubleValue(value) else { return nil }
        return "\(Int(number.rounded()))"
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func formatNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

private extension URL {
    var fileByteCount: Int64? {
        guard let value = try? resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(value)
    }
}

private extension NSImage {
    var pixelSize: (width: Int, height: Int)? {
        let bitmapRepresentations = representations.compactMap { representation -> (width: Int, height: Int)? in
            guard representation.pixelsWide > 0, representation.pixelsHigh > 0 else { return nil }
            return (representation.pixelsWide, representation.pixelsHigh)
        }

        if let largestRepresentation = bitmapRepresentations.max(by: { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }) {
            return largestRepresentation
        }

        guard size.width > 0, size.height > 0 else { return nil }
        return (Int(size.width.rounded()), Int(size.height.rounded()))
    }
}
