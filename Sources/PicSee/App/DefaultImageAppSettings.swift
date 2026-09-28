import CoreServices
import Foundation
import OSLog

struct DefaultImageFormat: Equatable, Identifiable {
    let id: String
    let label: String
    let contentType: String
    let extensions: String

    init(label: String, contentType: String, extensions: String) {
        self.id = contentType
        self.label = label
        self.contentType = contentType
        self.extensions = extensions
    }
}

enum DefaultImageAppSettings {
    static let formats: [DefaultImageFormat] = [
        DefaultImageFormat(label: "JPEG", contentType: "public.jpeg", extensions: "jpg, jpeg"),
        DefaultImageFormat(label: "PNG", contentType: "public.png", extensions: "png"),
        DefaultImageFormat(label: "GIF", contentType: "com.compuserve.gif", extensions: "gif"),
        DefaultImageFormat(label: "HEIC", contentType: "public.heic", extensions: "heic"),
        DefaultImageFormat(label: "TIFF", contentType: "public.tiff", extensions: "tif, tiff"),
        DefaultImageFormat(label: "BMP", contentType: "com.microsoft.bmp", extensions: "bmp"),
        DefaultImageFormat(label: "WebP", contentType: "org.webmproject.webp", extensions: "webp"),
        DefaultImageFormat(label: "RAW", contentType: "public.camera-raw-image", extensions: "dng, cr2, cr3, nef, arw, raf, rw2"),
        DefaultImageFormat(label: "AVIF", contentType: "public.avif", extensions: "avif"),
        DefaultImageFormat(label: "SVG", contentType: "public.svg-image", extensions: "svg"),
        DefaultImageFormat(label: "ICO", contentType: "com.microsoft.ico", extensions: "ico"),
        DefaultImageFormat(label: "ICNS", contentType: "com.apple.icns", extensions: "icns"),
        DefaultImageFormat(label: "JPEG 2000", contentType: "public.jpeg-2000", extensions: "jp2, j2k, jpf, jpx"),
        DefaultImageFormat(label: "Photoshop", contentType: "com.adobe.photoshop-image", extensions: "psd, psb"),
        DefaultImageFormat(label: "TGA", contentType: "com.truevision.tga-image", extensions: "tga"),
        DefaultImageFormat(label: "DDS", contentType: "com.microsoft.dds", extensions: "dds"),
        DefaultImageFormat(label: "OpenEXR", contentType: "com.ilm.openexr-image", extensions: "exr"),
        DefaultImageFormat(label: "Radiance HDR", contentType: "public.radiance", extensions: "hdr"),
        DefaultImageFormat(label: "JPEG XL", contentType: "public.jpeg-xl", extensions: "jxl")
    ]

    static var fallbackInstructions: String { L10n.text("其他格式可在 Finder 的“显示简介”→“打开方式”中选择 PicSee，并点“全部更改…”。") }

    static func shouldShowSettingsWindowAfterLaunch(didReceiveOpenRequest: Bool, hasOpenViewer: Bool) -> Bool {
        !didReceiveOpenRequest && !hasOpenViewer
    }

    static func apply(
        _ formats: [DefaultImageFormat],
        using handler: any DefaultImageAppHandling
    ) -> DefaultImageAppApplyResult {
        var completed: [DefaultImageFormat] = []
        var failures: [DefaultImageAppApplyResult.Failure] = []
        for format in formats {
            do {
                if !handler.isDefaultViewer(for: format) {
                    try handler.setDefaultViewer(for: format)
                }
                completed.append(format)
            } catch {
                failures.append(.init(format: format, error: error))
            }
        }
        return DefaultImageAppApplyResult(completed: completed, failures: failures)
    }
}

struct DefaultImageAppApplyResult {
    struct Failure {
        let format: DefaultImageFormat
        private let fallback: String
        private let error: Error?
        var message: String { error.map(L10n.errorDescription) ?? fallback }
        init(format: DefaultImageFormat, message: String) {
            self.format = format
            fallback = message
            error = nil
        }
        init(format: DefaultImageFormat, error: Error) {
            self.format = format
            self.error = error
            fallback = ""
        }
    }

    let completed: [DefaultImageFormat]
    let failures: [Failure]

    var statusMessage: String {
        if failures.isEmpty {
            return L10n.text("已设置 %1$@ 种格式。", String(describing: completed.count))
        }
        return L10n.text("已完成 %1$@ 种，%2$@ 种失败。", String(describing: completed.count), String(describing: failures.count))
    }

    var failureDetails: String {
        failures.map { "\($0.format.label)：\($0.message)" }.joined(separator: "\n")
    }
}

protocol DefaultImageAppHandling {
    func isDefaultViewer(for format: DefaultImageFormat) -> Bool
    func setDefaultViewer(for format: DefaultImageFormat) throws
}

enum DefaultImageAppError: LocalizedError {
    case missingBundleIdentifier
    case launchServicesFailed(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return L10n.text("无法读取当前应用的 Bundle ID。")
        case let .launchServicesFailed(status, contentType):
            return L10n.text("设置 %1$@ 默认打开方式失败，错误码 %2$@。", String(describing: contentType), String(describing: status))
        }
    }
}

struct LaunchServicesDefaultImageAppHandler: DefaultImageAppHandling {
    private let bundleIdentifier: String
    private static let logger = Logger(subsystem: "local.picsee.viewer", category: "DefaultImageApp")

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            throw DefaultImageAppError.missingBundleIdentifier
        }
        self.bundleIdentifier = bundleIdentifier
    }

    func isDefaultViewer(for format: DefaultImageFormat) -> Bool {
        guard
            let handler = LSCopyDefaultRoleHandlerForContentType(
                format.contentType as CFString,
                LSRolesMask.viewer
            )?.takeRetainedValue() as String?
        else {
            return false
        }

        return handler == bundleIdentifier
    }

    func setDefaultViewer(for format: DefaultImageFormat) throws {
        let status = LSSetDefaultRoleHandlerForContentType(
            format.contentType as CFString,
            LSRolesMask.viewer,
            bundleIdentifier as CFString
        )

        guard status == noErr else {
            Self.logger.error("Setting default viewer failed: type=\(format.contentType, privacy: .public), status=\(status)")
            throw DefaultImageAppError.launchServicesFailed(status, format.contentType)
        }
    }
}
