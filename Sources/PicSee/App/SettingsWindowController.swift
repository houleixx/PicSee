import AppKit
import Combine
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case defaultApps
    case browsing
    case about
    var id: Self { self }
    var title: String {
        switch self {
        case .defaultApps: L10n.text("打开方式")
        case .browsing: L10n.text("显示设置")
        case .about: L10n.text("关于")
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .defaultApps
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let contentSize = NSSize(width: 724, height: 548)
    let navigation = SettingsNavigation()
    private let preferences: ViewerPreferences
    private var pinningController: WindowPinningController?
    private var appearanceObservation: AnyCancellable?
    private var languageObservation: AnyCancellable?

    init(
        preferences: ViewerPreferences = .shared,
        updateChecker: UpdateChecker?,
        defaultAppHandler: any DefaultImageAppHandling,
        captureFixedWindowFrame: @escaping () -> Void
    ) {
        self.preferences = preferences
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = L10n.text("PicSee 设置")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: SettingsView(
            navigation: navigation,
            preferences: preferences,
            updateChecker: updateChecker,
            defaultAppHandler: defaultAppHandler,
            captureFixedWindowFrame: captureFixedWindowFrame
        ))
        // Attaching a hosting controller can reset the content size to zero
        // before its first layout pass. Restore the intended size before showing.
        window.setContentSize(Self.contentSize)
        languageObservation = LanguageSettings.shared.$revision.sink { [weak window] _ in
            window?.title = L10n.text("PicSee 设置")
        }
        pinningController = WindowPinningController(window: window, role: .settings, preferences: preferences)
        appearanceObservation = preferences.$snapshot.map(\.theme).removeDuplicates()
            .sink { [weak window] theme in window?.appearance = theme.appearance }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(page: SettingsPage? = nil) {
        preferences.reload()
        if let page { navigation.page = page }
        let targetScreen = NSApp.keyWindow?.screen ?? window?.screen ?? NSScreen.main
        // Hosting can finalize the window size on its first display.
        window?.makeKeyAndOrderFront(nil)
        if let window, let screen = targetScreen {
            window.contentView?.layoutSubtreeIfNeeded()
            let visibleFrame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

private struct SettingsView: View {
    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var preferences: ViewerPreferences
    let updateChecker: UpdateChecker?
    let defaultAppHandler: any DefaultImageAppHandling
    let captureFixedWindowFrame: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.text("设置页面"), selection: $navigation.page) {
                ForEach(SettingsPage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .id(language.revision)
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: L10n.languageCode == "zh-Hans" ? 300 : 360)
            .padding(.vertical, 12)

            Divider()

            // Keep each page's transient state when switching tabs.
            ZStack {
                BrowsingSettingsView(preferences: preferences, captureFixedWindowFrame: captureFixedWindowFrame)
                    .opacity(navigation.page == .browsing ? 1 : 0)
                    .disabled(navigation.page != .browsing)
                    .allowsHitTesting(navigation.page == .browsing)
                    .accessibilityHidden(navigation.page != .browsing)
                DefaultAppsSettingsView(
                    handler: defaultAppHandler, theme: preferences.snapshot.theme,
                    isActive: navigation.page == .defaultApps
                )
                    .opacity(navigation.page == .defaultApps ? 1 : 0)
                    .disabled(navigation.page != .defaultApps)
                    .allowsHitTesting(navigation.page == .defaultApps)
                    .accessibilityHidden(navigation.page != .defaultApps)
                AboutSettingsView(updateChecker: updateChecker)
                    .opacity(navigation.page == .about ? 1 : 0)
                    .disabled(navigation.page != .about)
                    .allowsHitTesting(navigation.page == .about)
                    .accessibilityHidden(navigation.page != .about)
            }
        }
        .frame(width: SettingsWindowController.contentSize.width, height: SettingsWindowController.contentSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, L10n.locale)
    }
}

private struct BrowsingSettingsView: View {
    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject var preferences: ViewerPreferences
    let captureFixedWindowFrame: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsCard(L10n.text("外观")) {
                    HStack {
                        Text(L10n.text("语言")).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker(L10n.text("语言"), selection: Binding(
                            get: { language.selection }, set: { language.set($0) }
                        )) {
                            ForEach(AppLanguage.allCases, id: \.rawValue) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .id(language.revision)
                        .frame(width: 270)
                    }
                    .padding(.vertical, 4)
                    Divider()
                    HStack {
                        Text(L10n.text("主题")).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker(L10n.text("主题"), selection: Binding(
                            get: { preferences.snapshot.theme },
                            set: { preferences.setTheme($0) }
                        )) {
                            ForEach(ViewerTheme.allCases, id: \.rawValue) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .id(language.revision)
                        .pickerStyle(.segmented)
                        .frame(width: 270)
                    }
                    .padding(.vertical, 4)
                }

                settingsCard(L10n.text("界面元素")) {
                    preferenceRow(L10n.text("显示标题栏"), keyPath: \.titleBarVisible)
                    Divider()
                    preferenceRow(L10n.text("显示缩略图"), detail: L10n.text("图片放大超出窗口时，显示定位缩略图"), keyPath: \.minimapEnabled)
                    Divider()
                    preferenceRow(L10n.text("显示文件信息"), detail: L10n.text("隐藏标题栏时，在左上角显示文件信息"), keyPath: \.fileInfoVisible)
                    Divider()
                    preferenceRow(L10n.text("显示底部工具栏"), keyPath: \.toolbarVisible)
                    Divider()
                    preferenceRow(L10n.text("显示图片参数"), detail: L10n.text("在右侧显示图片详细参数"), keyPath: \.imageParametersVisible)
                }

                settingsCard(L10n.text("图片浏览")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.text("全屏时小图显示方式")).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker(L10n.text("全屏时小图显示方式"), selection: Binding(
                                get: { preferences.snapshot.fullScreenSmallImageMode },
                                set: { preferences.setFullScreenSmallImageMode($0) }
                            )) {
                                ForEach(FullScreenSmallImageMode.allCases, id: \.rawValue) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .id(language.revision)
                            .frame(width: 200)
                        }
                        if preferences.snapshot.fullScreenSmallImageMode == .smart {
                            HStack {
                                Text(L10n.text("最大放大倍数")).font(.system(size: 13))
                                Spacer()
                                Picker(L10n.text("最大放大倍数"), selection: Binding(
                                    get: { preferences.snapshot.maximumSmallImageScale },
                                    set: { preferences.setMaximumSmallImageScale($0) }
                                )) {
                                    ForEach(FullScreenSmallImagePreference.scaleOptions, id: \.self) { scale in
                                        Text("\(scale.formatted(.number))×").tag(scale)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 200)
                            }
                        }
                        Text(L10n.text("仅影响全屏下的小图，大图始终按比例缩小，完整显示"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    Divider()
                    preferenceRow(
                        L10n.text("图片切换动画"),
                        detail: L10n.text("切换图片时显示过渡效果，关闭后直接显示下一张"),
                        keyPath: \.imageNavigationAnimationEnabled
                    )
                }

                settingsCard(L10n.text("窗口")) {
                    preferenceRow(
                        L10n.text("单窗口看图"),
                        detail: L10n.text("再次打开图片时，在已有窗口中显示"),
                        keyPath: \.singleWindowEnabled
                    )
                    Divider()
                    preferenceRow(
                        L10n.text("窗口置顶"),
                        detail: L10n.text("所有看图窗口保持在普通窗口上方，切换应用时仍然显示"),
                        keyPath: \.alwaysOnTopEnabled
                    )
                    Divider()
                    preferenceRow(
                        L10n.text("固定窗口大小和位置"),
                        detail: L10n.text("开启时记住当前图片窗口，之后打开图片时沿用"),
                        keyPath: \.fixedWindowEnabled
                    )
                    Divider()
                    preferenceRow(
                        L10n.text("右键手势关闭图片"),
                        detail: L10n.text("按住右键向下再向右划动（↓ →），松开关闭"),
                        keyPath: \.rightMouseCloseGestureEnabled
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func preferenceRow(
        _ title: String,
        detail: String? = nil,
        keyPath: WritableKeyPath<ViewerPreferencesSnapshot, Bool>
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle(title, isOn: Binding(
                get: { preferences.snapshot[keyPath: keyPath] },
                set: { value in
                    if keyPath == \.fixedWindowEnabled && value { captureFixedWindowFrame() }
                    preferences.set(keyPath, to: value)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

private func settingsCard<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SettingsCardSurface())
    }
}

private struct SettingsCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
    }

    private var backgroundColor: Color {
        // Match the native default-open panel in both appearances.
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)!
        var color = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.blended(withFraction: 0.035, of: .labelColor)
                ?? .windowBackgroundColor
        }
        return Color(nsColor: color)
    }
}

private struct DefaultAppsSettingsView: NSViewControllerRepresentable {
    let handler: any DefaultImageAppHandling
    let theme: ViewerTheme
    let isActive: Bool

    func makeNSViewController(context: Context) -> DefaultImageAppSettingsViewController {
        DefaultImageAppSettingsViewController(handler: handler)
    }

    func updateNSViewController(_ controller: DefaultImageAppSettingsViewController, context: Context) {
        controller.applyTheme(theme)
        // Hidden AppKit controls must not handle Return from another settings page.
        controller.view.isHidden = !isActive
    }
}

private struct AboutSettingsView: View {
    @ObservedObject private var language = LanguageSettings.shared
    @State private var isFeedbackHovered = false
    let updateChecker: UpdateChecker?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .padding(.top, 64)
                    .padding(.bottom, 24)
            }

            HStack {
                Spacer()
                Link(destination: AppMenu.feedbackURL) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 11, weight: .regular))
                            .accessibilityHidden(true)
                        Text(L10n.text("问题反馈"))
                            .font(.system(size: 12, weight: .regular))
                            .underline(isFeedbackHovered)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .medium))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color(nsColor: .linkColor))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    guard hovering != isFeedbackHovered else { return }
                    isFeedbackHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onDisappear {
                    if isFeedbackHovered {
                        isFeedbackHovered = false
                        NSCursor.pop()
                    }
                }
                .help(L10n.text("前往小红书反馈"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("PicSee").font(.system(size: 18, weight: .semibold))
                    Text(AppMenu.versionSummary(from: Bundle.main.infoDictionary ?? [:]))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text(L10n.text("下载地址：")).foregroundStyle(.secondary)
                let websiteURL = AppMenu.releasePageURL(from: Bundle.main.infoDictionary ?? [:])
                let websiteLabel = websiteURL.absoluteString.hasSuffix("/")
                    ? String(websiteURL.absoluteString.dropLast()) : websiteURL.absoluteString
                Link(websiteLabel, destination: websiteURL)
                    .buttonStyle(.link)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
            .font(.system(size: 12))

            Text(L10n.text("感谢“大脑袋范同学”提出的优化建议"))
                .font(.system(size: 11)).foregroundStyle(.secondary)

            if let updateChecker {
                SettingsUpdateView(updateChecker: updateChecker)
            } else {
                Text(L10n.text("当前构建缺少版本信息，无法检查更新。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
    }
}

private struct SettingsUpdateView: View {
    @ObservedObject private var language = LanguageSettings.shared
    @ObservedObject var updateChecker: UpdateChecker
    @State private var isUpToDate = false

    var body: some View {
        VStack(spacing: 12) {
            Picker(L10n.text("自动检查更新："), selection: Binding(
                get: { updateChecker.frequency }, set: { updateChecker.setFrequency($0) }
            )) {
                ForEach(UpdateCheckFrequency.allCases) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            .id(language.revision)
            .fixedSize()

            Button(updateChecker.checkError == nil ? L10n.text("检查更新") : L10n.text("重试检查")) {
                Task { isUpToDate = await updateChecker.checkForUpdatesManually() }
            }
            .buttonStyle(.bordered)
            .disabled(updateChecker.status == .checking || updateChecker.status == .downloading)

            updateStatus
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
        }
        .font(.system(size: 12))
        .controlSize(.regular)
        .onChange(of: updateChecker.status) { _, status in
            if status == .checking { isUpToDate = false }
        }
    }

    private var updateStatus: some View {
        VStack(spacing: 12) {
            if updateChecker.status == .checking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("正在检查更新…"))
                }
            } else if let error = updateChecker.checkError {
                Text(error).foregroundStyle(.secondary)
            } else if let update = updateChecker.availableUpdate {
                Text(L10n.text("发现新版本 %1$@", String(describing: update.version.displayString)))
            } else if isUpToDate {
                HStack(spacing: 6) {
                    Image(nsImage: PhosphorImages.check)
                        .resizable().renderingMode(.template).scaledToFit()
                        .frame(width: 16, height: 16).foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text(L10n.text("已经是最新版本了"))
                }
            }

            if updateChecker.status == .downloading {
                ProgressView(value: updateChecker.downloadProgress ?? 0)
                    .frame(width: 220)
                Text(L10n.text("正在下载更新…")).foregroundStyle(.secondary)
            } else if updateChecker.availableUpdate != nil {
                if updateChecker.status == .failed {
                    Text(updateChecker.downloadError ?? L10n.text("下载失败，请重试。")).foregroundStyle(.secondary)
                }
                Button(updateChecker.status == .failed ? L10n.text("重试下载") : L10n.text("下载并安装")) {
                    Task { await updateChecker.downloadAvailableUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updateChecker.status == .checking)
            }

        }
    }
}
