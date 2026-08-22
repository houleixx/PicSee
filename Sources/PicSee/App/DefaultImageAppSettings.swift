import CoreServices
import Foundation

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
        DefaultImageFormat(label: "RAW", contentType: "public.camera-raw-image", extensions: "dng, cr2, cr3, nef, arw, raf, rw2")
    ]

    static let fallbackInstructions = "其他格式可在 Finder 的“显示简介”→“打开方式”中选择 PicSee，并点“全部更改…”。"

    static func shouldShowSettingsWindowAfterLaunch(didReceiveOpenRequest: Bool, hasOpenViewer: Bool) -> Bool {
        !didReceiveOpenRequest && !hasOpenViewer
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
            return "无法读取当前应用的 Bundle ID。"
        case let .launchServicesFailed(status, contentType):
            return "设置 \(contentType) 默认打开方式失败，错误码 \(status)。"
        }
    }
}

struct LaunchServicesDefaultImageAppHandler: DefaultImageAppHandling {
    private let bundleIdentifier: String

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
            throw DefaultImageAppError.launchServicesFailed(status, format.contentType)
        }
    }
}
