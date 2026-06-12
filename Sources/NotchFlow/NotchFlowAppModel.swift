import Carbon
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
    let panelController: NotchPanelController
    let hotKeyManager: GlobalHotKeyManager

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
            aiTokenUsage: aiTokenUsage
        )
        hotKeyManager = GlobalHotKeyManager(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak panelController] in
            panelController?.toggleFromHotKey()
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
        panelController.start()
        nowPlaying.start()
        weather.start()
        battery.start()
        clipboardHistory.start()
        wallpaper.start()
        localAppSearch.start()
        hotKeyManager.register()
        chargeLimit.start()
        aiTokenUsage.start()

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
        nowPlaying.stop()
        weather.stop()
        battery.stop()
        clipboardHistory.stop()
        wallpaper.stop()
        hotKeyManager.unregister()
        chargeLimit.stop()
        aiTokenUsage.stop()
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
}
