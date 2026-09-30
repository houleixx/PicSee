import Foundation
import ImageIO

struct ImageParameterMetadata: Equatable, Sendable {
    let size: String?
    private let creationDate: Date?
    var creationTime: String? { creationDate.map(Self.formatDate) }
    let colorSpace: String?
    let resolution: String?
    let camera: String?
    let lens: String?
    let shutterSpeed: String?
    let aperture: String?
    let iso: String?
    let focalLength: String?
    let exposureCompensation: String?
    private let flashValue: Int?
    var flash: String? { Self.flash(flashValue) }

    init?(url: URL) {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        self.init(url: url, properties: properties)
    }

    init?(url: URL?, properties: [CFString: Any]) {
        let width = Self.pixelDimension(properties[kCGImagePropertyPixelWidth])
        let height = Self.pixelDimension(properties[kCGImagePropertyPixelHeight])
        let sizeValue = Self.imageSize(width: width, height: height)

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let creationDateValue = Self.creationDate(
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
        let flashValue = Self.doubleValue(exif?[kCGImagePropertyExifFlash]).map { Int($0.rounded()) }

        guard [
            creationDateValue.map { String(describing: $0) },
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
            flashValue.map { String($0) }
        ].contains(where: { $0 != nil }) else { return nil }

        size = sizeValue
        creationDate = creationDateValue
        colorSpace = colorSpaceValue
        resolution = resolutionValue
        camera = cameraValue
        lens = lensValue
        shutterSpeed = shutterSpeedValue
        aperture = apertureValue
        iso = isoValue
        focalLength = focalLengthValue
        exposureCompensation = exposureCompensationValue
        self.flashValue = flashValue
    }

    init?(properties: [CFString: Any]) {
        self.init(url: nil, properties: properties)
    }

    var displayRows: [(label: String, value: String)] {
        [
            (L10n.text("创建时间"), creationTime),
            (L10n.text("尺寸"), size),
            (L10n.text("分辨率"), resolution),
            (L10n.text("色彩空间"), colorSpace),
            (L10n.text("相机"), camera),
            (L10n.text("镜头"), lens),
            (L10n.text("快门"), shutterSpeed),
            (L10n.text("光圈"), aperture),
            ("ISO", iso),
            (L10n.text("焦距"), focalLength),
            (L10n.text("曝光补偿"), exposureCompensation),
            (L10n.text("闪光灯"), flash)
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
            return L10n.text("否")
        case 1:
            return L10n.text("闪光")
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

    private static func creationDate(exifDate: Any?, digitizedDate: Any?, tiffDate: Any?, fileURL: URL?) -> Date? {
        [exifDate, digitizedDate, tiffDate]
            .compactMap { $0 }
            .compactMap(parseExifDate)
            .first
        ?? fileURL.flatMap(fileCreationDate)
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
        formatter.locale = L10n.locale
        formatter.timeZone = .current
        formatter.dateFormat = L10n.text("yyyy年MM月dd日 HH:mm")
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

