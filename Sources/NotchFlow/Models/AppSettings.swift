import Foundation

enum QuickLaunchLayoutMode: String, CaseIterable, Identifiable {
    case grid
    case carousel

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .grid:
            return "两行"
        case .carousel:
            return "一行"
        }
    }
}

enum PanelAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }
}

enum PanelTextSizePreset: String, CaseIterable, Identifiable {
    case regular
    case large
    case extraLarge

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .regular:
            return "标准"
        case .large:
            return "偏大"
        case .extraLarge:
            return "更大"
        }
    }

    var scale: Double {
        switch self {
        case .regular:
            return 1.0
        case .large:
            return 1.08
        case .extraLarge:
            return 1.16
        }
    }
}

enum LogRetentionPreset: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    case ninetyDays = 90

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .sevenDays:
            return "7 天"
        case .fourteenDays:
            return "14 天"
        case .thirtyDays:
            return "30 天"
        case .ninetyDays:
            return "90 天"
        }
    }
}

enum WallpaperRefreshIntervalPreset: Int, CaseIterable, Identifiable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .fiveMinutes:
            return "5 分钟"
        case .fifteenMinutes:
            return "15 分钟"
        case .thirtyMinutes:
            return "30 分钟"
        case .oneHour:
            return "1 小时"
        case .twoHours:
            return "2 小时"
        case .fourHours:
            return "4 小时"
        }
    }

    var timeInterval: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

enum ScreenBreakReminderThresholdPreset: Int, CaseIterable, Identifiable {
    case twentyMinutes = 20
    case fortyFiveMinutes = 45
    case sixtyMinutes = 60

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .twentyMinutes:
            return "20 分钟"
        case .fortyFiveMinutes:
            return "45 分钟"
        case .sixtyMinutes:
            return "60 分钟"
        }
    }

    var timeInterval: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let hoverToExpand = "HoverToExpand"
        static let autoHideDelay = "AutoHideDelay"
        static let weatherEnabled = "WeatherEnabled"
        static let deviceBatteryEnabled = "DeviceBatteryEnabled"
        static let clipboardHistoryEnabled = "ClipboardHistoryEnabled"
        static let wallpaperRefreshEnabled = "WallpaperRefreshEnabled"
        static let wallpaperAutoRefreshEnabled = "WallpaperAutoRefreshEnabled"
        static let wallpaperRefreshIntervalPreset = "WallpaperRefreshIntervalPreset"
        static let quickLaunchLayoutMode = "QuickLaunchLayoutMode"
        static let quickLaunchShowsLabels = "QuickLaunchShowsLabels"
        static let panelAppearanceMode = "PanelAppearanceMode"
        static let panelTextSizePreset = "PanelTextSizePreset"
        static let chargeLimitEnabled = "ChargeLimitEnabled"
        static let aiTokenUsageEnabled = "AITokenUsageEnabled"
        static let nowPlayingEnabled = "NowPlayingEnabled"
        static let logRetentionPreset = "LogRetentionPreset"
        static let screenHealthEnabled = "ScreenHealthEnabled"
        static let screenBreakReminderEnabled = "ScreenBreakReminderEnabled"
        static let screenBreakReminderThresholdPreset = "ScreenBreakReminderThresholdPreset"
    }

    @Published var hoverToExpand: Bool {
        didSet {
            UserDefaults.standard.set(hoverToExpand, forKey: Keys.hoverToExpand)
        }
    }

    @Published var autoHideDelay: Double {
        didSet {
            UserDefaults.standard.set(autoHideDelay, forKey: Keys.autoHideDelay)
        }
    }

    @Published var weatherEnabled: Bool {
        didSet {
            UserDefaults.standard.set(weatherEnabled, forKey: Keys.weatherEnabled)
        }
    }

    @Published var deviceBatteryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(deviceBatteryEnabled, forKey: Keys.deviceBatteryEnabled)
        }
    }

    @Published var clipboardHistoryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(clipboardHistoryEnabled, forKey: Keys.clipboardHistoryEnabled)
        }
    }

    @Published var wallpaperRefreshEnabled: Bool {
        didSet {
            UserDefaults.standard.set(wallpaperRefreshEnabled, forKey: Keys.wallpaperRefreshEnabled)
        }
    }

    @Published var wallpaperAutoRefreshEnabled: Bool {
        didSet {
            UserDefaults.standard.set(wallpaperAutoRefreshEnabled, forKey: Keys.wallpaperAutoRefreshEnabled)
        }
    }

    @Published var wallpaperRefreshIntervalPreset: WallpaperRefreshIntervalPreset {
        didSet {
            UserDefaults.standard.set(wallpaperRefreshIntervalPreset.rawValue, forKey: Keys.wallpaperRefreshIntervalPreset)
        }
    }

    @Published var quickLaunchLayoutMode: QuickLaunchLayoutMode {
        didSet {
            UserDefaults.standard.set(quickLaunchLayoutMode.rawValue, forKey: Keys.quickLaunchLayoutMode)
        }
    }

    @Published var quickLaunchShowsLabels: Bool {
        didSet {
            UserDefaults.standard.set(quickLaunchShowsLabels, forKey: Keys.quickLaunchShowsLabels)
        }
    }

    @Published var panelAppearanceMode: PanelAppearanceMode {
        didSet {
            UserDefaults.standard.set(panelAppearanceMode.rawValue, forKey: Keys.panelAppearanceMode)
        }
    }

    @Published var panelTextSizePreset: PanelTextSizePreset {
        didSet {
            UserDefaults.standard.set(panelTextSizePreset.rawValue, forKey: Keys.panelTextSizePreset)
        }
    }

    @Published var chargeLimitEnabled: Bool {
        didSet {
            UserDefaults.standard.set(chargeLimitEnabled, forKey: Keys.chargeLimitEnabled)
        }
    }

    @Published var aiTokenUsageEnabled: Bool {
        didSet {
            UserDefaults.standard.set(aiTokenUsageEnabled, forKey: Keys.aiTokenUsageEnabled)
        }
    }

    @Published var nowPlayingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(nowPlayingEnabled, forKey: Keys.nowPlayingEnabled)
        }
    }

    @Published var logRetentionPreset: LogRetentionPreset {
        didSet {
            UserDefaults.standard.set(logRetentionPreset.rawValue, forKey: Keys.logRetentionPreset)
        }
    }

    @Published var screenHealthEnabled: Bool {
        didSet {
            UserDefaults.standard.set(screenHealthEnabled, forKey: Keys.screenHealthEnabled)
        }
    }

    @Published var screenBreakReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(screenBreakReminderEnabled, forKey: Keys.screenBreakReminderEnabled)
        }
    }

    @Published var screenBreakReminderThresholdPreset: ScreenBreakReminderThresholdPreset {
        didSet {
            UserDefaults.standard.set(
                screenBreakReminderThresholdPreset.rawValue,
                forKey: Keys.screenBreakReminderThresholdPreset
            )
        }
    }

    let chargeLimitMax: Int = 80
    let chargeLimitMin: Int = 75

    let hotKeyDescription = "Option + Command + Space"

    init(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: Keys.hoverToExpand) == nil {
            defaults.set(true, forKey: Keys.hoverToExpand)
        }

        if defaults.object(forKey: Keys.autoHideDelay) == nil {
            defaults.set(1.0, forKey: Keys.autoHideDelay)
        }

        if defaults.object(forKey: Keys.weatherEnabled) == nil {
            defaults.set(true, forKey: Keys.weatherEnabled)
        }

        if defaults.object(forKey: Keys.deviceBatteryEnabled) == nil {
            defaults.set(true, forKey: Keys.deviceBatteryEnabled)
        }

        if defaults.object(forKey: Keys.clipboardHistoryEnabled) == nil {
            defaults.set(true, forKey: Keys.clipboardHistoryEnabled)
        }

        if defaults.object(forKey: Keys.wallpaperRefreshEnabled) == nil {
            defaults.set(true, forKey: Keys.wallpaperRefreshEnabled)
        }

        if defaults.object(forKey: Keys.wallpaperAutoRefreshEnabled) == nil {
            defaults.set(false, forKey: Keys.wallpaperAutoRefreshEnabled)
        }

        if defaults.object(forKey: Keys.wallpaperRefreshIntervalPreset) == nil {
            defaults.set(WallpaperRefreshIntervalPreset.thirtyMinutes.rawValue, forKey: Keys.wallpaperRefreshIntervalPreset)
        }

        if defaults.object(forKey: Keys.quickLaunchLayoutMode) == nil {
            defaults.set(QuickLaunchLayoutMode.grid.rawValue, forKey: Keys.quickLaunchLayoutMode)
        }

        if defaults.object(forKey: Keys.quickLaunchShowsLabels) == nil {
            defaults.set(true, forKey: Keys.quickLaunchShowsLabels)
        }

        if defaults.object(forKey: Keys.panelAppearanceMode) == nil {
            defaults.set(PanelAppearanceMode.system.rawValue, forKey: Keys.panelAppearanceMode)
        }

        if defaults.object(forKey: Keys.panelTextSizePreset) == nil {
            defaults.set(PanelTextSizePreset.regular.rawValue, forKey: Keys.panelTextSizePreset)
        }

        if defaults.object(forKey: Keys.chargeLimitEnabled) == nil {
            defaults.set(false, forKey: Keys.chargeLimitEnabled)
        }

        if defaults.object(forKey: Keys.aiTokenUsageEnabled) == nil {
            defaults.set(false, forKey: Keys.aiTokenUsageEnabled)
        }

        if defaults.object(forKey: Keys.nowPlayingEnabled) == nil {
            defaults.set(false, forKey: Keys.nowPlayingEnabled)
        }

        if defaults.object(forKey: Keys.logRetentionPreset) == nil {
            defaults.set(LogRetentionPreset.thirtyDays.rawValue, forKey: Keys.logRetentionPreset)
        }

        if defaults.object(forKey: Keys.screenHealthEnabled) == nil {
            defaults.set(true, forKey: Keys.screenHealthEnabled)
        }

        if defaults.object(forKey: Keys.screenBreakReminderEnabled) == nil {
            defaults.set(true, forKey: Keys.screenBreakReminderEnabled)
        }

        if defaults.object(forKey: Keys.screenBreakReminderThresholdPreset) == nil {
            defaults.set(
                ScreenBreakReminderThresholdPreset.fortyFiveMinutes.rawValue,
                forKey: Keys.screenBreakReminderThresholdPreset
            )
        }

        hoverToExpand = defaults.bool(forKey: Keys.hoverToExpand)
        autoHideDelay = defaults.double(forKey: Keys.autoHideDelay)
        weatherEnabled = defaults.bool(forKey: Keys.weatherEnabled)
        deviceBatteryEnabled = defaults.bool(forKey: Keys.deviceBatteryEnabled)
        clipboardHistoryEnabled = defaults.bool(forKey: Keys.clipboardHistoryEnabled)
        wallpaperRefreshEnabled = defaults.bool(forKey: Keys.wallpaperRefreshEnabled)
        wallpaperAutoRefreshEnabled = defaults.bool(forKey: Keys.wallpaperAutoRefreshEnabled)
        wallpaperRefreshIntervalPreset = WallpaperRefreshIntervalPreset(
            rawValue: defaults.integer(forKey: Keys.wallpaperRefreshIntervalPreset)
        ) ?? .thirtyMinutes
        quickLaunchLayoutMode = QuickLaunchLayoutMode(
            rawValue: defaults.string(forKey: Keys.quickLaunchLayoutMode) ?? QuickLaunchLayoutMode.grid.rawValue
        ) ?? .grid
        quickLaunchShowsLabels = defaults.bool(forKey: Keys.quickLaunchShowsLabels)
        panelAppearanceMode = PanelAppearanceMode(
            rawValue: defaults.string(forKey: Keys.panelAppearanceMode) ?? PanelAppearanceMode.system.rawValue
        ) ?? .system
        panelTextSizePreset = PanelTextSizePreset(
            rawValue: defaults.string(forKey: Keys.panelTextSizePreset) ?? PanelTextSizePreset.regular.rawValue
        ) ?? .regular
        chargeLimitEnabled = defaults.bool(forKey: Keys.chargeLimitEnabled)
        aiTokenUsageEnabled = defaults.bool(forKey: Keys.aiTokenUsageEnabled)
        nowPlayingEnabled = defaults.bool(forKey: Keys.nowPlayingEnabled)
        logRetentionPreset = LogRetentionPreset(
            rawValue: defaults.integer(forKey: Keys.logRetentionPreset)
        ) ?? .thirtyDays
        screenHealthEnabled = defaults.bool(forKey: Keys.screenHealthEnabled)
        screenBreakReminderEnabled = defaults.bool(forKey: Keys.screenBreakReminderEnabled)
        screenBreakReminderThresholdPreset = ScreenBreakReminderThresholdPreset(
            rawValue: defaults.integer(forKey: Keys.screenBreakReminderThresholdPreset)
        ) ?? .fortyFiveMinutes
    }
}
