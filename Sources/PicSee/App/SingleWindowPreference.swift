import AppKit

/// Shared by settings and context menus, including existing independent instances.
enum SingleWindowPreference {
    static let enabledKey = "PicSee.SingleWindowEnabled"
    static let ownerKey = "PicSee.SingleWindowOwner"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    @MainActor
    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        guard enabled != isEnabled(in: defaults) else { return }
        if enabled, defaults === UserDefaults.standard {
            // The window whose menu/settings enabled the mode becomes the receiver.
            defaults.set(SingleWindowRouter.identity(of: .current), forKey: ownerKey)
        } else if !enabled {
            defaults.removeObject(forKey: ownerKey)
        }
        defaults.set(enabled, forKey: enabledKey)
        ViewerPreferenceChange.post(in: defaults)
    }
}

@MainActor
enum SingleWindowRouter {
    struct Instance: Equatable {
        let pid: pid_t
        let launchedAt: TimeInterval
        var identity: String { "\(pid):\(launchedAt)" }
    }

    static func identity(of app: NSRunningApplication) -> String {
        Instance(pid: app.processIdentifier, launchedAt: app.launchDate?.timeIntervalSince1970 ?? 0).identity
    }

    /// Stable ordering gives simultaneous open requests the same destination.
    /// Including the launch date prevents a reused PID from inheriting ownership.
    static func receiver(in instances: [Instance], preferredIdentity: String?) -> Instance? {
        instances.first { $0.identity == preferredIdentity } ?? instances.min {
            if $0.launchedAt != $1.launchedAt { return $0.launchedAt < $1.launchedAt }
            return $0.pid < $1.pid
        }
    }

    static func receiverPID(defaults: UserDefaults = .standard) -> pid_t {
        guard let bundleID = Bundle.main.bundleIdentifier else { return ProcessInfo.processInfo.processIdentifier }
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated && $0.bundleURL == Bundle.main.bundleURL }
            .map { Instance(pid: $0.processIdentifier, launchedAt: $0.launchDate?.timeIntervalSince1970 ?? 0) }
        return receiver(in: instances, preferredIdentity: defaults.string(forKey: SingleWindowPreference.ownerKey))?.pid
            ?? ProcessInfo.processInfo.processIdentifier
    }

    static func forward(_ url: URL, to pid: pid_t) throws {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        let files = NSAppleEventDescriptor.list()
        files.insert(NSAppleEventDescriptor(fileURL: url), at: 1)
        event.setParam(files, forKeyword: AEKeyword(keyDirectObject))
        // A queued event also works while the destination is launching or showing a sheet.
        _ = try event.sendEvent(options: [.noReply, .neverInteract], timeout: 1)
    }
}
