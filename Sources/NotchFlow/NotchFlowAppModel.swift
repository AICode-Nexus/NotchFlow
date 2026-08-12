import Carbon
import Combine
import Foundation

@MainActor
final class NotchFlowAppModel: ObservableObject {
    static let shared = NotchFlowAppModel()
    static let showPanelOnLaunchArgument = "--show-panel-on-launch"

    let settings: AppSettings
    let nowPlaying: NowPlayingService
    let weather: WeatherForecastService
    let battery: BatteryStatusService
    let clipboardHistory: ClipboardHistoryService
    let wallpaper: WallpaperRefreshService
    let scriptShortcuts: ScriptShortcutStore
    let localAppSearch: LocalAppSearchService
    let launchAtLogin: LaunchAtLoginManager
    let chargeLimit: ChargeLimitService
    let aiTokenUsage: AITokenUsageService
    let screenHealth: ScreenHealthService
    let panelController: NotchPanelController
    let hotKeyManager: GlobalHotKeyManager

    private var isStarted = false
    private var nowPlayingSettingCancellable: AnyCancellable?
    private var panelStateCancellable: AnyCancellable?

    private init() {
        settings = AppSettings()
        nowPlaying = NowPlayingService()
        weather = WeatherForecastService(settings: settings)
        battery = BatteryStatusService()
        clipboardHistory = ClipboardHistoryService(settings: settings)
        wallpaper = WallpaperRefreshService(settings: settings)
        scriptShortcuts = ScriptShortcutStore()
        localAppSearch = LocalAppSearchService()
        launchAtLogin = LaunchAtLoginManager()
        chargeLimit = ChargeLimitService(settings: settings)
        aiTokenUsage = AITokenUsageService(settings: settings)
        screenHealth = ScreenHealthService(settings: settings)
        panelController = NotchPanelController(
            settings: settings,
            nowPlaying: nowPlaying,
            weather: weather,
            battery: battery,
            clipboardHistory: clipboardHistory,
            wallpaper: wallpaper,
            scriptShortcuts: scriptShortcuts,
            localAppSearch: localAppSearch,
            chargeLimit: chargeLimit,
            aiTokenUsage: aiTokenUsage,
            screenHealth: screenHealth
        )
        hotKeyManager = GlobalHotKeyManager(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak panelController] in
            panelController?.toggleFromHotKey()
        }

        panelStateCancellable = panelController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    var menuBarIconName: String {
        if panelController.isPinned {
            return "pin.fill"
        }

        if panelController.isExpanded {
            return "capsule.portrait.fill"
        }

        return "capsule.portrait"
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        panelController.start()
        bindNowPlayingSetting()
        weather.start()
        battery.start()
        clipboardHistory.start()
        wallpaper.start()
        localAppSearch.start()
        hotKeyManager.register()
        chargeLimit.start()
        aiTokenUsage.start()
        screenHealth.start()

        if ProcessInfo.processInfo.arguments.contains(Self.showPanelOnLaunchArgument) {
            Task { @MainActor in
                panelController.expandAndPin()
            }
        }

        Task {
            await launchAtLogin.refreshStatus()
        }
    }

    func stop() {
        isStarted = false
        nowPlayingSettingCancellable?.cancel()
        nowPlayingSettingCancellable = nil
        nowPlaying.stop()
        weather.stop()
        battery.stop()
        clipboardHistory.stop()
        wallpaper.stop()
        localAppSearch.stop()
        hotKeyManager.unregister()
        chargeLimit.stop()
        aiTokenUsage.stop()
        screenHealth.stop()
    }

    func togglePanelPinState() {
        panelController.toggleFromHotKey()
    }

    func collapsePanel() {
        panelController.collapseToCompact()
    }

    func repositionPanel() {
        panelController.reposition()
    }

    private func bindNowPlayingSetting() {
        guard nowPlayingSettingCancellable == nil else {
            return
        }

        nowPlayingSettingCancellable = settings.$nowPlayingEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self, self.isStarted else {
                    return
                }

                if isEnabled {
                    self.nowPlaying.start()
                } else {
                    self.nowPlaying.stop()
                }
            }
    }
}
