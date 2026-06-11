import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchPanelMetrics {
    let textScale: CGFloat

    private var layoutScale: CGFloat {
        max(1.0, min(textScale, 1.16))
    }

    func scaled(_ value: CGFloat, minimum: CGFloat? = nil) -> CGFloat {
        let scaledValue = value * layoutScale
        if let minimum {
            return max(minimum, scaledValue)
        }

        return scaledValue
    }

    var baseCompactSize: NSSize {
        NSSize(width: scaled(200, minimum: 200), height: scaled(38, minimum: 38))
    }

    var headerHeightEstimate: CGFloat {
        scaled(20, minimum: 20)
    }

    var expandedSectionSpacing: CGFloat {
        scaled(12, minimum: 12)
    }

    var expandedVerticalPadding: CGFloat {
        scaled(28, minimum: 28)
    }

    var nowPlayingSectionHeight: CGFloat {
        scaled(110, minimum: 110)
    }

    var moduleSectionHeight: CGFloat {
        moduleUnitSize
    }

    var searchFieldBaseHeight: CGFloat {
        scaled(42, minimum: 42)
    }

    var searchFeedbackRowHeight: CGFloat {
        scaled(46, minimum: 46)
    }

    var searchResultRowHeight: CGFloat {
        scaled(56, minimum: 56)
    }

    var searchResultsViewportHeight: CGFloat {
        max(searchFeedbackRowHeight, searchResultRowHeight)
    }

    var searchSectionHeight: CGFloat {
        searchFieldBaseHeight + 1 + searchResultsViewportHeight
    }

    var horizontalPadding: CGFloat {
        scaled(32, minimum: 32)
    }

    var moduleUnitSize: CGFloat {
        scaled(120, minimum: 120)
    }

    var moduleSpacing: CGFloat {
        scaled(10, minimum: 10)
    }
}

@MainActor
struct NotchPanelStyle {
    let appearanceMode: PanelAppearanceMode
    let resolvedColorScheme: ColorScheme
    let isAttachedToNotch: Bool
    let textScale: CGFloat
    let metrics: NotchPanelMetrics

    init(settings: AppSettings, systemColorScheme: ColorScheme, isAttachedToNotch: Bool) {
        appearanceMode = settings.panelAppearanceMode
        resolvedColorScheme = Self.resolveColorScheme(
            appearanceMode: settings.panelAppearanceMode,
            systemColorScheme: systemColorScheme
        )
        self.isAttachedToNotch = isAttachedToNotch
        textScale = CGFloat(settings.panelTextSizePreset.scale)
        metrics = NotchPanelMetrics(textScale: CGFloat(settings.panelTextSizePreset.scale))
    }

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var visualEffectAppearanceName: NSAppearance.Name? {
        switch appearanceMode {
        case .system:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }

    func font(_ baseSize: CGFloat, weight: Font.Weight = .regular, minimum: CGFloat = 12) -> Font {
        .system(size: max(minimum, baseSize * textScale), weight: weight)
    }

    func scaled(_ value: CGFloat, minimum: CGFloat? = nil) -> CGFloat {
        metrics.scaled(value, minimum: minimum)
    }

    func primaryText(_ opacity: Double = 0.92) -> Color {
        if isDarkMode {
            return Color.white.opacity(opacity)
        }

        return Color.black.opacity(min(opacity + 0.03, 0.96))
    }

    func secondaryText(_ opacity: Double = 0.76) -> Color {
        if isDarkMode {
            return Color.white.opacity(opacity)
        }

        return Color.black.opacity(min(opacity + 0.02, 0.84))
    }

    func surfaceFill(_ darkOpacity: Double, lightOpacity: Double? = nil) -> Color {
        if isDarkMode {
            return Color.white.opacity(darkOpacity)
        }

        return Color.black.opacity(lightOpacity ?? min(darkOpacity, 0.10))
    }

    var moduleBackgroundColor: Color {
        surfaceFill(
            isAttachedToNotch ? 0.13 : 0.10,
            lightOpacity: isAttachedToNotch ? 0.08 : 0.06
        )
    }

    var moduleTileBackgroundColor: Color {
        surfaceFill(
            isAttachedToNotch ? 0.17 : 0.13,
            lightOpacity: isAttachedToNotch ? 0.10 : 0.08
        )
    }

    var moduleBorderColor: Color {
        if isDarkMode {
            return Color.white.opacity(isAttachedToNotch ? 0.16 : 0.12)
        }

        return Color.black.opacity(isAttachedToNotch ? 0.10 : 0.12)
    }

    var panelBorderColor: Color {
        isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    var panelShadowColor: Color {
        if isDarkMode {
            return .black.opacity(isAttachedToNotch ? 0.10 : 0.18)
        }

        return .black.opacity(isAttachedToNotch ? 0.08 : 0.12)
    }

    var panelMaterial: NSVisualEffectView.Material {
        isDarkMode ? .hudWindow : .underWindowBackground
    }

    var panelBackgroundTint: Color {
        if isDarkMode {
            return Color.black.opacity(isAttachedToNotch ? 0.18 : 0.24)
        }

        return Color.white.opacity(isAttachedToNotch ? 0.16 : 0.24)
    }

    var panelBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: isDarkMode
                ? [
                    Color.white.opacity(0.05),
                    Color.white.opacity(0.02),
                    Color.black.opacity(0.12),
                ]
                : [
                    Color.white.opacity(0.24),
                    Color.white.opacity(0.12),
                    Color.black.opacity(0.04),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var attachedBaseColor: Color {
        if isDarkMode {
            return Color(red: 0.26, green: 0.33, blue: 0.22)
        }

        return Color(red: 0.80, green: 0.88, blue: 0.72)
    }

    var attachedOverlayGradient: LinearGradient {
        LinearGradient(
            colors: isDarkMode
                ? [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.03),
                    Color.black.opacity(0.16),
                ]
                : [
                    Color.white.opacity(0.26),
                    Color.white.opacity(0.12),
                    Color.black.opacity(0.04),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var dividerColor: Color {
        isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    var chargingAccent: Color {
        Color(red: 0.58, green: 0.88, blue: 0.56)
    }

    var controlFillColor: Color {
        surfaceFill(0.09, lightOpacity: 0.08)
    }

    var progressTrackColor: Color {
        surfaceFill(0.12, lightOpacity: 0.10)
    }

    var artworkPlaceholderFill: Color {
        surfaceFill(0.07, lightOpacity: 0.06)
    }

    var inactiveIndicatorColor: Color {
        primaryText(0.45)
    }

    var positiveIndicatorColor: Color {
        isDarkMode ? .green : Color.green.opacity(0.85)
    }

    private var isDarkMode: Bool {
        resolvedColorScheme == .dark
    }

    private static func resolveColorScheme(
        appearanceMode: PanelAppearanceMode,
        systemColorScheme: ColorScheme
    ) -> ColorScheme {
        switch appearanceMode {
        case .system:
            return systemColorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct NotchPanelView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject var panelController: NotchPanelController
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var weather: WeatherForecastService
    @ObservedObject var battery: BatteryStatusService
    @ObservedObject var clipboardHistory: ClipboardHistoryService
    @ObservedObject var settings: AppSettings
    @ObservedObject var wallpaper: WallpaperRefreshService
    @ObservedObject var scriptShortcuts: ScriptShortcutStore
    @ObservedObject var localAppSearch: LocalAppSearchService
    @ObservedObject var chargeLimit: ChargeLimitService
    @State private var isClipboardListPresented = false
    @State private var isQuickLaunchEditing = false
    @State private var draggedQuickLaunchShortcutID: UUID?

    private let panelContentAnimation = Animation.spring(response: 0.32, dampingFraction: 0.84, blendDuration: 0.12)

    private var style: NotchPanelStyle {
        NotchPanelStyle(
            settings: settings,
            systemColorScheme: systemColorScheme,
            isAttachedToNotch: panelController.isAttachedToNotch
        )
    }

    private var panelMetrics: NotchPanelMetrics {
        style.metrics
    }

    private var moduleUnitSize: CGFloat {
        panelMetrics.moduleUnitSize
    }

    private var moduleSpacing: CGFloat {
        panelMetrics.moduleSpacing
    }

    private var searchResultsViewportHeight: CGFloat {
        panelMetrics.searchResultsViewportHeight
    }

    private var moduleCardTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
        )
    }

    private var expandedSectionTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)).combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    private var moduleBackgroundColor: Color {
        style.moduleBackgroundColor
    }

    private var moduleTileBackgroundColor: Color {
        style.moduleTileBackgroundColor
    }

    private var moduleBorderColor: Color {
        style.moduleBorderColor
    }

    private var weatherModuleWidth: CGFloat {
        moduleUnitSize
    }

    private var batteryModuleWidth: CGFloat {
        moduleUnitSize
    }

    private var quickLaunchModuleWidth: CGFloat {
        (moduleUnitSize * 2) + moduleSpacing
    }

    private var clipboardModuleWidth: CGFloat {
        moduleUnitSize * 1.5
    }

    private var wallpaperModuleWidth: CGFloat {
        moduleUnitSize
    }

    private var quickLaunchUsesCarouselLayout: Bool {
        settings.quickLaunchLayoutMode == .carousel
    }

    private var quickLaunchShowsLabels: Bool {
        settings.quickLaunchShowsLabels
    }

    private func panelFont(_ baseSize: CGFloat, weight: Font.Weight = .regular, minimum: CGFloat = 12) -> Font {
        style.font(baseSize, weight: weight, minimum: minimum)
    }

    private func panelScaled(_ value: CGFloat, minimum: CGFloat? = nil) -> CGFloat {
        style.scaled(value, minimum: minimum)
    }

    private func panelMax(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        max(lhs, rhs)
    }

    private var visibleModuleWidths: [CGFloat] {
        [
            shouldShowWeatherSection ? weatherModuleWidth : nil,
            shouldShowBatterySection ? batteryModuleWidth : nil,
            shouldShowWallpaperSection ? wallpaperModuleWidth : nil,
            shouldShowClipboardSection ? clipboardModuleWidth : nil,
            shouldShowQuickLaunchSection ? quickLaunchModuleWidth : nil,
        ].compactMap { $0 }
    }

    private var contentRowWidth: CGFloat {
        guard !visibleModuleWidths.isEmpty else {
            return quickLaunchModuleWidth
        }

        let moduleWidth = visibleModuleWidths.reduce(0, +) + (CGFloat(visibleModuleWidths.count - 1) * moduleSpacing)
        return max(moduleWidth, quickLaunchModuleWidth)
    }

    private var moduleAnimationKey: String {
        [
            shouldShowWeatherSection ? "weather" : nil,
            shouldShowBatterySection ? "battery" : nil,
            shouldShowWallpaperSection ? "wallpaper" : nil,
            shouldShowClipboardSection ? "clipboard" : nil,
            shouldShowQuickLaunchSection ? "quickLaunch" : nil,
            quickLaunchUsesCarouselLayout ? "carousel" : "grid",
            quickLaunchShowsLabels ? "labels" : "icons",
            settings.panelAppearanceMode.rawValue,
            settings.panelTextSizePreset.rawValue,
            isQuickLaunchEditing ? "editing" : "normal",
            "\(clipboardHistory.entries.count)",
            wallpaper.lastWallpaperName ?? "none",
            wallpaper.statusMessage,
            "\(scriptShortcuts.shortcuts.count)",
        ]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    private var surfaceSize: CGSize {
        panelController.isExpanded ? panelController.expandedPanelSize : panelController.compactPanelSize
    }

    var body: some View {
        ZStack(alignment: .top) {
            panelSurface
                .frame(width: surfaceSize.width, height: surfaceSize.height)
                .animation(panelContentAnimation, value: surfaceSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .preferredColorScheme(style.preferredColorScheme)
        .onHover { isHovering in
            panelController.hoverChanged(isHovering: isHovering)
        }
    }

    private var panelSurface: some View {
        ZStack {
            surfaceBackground

            if panelController.isExpanded {
                expandedView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                compactView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compositingGroup()
        .clipShape(panelShape)
        .overlay {
            panelShape
                .strokeBorder(style.panelBorderColor, lineWidth: 1)
        }
        .contentShape(panelShape)
        .shadow(
            color: style.panelShadowColor,
            radius: panelController.isAttachedToNotch ? 12 : 20,
            y: panelController.isAttachedToNotch ? 4 : 8
        )
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        if panelController.isAttachedToNotch {
            panelShape
                .fill(style.attachedBaseColor)
                .overlay {
                    panelShape.fill(style.attachedOverlayGradient)
                }
                .overlay {
                    panelShape.fill(style.panelBackgroundTint)
                }
        } else {
            VisualEffectView(
                material: style.panelMaterial,
                blendingMode: .withinWindow,
                appearanceName: style.visualEffectAppearanceName
            )
                .overlay {
                    panelShape.fill(style.panelBackgroundTint)
                }
                .overlay {
                    panelShape.fill(style.panelBackgroundGradient)
                }
                .clipShape(panelShape)
        }
    }

    private var panelShape: NotchSurfaceShape {
        let bottomRadius = panelController.isExpanded
            ? 26.0
            : min(panelController.compactPanelSize.height / 2, 14.0)
        let topRadius = panelController.isAttachedToNotch
            ? (panelController.isExpanded ? 12.0 : 6.0)
            : bottomRadius

        return NotchSurfaceShape(
            topCornerRadius: topRadius,
            bottomCornerRadius: bottomRadius
        )
    }

    private var compactView: some View {
        HStack(spacing: 10) {
            Image(systemName: compactSymbolName)
                .font(panelFont(14, weight: .semibold))
                .foregroundStyle(panelPrimaryTextColor)
                .frame(width: 20)

            Text(compactTitle)
                .font(panelFont(13, weight: .semibold))
                .foregroundStyle(panelPrimaryTextColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            compactAccessory
        }
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            panelController.expandAndPin()
        }
    }

    private var expandedView: some View {
        VStack(spacing: 12) {
            expandedHeader

            if nowPlaying.snapshot.hasContent {
                nowPlayingSection
                    .transition(expandedSectionTransition)
            }

            if shouldShowModuleRow {
                moduleRow
                    .transition(expandedSectionTransition)
            }

            appSearchSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .animation(panelContentAnimation, value: nowPlaying.snapshot.hasContent)
        .animation(panelContentAnimation, value: moduleAnimationKey)
    }

    private var expandedHeader: some View {
        HStack(spacing: 10) {
            Text("NotchFlow")
                .font(panelFont(13, weight: .semibold))
                .foregroundStyle(panelPrimaryTextColor)

            Spacer()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelSecondaryTextColor)

            Button {
                panelController.togglePin()
            } label: {
                Image(systemName: panelController.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelSecondaryTextColor)

            Button {
                panelController.collapseToCompact()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelSecondaryTextColor)
        }
    }

    private var nowPlayingSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                artworkView

                VStack(alignment: .leading, spacing: 4) {
                    Text(nowPlaying.snapshot.title)
                        .font(panelFont(16, weight: .semibold))
                        .foregroundStyle(panelPrimaryTextColor)
                        .lineLimit(2)

                    Text(nowPlaying.snapshot.artist.isEmpty ? "Ready when your media is." : nowPlaying.snapshot.artist)
                        .font(panelFont(13, weight: .medium))
                        .foregroundStyle(panelSecondaryTextColor)
                        .lineLimit(1)

                    if !nowPlaying.snapshot.album.isEmpty {
                        Text(nowPlaying.snapshot.album)
                            .font(panelFont(12, weight: .regular))
                            .foregroundStyle(panelTertiaryTextColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                mediaButton(systemName: "backward.fill") {
                    nowPlaying.previousTrack()
                }

                mediaButton(systemName: nowPlaying.snapshot.isPlaying ? "pause.fill" : "play.fill") {
                    nowPlaying.togglePlayPause()
                }

                mediaButton(systemName: "forward.fill") {
                    nowPlaying.nextTrack()
                }

                Spacer()

                Button {
                    nowPlaying.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(panelFont(12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(panelSecondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var moduleRow: some View {
        HStack(alignment: .top, spacing: moduleSpacing) {
            if shouldShowWeatherSection {
                weatherSection
                    .transition(moduleCardTransition)
            }

            if shouldShowBatterySection {
                batterySection
                    .transition(moduleCardTransition)
            }

            if shouldShowWallpaperSection {
                wallpaperSection
                    .transition(moduleCardTransition)
            }

            if shouldShowClipboardSection {
                clipboardHistorySection
                    .transition(moduleCardTransition)
            }

            if shouldShowQuickLaunchSection {
                quickLaunchSection
                    .transition(moduleCardTransition)
            }
        }
        .frame(width: contentRowWidth, alignment: .center)
        .frame(minHeight: moduleUnitSize, maxHeight: moduleUnitSize, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var moduleHeaderForegroundColor: Color {
        style.primaryText(0.78)
    }

    private var panelPrimaryTextColor: Color {
        style.primaryText(0.94)
    }

    private var panelSecondaryTextColor: Color {
        style.secondaryText(0.72)
    }

    private var panelTertiaryTextColor: Color {
        style.secondaryText(0.62)
    }

    private var modulePrimaryTextColor: Color {
        panelPrimaryTextColor
    }

    private var moduleSecondaryTextColor: Color {
        panelSecondaryTextColor
    }

    private var moduleTertiaryTextColor: Color {
        panelTertiaryTextColor
    }

    private var moduleCardInsets: EdgeInsets {
        EdgeInsets(
            top: panelScaled(10, minimum: 10),
            leading: panelScaled(10, minimum: 10),
            bottom: panelScaled(10, minimum: 10),
            trailing: panelScaled(10, minimum: 10)
        )
    }

    private var moduleHeaderHeight: CGFloat {
        panelScaled(18, minimum: 18)
    }

    private func moduleCard<Content: View>(
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(moduleCardInsets)
        .frame(width: width, height: moduleUnitSize, alignment: .topLeading)
        .background(moduleBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(moduleBorderColor, lineWidth: 1)
        }
    }

    private func moduleHeader<Trailing: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(panelFont(12, weight: .semibold))
                .foregroundStyle(moduleHeaderForegroundColor)
                .frame(width: 14, alignment: .leading)

            Text(title)
                .font(panelFont(12, weight: .semibold))
                .foregroundStyle(moduleHeaderForegroundColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            trailing()
        }
        .frame(height: moduleHeaderHeight, alignment: .center)
    }

    private var weatherSection: some View {
        moduleCard(width: weatherModuleWidth) {
            if weather.snapshot.hasContent {
                moduleHeader("天气", systemImage: "cloud.sun") {
                    Image(systemName: weather.snapshot.symbolName)
                        .font(panelFont(15, weight: .semibold))
                        .foregroundStyle(modulePrimaryTextColor)
                }

                Spacer(minLength: 4)

                Text(formattedTemperature(weather.snapshot.temperature))
                    .font(panelFont(26, weight: .bold))
                    .foregroundStyle(modulePrimaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(weather.snapshot.conditionName)
                    .font(panelFont(12, weight: .semibold))
                    .foregroundStyle(moduleSecondaryTextColor)
                    .lineLimit(1)
                    .padding(.top, 2)

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text("体感 \(formattedTemperature(weather.snapshot.apparentTemperature))")
                    Text("\(formattedTemperature(weather.snapshot.lowTemperature)) - \(formattedTemperature(weather.snapshot.highTemperature))")
                }
                .font(panelFont(12, weight: .medium))
                .foregroundStyle(moduleSecondaryTextColor)
            } else {
                moduleHeader("天气", systemImage: "cloud.sun") {
                    Image(systemName: "cloud.sun.fill")
                        .font(panelFont(14, weight: .semibold))
                        .foregroundStyle(modulePrimaryTextColor)
                }

                Spacer(minLength: 4)

                Text(weatherPlaceholderTitle)
                    .font(panelFont(12, weight: .semibold))
                    .foregroundStyle(modulePrimaryTextColor)
                    .lineLimit(1)

                Text(weather.statusMessage)
                    .font(panelFont(12, weight: .medium))
                    .foregroundStyle(moduleSecondaryTextColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

                Spacer(minLength: 4)

                HStack {
                    if weather.authorizationStatus == .notDetermined {
                        Button {
                            weather.requestLocationAuthorization()
                        } label: {
                            Label("允许定位", systemImage: "location")
                                .font(panelFont(12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(moduleSecondaryTextColor)
                    }

                    Spacer(minLength: 0)

                    Button {
                        weather.refresh(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(panelFont(11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(moduleSecondaryTextColor)
                }
            }
        }
    }

    private var batterySection: some View {
        moduleCard(width: batteryModuleWidth) {
            moduleHeader("设备电量", systemImage: "battery.100") {
                if settings.chargeLimitEnabled && chargeLimit.state == .chargingDisabled {
                    Image(systemName: "bolt.slash.fill")
                        .font(panelFont(11, weight: .semibold))
                        .foregroundStyle(.orange)
                } else if settings.chargeLimitEnabled && chargeLimit.state == .monitoring {
                    Image(systemName: "bolt.shield.fill")
                        .font(panelFont(11, weight: .semibold))
                        .foregroundStyle(style.chargingAccent)
                } else if battery.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(moduleSecondaryTextColor)
                        .scaleEffect(0.65)
                } else if let primaryBattery = primaryBatterySnapshot, primaryBattery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(panelFont(11, weight: .semibold))
                        .foregroundStyle(style.chargingAccent)
                } else if battery.snapshot.accessoryCount > 0 {
                    Text("\(battery.snapshot.accessoryCount)")
                        .font(panelFont(12, weight: .semibold))
                        .foregroundStyle(moduleSecondaryTextColor)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 6)

            batteryHero

            Spacer(minLength: 6)

            if settings.chargeLimitEnabled || chargeLimit.state == .chargingDisabled {
                Button {
                    chargeLimit.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: chargeLimit.state == .chargingDisabled ? "bolt.slash.fill" : "bolt.shield.fill")
                            .font(panelFont(10, weight: .semibold))
                            .foregroundStyle(chargeLimit.state == .chargingDisabled ? .orange : style.chargingAccent)

                        Text(chargeLimit.state == .chargingDisabled ? "充电已暂停" : "充电保护中")
                            .font(panelFont(11, weight: .medium))
                            .foregroundStyle(moduleSecondaryTextColor)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(moduleTileBackgroundColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)
            }

            batteryFooter
        }
    }

    private var clipboardHistorySection: some View {
        moduleCard(width: clipboardModuleWidth) {
            moduleHeader("剪贴板", systemImage: "doc.on.clipboard") {
                if !clipboardHistory.entries.isEmpty {
                    Button {
                        isClipboardListPresented.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet")
                                .font(panelFont(9, weight: .semibold))

                            Text("\(clipboardHistory.entries.count)")
                                .font(panelFont(12, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(moduleSecondaryTextColor)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(style.controlFillColor, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("查看剪贴板历史")
                    .popover(isPresented: $isClipboardListPresented, arrowEdge: .top) {
                        clipboardHistoryPopover
                    }
                }
            }

            Spacer(minLength: 6)

            if clipboardHistory.entries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)

                    Image(systemName: "doc.text")
                        .font(panelFont(18, weight: .medium))
                        .foregroundStyle(moduleTertiaryTextColor)

                    Text("复制文本后会出现在这里")
                        .font(panelFont(12, weight: .semibold))
                        .foregroundStyle(modulePrimaryTextColor)
                        .lineLimit(2)

                    Text("最近 3 条会显示在面板里")
                        .font(panelFont(12, weight: .medium))
                        .foregroundStyle(moduleSecondaryTextColor)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(visibleClipboardEntries.enumerated()), id: \.element.id) { index, entry in
                        clipboardHistoryEntryButton(entry, isPrimary: index == 0)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var wallpaperSection: some View {
        moduleCard(width: wallpaperModuleWidth) {
            moduleHeader("壁纸", systemImage: "photo.on.rectangle.angled") {
                if wallpaper.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(moduleSecondaryTextColor)
                        .scaleEffect(0.65)
                } else if settings.wallpaperAutoRefreshEnabled {
                    Image(systemName: "timer")
                        .font(panelFont(11, weight: .semibold))
                        .foregroundStyle(moduleSecondaryTextColor)
                } else {
                    Button {
                        wallpaper.refreshOrChooseFolder()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(panelFont(11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(moduleSecondaryTextColor)
                    .help(wallpaper.selectedDirectoryURL == nil ? "选择壁纸文件夹" : "刷新壁纸")
                }
            }

            Spacer(minLength: 6)

            Text(wallpaperHeroTitle)
                .font(panelFont(16, weight: .semibold))
                .foregroundStyle(modulePrimaryTextColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(wallpaperSubtitle)
                .font(panelFont(12, weight: .medium))
                .foregroundStyle(moduleSecondaryTextColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            Spacer(minLength: 6)

            Button {
                wallpaper.refreshOrChooseFolder()
            } label: {
                Label(wallpaper.selectedDirectoryURL == nil ? "选择" : "刷新", systemImage: "photo")
                    .font(panelFont(12, weight: .medium))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(moduleSecondaryTextColor)
            .disabled(wallpaper.isRefreshing)
        }
    }

    private var clipboardHistoryPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label("剪贴板历史", systemImage: "doc.on.clipboard")
                    .font(panelFont(13, weight: .semibold))
                    .foregroundStyle(modulePrimaryTextColor)

                Spacer(minLength: 12)

                Text("\(clipboardHistory.entries.count)")
                    .font(panelFont(12, weight: .semibold))
                    .foregroundStyle(moduleSecondaryTextColor)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(style.controlFillColor, in: Capsule(style: .continuous))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 9)

            Divider()

            if clipboardHistory.entries.isEmpty {
                Text("暂无历史")
                    .font(panelFont(13, weight: .medium))
                    .foregroundStyle(moduleSecondaryTextColor)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(clipboardHistory.entries) { entry in
                            clipboardHistoryPopoverRow(entry)

                            if entry.id != clipboardHistory.entries.last?.id {
                                Divider()
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(width: 320)
        .preferredColorScheme(style.preferredColorScheme)
    }

    private func clipboardHistoryPopoverRow(_ entry: ClipboardHistoryEntry) -> some View {
        Button {
            clipboardHistory.copy(entry)
            isClipboardListPresented = false
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.previewText)
                    .font(panelFont(13, weight: .semibold))
                    .foregroundStyle(modulePrimaryTextColor)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Text(entry.detailText)
                    .font(panelFont(11, weight: .medium))
                    .foregroundStyle(moduleSecondaryTextColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.text)
    }

    private var quickLaunchSection: some View {
        moduleCard(width: quickLaunchModuleWidth) {
            VStack(alignment: .leading, spacing: quickLaunchHeaderSpacing) {
                moduleHeader("快捷启动", systemImage: "bolt.fill") {
                    quickLaunchEditControl
                }

                if quickLaunchUsesCarouselLayout {
                    quickLaunchCarousel
                } else {
                    quickLaunchGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var quickLaunchEditControl: some View {
        if !scriptShortcuts.shortcuts.isEmpty {
            Button {
                toggleQuickLaunchEditing()
            } label: {
                Text(isQuickLaunchEditing ? "完成" : "编辑")
                    .font(panelFont(11, weight: .semibold))
                    .foregroundStyle(moduleSecondaryTextColor)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(style.controlFillColor, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(isQuickLaunchEditing ? "完成编辑" : "编辑快捷启动")
        }
    }

    private var quickLaunchGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: quickLaunchRows, alignment: .center, spacing: quickLaunchItemSpacing) {
                ForEach(scriptShortcuts.shortcuts) { shortcut in
                    launchShortcutGridButton(shortcut)
                }
            }
            .padding(.vertical, quickLaunchVerticalPadding)
            .padding(.leading, 1)
            .padding(.trailing, 2)
        }
        .frame(height: quickLaunchViewportHeight)
    }

    private var quickLaunchCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: quickLaunchItemSpacing) {
                ForEach(scriptShortcuts.shortcuts) { shortcut in
                    launchShortcutCarouselButton(shortcut)
                }
            }
            .padding(.vertical, quickLaunchVerticalPadding)
            .padding(.leading, 1)
            .padding(.trailing, 2)
        }
        .frame(height: quickLaunchViewportHeight)
    }

    private var appSearchSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(panelFont(13, weight: .semibold))
                    .foregroundStyle(moduleHeaderForegroundColor)

                TextField("搜索本机 App", text: $localAppSearch.query)
                    .textFieldStyle(.plain)
                    .font(panelFont(13, weight: .medium))
                    .foregroundStyle(panelPrimaryTextColor)
                    .onSubmit {
                        localAppSearch.activateTopResult()
                    }

                if isSearchingApps {
                    Button {
                        localAppSearch.clearQuery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(panelFont(13, weight: .semibold))
                            .foregroundStyle(panelSecondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: panelMetrics.searchFieldBaseHeight)

            Rectangle()
                .fill(style.dividerColor)
                .frame(height: 1)

            appSearchResults
        }
        .frame(width: contentRowWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(moduleBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(moduleBorderColor, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var appSearchResults: some View {
        if !isSearchingApps {
            HStack {
                Text("输入名称即可匹配本机 App")
                    .font(panelFont(12, weight: .medium))
                    .foregroundStyle(panelSecondaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: searchResultsViewportHeight)
        } else if localAppSearch.isIndexing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(panelPrimaryTextColor)

                Text("正在整理已安装应用…")
                    .font(panelFont(12, weight: .medium))
                    .foregroundStyle(panelSecondaryTextColor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: searchResultsViewportHeight)
        } else if localAppSearch.visibleResults.isEmpty {
            HStack {
                Text("没有找到匹配的 App")
                    .font(panelFont(12, weight: .medium))
                    .foregroundStyle(panelSecondaryTextColor)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: searchResultsViewportHeight)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(localAppSearch.visibleResults.enumerated()), id: \.element.id) { index, app in
                        appSearchResultChip(app, isPrimary: index == 0)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(height: searchResultsViewportHeight)
        }
    }

    private func appSearchResultChip(_ app: LocalInstalledApp, isPrimary: Bool) -> some View {
        Button {
            localAppSearch.open(app)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: app.iconImage)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(panelFont(12, weight: .medium))
                        .foregroundStyle(panelPrimaryTextColor)
                        .lineLimit(1)

                    if isPrimary {
                        Text("回车打开")
                            .font(panelFont(12, weight: .medium))
                            .foregroundStyle(panelSecondaryTextColor)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: moduleUnitSize, height: 40, alignment: .leading)
            .background(moduleTileBackgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var batteryHero: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(batteryCenterValueText)
                .font(panelFont(28, weight: .bold))
                .foregroundStyle(modulePrimaryTextColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 4) {
                Image(systemName: batteryCenterSymbolName)
                    .font(panelFont(9, weight: .semibold))
                    .foregroundStyle(moduleSecondaryTextColor)

                Text(batteryPrimaryCaption)
                    .font(panelFont(12, weight: .semibold))
                    .foregroundStyle(moduleSecondaryTextColor)
                    .lineLimit(1)
            }

            batteryLevelBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var batteryFooter: some View {
        if battery.snapshot.accessories.isEmpty {
            batteryEmptyAccessoriesView
        } else {
            batteryAccessoriesStrip
        }
    }

    private var batteryAccessoriesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(battery.snapshot.accessories) { accessory in
                    batteryAccessoryPill(accessory)
                }
            }
            .padding(.trailing, 2)
        }
        .frame(height: 22)
    }

    private var batteryEmptyAccessoriesView: some View {
        HStack(spacing: 5) {
            Image(systemName: "wave.3.right")
                .font(panelFont(9, weight: .semibold))

            Text(batteryAccessoryStatusText)
                .font(panelFont(12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(moduleSecondaryTextColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 20)
    }

    private func batteryAccessoryPill(_ accessory: DeviceBatterySnapshot) -> some View {
        HStack(spacing: 4) {
            Image(systemName: accessory.kind.symbolName)
                .font(panelFont(9, weight: .semibold))
                .foregroundStyle(moduleSecondaryTextColor)

            Text(accessory.percentageText)
                .font(panelFont(12, weight: .semibold))
                .foregroundStyle(modulePrimaryTextColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(moduleTileBackgroundColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var batteryLevelBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(style.progressTrackColor)

                Capsule(style: .continuous)
                    .fill(batteryRingColor)
                    .frame(
                        width: max(
                            batteryLevelProgress > 0 ? 10 : 0,
                            geometry.size.width * batteryLevelProgress
                        )
                    )
            }
        }
        .frame(height: 6)
    }

    private var artworkView: some View {
        Group {
            if let image = nowPlaying.snapshot.artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(style.artworkPlaceholderFill)

                    Image(systemName: "music.note")
                        .font(panelFont(24, weight: .medium))
                        .foregroundStyle(panelSecondaryTextColor)
                }
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func clipboardHistoryEntryButton(_ entry: ClipboardHistoryEntry, isPrimary: Bool) -> some View {
        Button {
            clipboardHistory.copy(entry)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPrimary ? "doc.on.clipboard.fill" : "doc.text")
                    .font(panelFont(9, weight: .semibold))
                    .foregroundStyle(isPrimary ? modulePrimaryTextColor : moduleSecondaryTextColor)
                    .frame(width: 10)

                Text(entry.previewText)
                    .font(panelFont(12, weight: isPrimary ? .semibold : .medium))
                    .foregroundStyle(modulePrimaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 22, alignment: .leading)
            .background(
                isPrimary ? style.surfaceFill(0.16, lightOpacity: 0.12) : moduleTileBackgroundColor,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(entry.text)
    }

    private func mediaButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(panelFont(14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(style.controlFillColor, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(panelPrimaryTextColor)
    }

    private func launchShortcutGridButton(_ shortcut: ScriptShortcut) -> some View {
        quickLaunchEditableTile(
            shortcut,
            width: quickLaunchGridCellWidth,
            height: quickLaunchGridCellHeight,
            iconSize: quickLaunchGridIconSize,
            isCarouselLayout: false
        )
    }

    private func launchShortcutCarouselButton(_ shortcut: ScriptShortcut) -> some View {
        quickLaunchEditableTile(
            shortcut,
            width: quickLaunchCarouselCellWidth,
            height: quickLaunchCarouselCellHeight,
            iconSize: quickLaunchCarouselIconSize,
            isCarouselLayout: true
        )
    }

    private func quickLaunchEditableTile(
        _ shortcut: ScriptShortcut,
        width: CGFloat,
        height: CGFloat,
        iconSize: CGFloat,
        isCarouselLayout: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            quickLaunchTileContent(
                shortcut,
                width: width,
                height: height,
                iconSize: iconSize,
                isCarouselLayout: isCarouselLayout
            )
            .background(moduleTileBackgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .rotationEffect(.degrees(quickLaunchJiggleAngle(for: shortcut)))
            .scaleEffect(draggedQuickLaunchShortcutID == shortcut.id ? 1.05 : 1.0)
            .animation(quickLaunchJiggleAnimation(for: shortcut), value: isQuickLaunchEditing)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: draggedQuickLaunchShortcutID)

            if isQuickLaunchEditing {
                quickLaunchDeleteButton(shortcut)
                    .padding(.leading, 3)
                    .padding(.top, 3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard !isQuickLaunchEditing else {
                return
            }

            scriptShortcuts.run(shortcut)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    enterQuickLaunchEditing()
                }
        )
        .onDrag {
            enterQuickLaunchEditing()
            draggedQuickLaunchShortcutID = shortcut.id
            return NSItemProvider(object: shortcut.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: QuickLaunchShortcutReorderDropDelegate(
                targetID: shortcut.id,
                draggedShortcutID: $draggedQuickLaunchShortcutID,
                isEditing: $isQuickLaunchEditing,
                store: scriptShortcuts
            )
        )
    }

    @ViewBuilder
    private func quickLaunchTileContent(
        _ shortcut: ScriptShortcut,
        width: CGFloat,
        height: CGFloat,
        iconSize: CGFloat,
        isCarouselLayout: Bool
    ) -> some View {
        if isCarouselLayout {
            VStack(spacing: quickLaunchShowsLabels ? 7 : 0) {
                shortcutCarouselIcon(shortcut, size: iconSize)

                if quickLaunchShowsLabels {
                    Text(shortcut.displayName)
                        .font(panelFont(12, weight: .medium))
                        .foregroundStyle(panelPrimaryTextColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, quickLaunchShowsLabels ? 4 : 0)
            .frame(width: width, height: height, alignment: .center)
        } else if quickLaunchShowsLabels {
            HStack(spacing: 8) {
                shortcutGridIcon(shortcut, size: iconSize)

                Text(shortcut.displayName)
                    .font(panelFont(12, weight: .medium))
                    .foregroundStyle(panelPrimaryTextColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: height, alignment: .leading)
        } else {
            shortcutGridIcon(shortcut, size: iconSize)
                .frame(width: width, height: height, alignment: .center)
        }
    }

    private func quickLaunchDeleteButton(_ shortcut: ScriptShortcut) -> some View {
        Button(role: .destructive) {
            withAnimation(panelContentAnimation) {
                scriptShortcuts.remove(shortcut)

                if scriptShortcuts.shortcuts.isEmpty {
                    isQuickLaunchEditing = false
                }
            }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(panelFont(15, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.red)
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .help("移除快捷项")
    }

    @ViewBuilder
    private func shortcutGridIcon(_ shortcut: ScriptShortcut, size: CGFloat = 18) -> some View {
        if let image = shortcut.iconImage {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: shortcut.kind.symbolName)
                .font(panelFont(panelMax(size - 6, 12), weight: .semibold))
                .foregroundStyle(panelPrimaryTextColor)
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func shortcutCarouselIcon(_ shortcut: ScriptShortcut, size: CGFloat) -> some View {
        if let image = shortcut.iconImage {
            Image(nsImage: image)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: shortcut.kind.symbolName)
                .font(panelFont(panelMax(size - 10, 12), weight: .semibold))
                .foregroundStyle(panelPrimaryTextColor)
                .frame(width: size, height: size)
        }
    }

    private var quickLaunchHeaderSpacing: CGFloat {
        panelScaled(6, minimum: 6)
    }

    private var quickLaunchItemSpacing: CGFloat {
        panelScaled(6, minimum: 6)
    }

    private var quickLaunchVerticalPadding: CGFloat {
        let basePadding = quickLaunchUsesCarouselLayout ? panelScaled(4, minimum: 4) : panelScaled(2, minimum: 2)
        return isQuickLaunchEditing ? basePadding + 2 : basePadding
    }

    private var canReorderQuickLaunchShortcuts: Bool {
        scriptShortcuts.shortcuts.count > 1
    }

    private func toggleQuickLaunchEditing() {
        withAnimation(panelContentAnimation) {
            isQuickLaunchEditing.toggle()
            draggedQuickLaunchShortcutID = nil
        }
    }

    private func enterQuickLaunchEditing() {
        guard !isQuickLaunchEditing else {
            return
        }

        withAnimation(panelContentAnimation) {
            isQuickLaunchEditing = true
        }
    }

    private func quickLaunchJiggleAngle(for shortcut: ScriptShortcut) -> Double {
        guard isQuickLaunchEditing else {
            return 0
        }

        return quickLaunchJiggleSeed(for: shortcut).isMultiple(of: 2) ? -1.6 : 1.6
    }

    private func quickLaunchJiggleAnimation(for shortcut: ScriptShortcut) -> Animation? {
        guard isQuickLaunchEditing else {
            return .easeOut(duration: 0.12)
        }

        return .easeInOut(duration: quickLaunchJiggleDuration(for: shortcut))
            .repeatForever(autoreverses: true)
    }

    private func quickLaunchJiggleDuration(for shortcut: ScriptShortcut) -> Double {
        let offset = Double(quickLaunchJiggleSeed(for: shortcut) % 3) * 0.025
        return 0.14 + offset
    }

    private func quickLaunchJiggleSeed(for shortcut: ScriptShortcut) -> Int {
        shortcut.id.uuidString.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
    }

    private var quickLaunchViewportHeight: CGFloat {
        moduleUnitSize - moduleCardInsets.top - moduleCardInsets.bottom - moduleHeaderHeight - quickLaunchHeaderSpacing
    }

    private var quickLaunchRowCount: Int {
        quickLaunchUsesCarouselLayout ? 1 : 2
    }

    private var quickLaunchRowHeight: CGFloat {
        let totalSpacing = CGFloat(max(quickLaunchRowCount - 1, 0)) * quickLaunchItemSpacing
        return max(
            panelScaled(30, minimum: 30),
            (quickLaunchViewportHeight - (quickLaunchVerticalPadding * 2) - totalSpacing) / CGFloat(quickLaunchRowCount)
        )
    }

    private var quickLaunchRows: [GridItem] {
        Array(
            repeating: GridItem(.fixed(quickLaunchRowHeight), spacing: quickLaunchItemSpacing, alignment: .center),
            count: quickLaunchRowCount
        )
    }

    private var quickLaunchGridCellWidth: CGFloat {
        quickLaunchShowsLabels ? panelScaled(108, minimum: 96) : quickLaunchRowHeight
    }

    private var quickLaunchGridCellHeight: CGFloat {
        quickLaunchRowHeight
    }

    private var quickLaunchGridIconSize: CGFloat {
        if quickLaunchShowsLabels {
            return min(panelScaled(20, minimum: 18), quickLaunchRowHeight - 12)
        }

        return min(panelScaled(24, minimum: 22), quickLaunchRowHeight - 8)
    }

    private var quickLaunchCarouselCellWidth: CGFloat {
        quickLaunchShowsLabels ? panelScaled(74, minimum: 68) : quickLaunchRowHeight
    }

    private var quickLaunchCarouselCellHeight: CGFloat {
        quickLaunchRowHeight
    }

    private var quickLaunchCarouselIconSize: CGFloat {
        if quickLaunchShowsLabels {
            return min(panelScaled(30, minimum: 28), quickLaunchCarouselCellHeight - 28)
        }

        return min(panelScaled(38, minimum: 34), quickLaunchCarouselCellHeight - 8)
    }

    private var visibleClipboardEntries: [ClipboardHistoryEntry] {
        Array(clipboardHistory.entries.prefix(3))
    }

    @ViewBuilder
    private var compactAccessory: some View {
        if nowPlaying.snapshot.hasContent {
            Circle()
                .fill(nowPlaying.snapshot.isPlaying ? style.positiveIndicatorColor : style.inactiveIndicatorColor)
                .frame(width: 7, height: 7)
        } else if settings.weatherEnabled, weather.isLoading {
            ProgressView()
                .controlSize(.mini)
                .tint(panelSecondaryTextColor)
                .scaleEffect(0.6)
        } else if settings.weatherEnabled, weather.snapshot.hasContent {
            Image(systemName: "location.fill")
                .font(panelFont(9, weight: .semibold))
                .foregroundStyle(panelSecondaryTextColor)
        } else if settings.deviceBatteryEnabled, battery.isLoading {
            ProgressView()
                .controlSize(.mini)
                .tint(panelSecondaryTextColor)
                .scaleEffect(0.6)
        } else if settings.deviceBatteryEnabled, let primaryBattery = primaryBatterySnapshot, primaryBattery.isCharging {
            Image(systemName: "bolt.fill")
                .font(panelFont(10, weight: .semibold))
                .foregroundStyle(batteryRingColor.opacity(0.9))
        } else if settings.clipboardHistoryEnabled, !clipboardHistory.entries.isEmpty {
            Text("\(clipboardHistory.entries.count)")
                .font(panelFont(12, weight: .semibold))
                .foregroundStyle(panelSecondaryTextColor)
                .monospacedDigit()
        } else if settings.wallpaperRefreshEnabled, wallpaper.isRefreshing {
            ProgressView()
                .controlSize(.mini)
                .tint(panelSecondaryTextColor)
                .scaleEffect(0.6)
        } else if settings.wallpaperRefreshEnabled, wallpaper.lastWallpaperName != nil {
            Image(systemName: "photo.fill")
                .font(panelFont(10, weight: .semibold))
                .foregroundStyle(panelSecondaryTextColor)
        }
    }

    private var compactSymbolName: String {
        if nowPlaying.snapshot.hasContent {
            return "waveform"
        }

        if settings.weatherEnabled {
            return weather.snapshot.symbolName
        }

        if settings.deviceBatteryEnabled, primaryBatterySnapshot != nil {
            return batteryCenterSymbolName
        }

        if settings.clipboardHistoryEnabled, !clipboardHistory.entries.isEmpty {
            return "doc.on.clipboard"
        }

        if settings.wallpaperRefreshEnabled {
            return "photo.on.rectangle.angled"
        }

        if shouldShowQuickLaunchSection {
            return "bolt.fill"
        }

        return "magnifyingglass"
    }

    private var compactTitle: String {
        if nowPlaying.snapshot.hasContent {
            return nowPlaying.snapshot.title
        }

        if settings.weatherEnabled {
            if weather.snapshot.hasContent {
                return "\(formattedTemperature(weather.snapshot.temperature)) · \(weather.snapshot.conditionName)"
            }

            return weather.statusMessage
        }

        if settings.deviceBatteryEnabled, let primaryBattery = primaryBatterySnapshot {
            if battery.snapshot.accessoryCount > 0 {
                return "\(primaryBattery.percentageText) · \(battery.snapshot.accessoryCount) 个外设"
            }

            return primaryBattery.isCharging
                ? "正在充电 · \(primaryBattery.percentageText)"
                : "电量 \(primaryBattery.percentageText)"
        }

        if scriptShortcuts.shortcuts.count == 1,
           let shortcut = scriptShortcuts.shortcuts.first {
            return shortcut.displayName
        }

        if settings.clipboardHistoryEnabled,
           let latestEntry = clipboardHistory.entries.first {
            return latestEntry.previewText
        }

        if settings.wallpaperRefreshEnabled {
            if let lastWallpaperName = wallpaper.lastWallpaperName {
                return "壁纸 · \(lastWallpaperName)"
            }

            return wallpaper.statusMessage
        }

        if shouldShowQuickLaunchSection {
            return "快捷启动 \(scriptShortcuts.shortcuts.count)"
        }

        if settings.clipboardHistoryEnabled {
            return "剪贴板历史"
        }

        return "搜索 App"
    }

    private var shouldShowWeatherSection: Bool {
        settings.weatherEnabled
    }

    private var shouldShowBatterySection: Bool {
        settings.deviceBatteryEnabled
    }

    private var shouldShowQuickLaunchSection: Bool {
        !scriptShortcuts.shortcuts.isEmpty
    }

    private var shouldShowClipboardSection: Bool {
        settings.clipboardHistoryEnabled
    }

    private var shouldShowWallpaperSection: Bool {
        settings.wallpaperRefreshEnabled
    }

    private var shouldShowModuleRow: Bool {
        shouldShowWeatherSection || shouldShowBatterySection || shouldShowWallpaperSection || shouldShowClipboardSection || shouldShowQuickLaunchSection
    }

    private var isSearchingApps: Bool {
        !localAppSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryBatterySnapshot: DeviceBatterySnapshot? {
        battery.snapshot.internalBattery ?? battery.snapshot.accessories.first
    }

    private var batteryLevelProgress: CGFloat {
        CGFloat((primaryBatterySnapshot?.percentage ?? 0)) / 100
    }

    private var batteryCenterSymbolName: String {
        primaryBatterySnapshot?.kind.symbolName ?? "battery.100"
    }

    private var batteryCenterValueText: String {
        primaryBatterySnapshot?.percentageText ?? "--"
    }

    private var batteryPrimaryCaption: String {
        guard let primaryBattery = primaryBatterySnapshot else {
            return battery.snapshot.disconnectedAccessoryCount > 0 ? "等待设备连接" : "暂无设备"
        }

        if primaryBattery.kind == .mac {
            return primaryBattery.isCharging ? "本机正在充电" : "本机电量"
        }

        return primaryBattery.name
    }

    private var batteryAccessoryStatusText: String {
        return "暂无蓝牙外设"
    }

    private var batteryRingColor: Color {
        guard let primaryBattery = primaryBatterySnapshot else {
            return style.secondaryText(0.55)
        }

        if primaryBattery.isCharging {
            return style.chargingAccent
        }

        switch primaryBattery.percentage {
        case 51 ... 100:
            return Color(red: 0.54, green: 0.85, blue: 0.58)
        case 21 ... 50:
            return Color(red: 0.95, green: 0.76, blue: 0.31)
        default:
            return Color(red: 0.96, green: 0.42, blue: 0.33)
        }
    }

    private var weatherPlaceholderTitle: String {
        switch weather.authorizationStatus {
        case .notDetermined:
            return "需要定位权限"
        case .denied, .restricted:
            return "天气不可用"
        case .authorizedAlways, .authorizedWhenInUse:
            return weather.isLoading ? "正在获取天气" : "天气暂不可用"
        @unknown default:
            return "天气暂不可用"
        }
    }

    private var wallpaperHeroTitle: String {
        if let lastWallpaperName = wallpaper.lastWallpaperName {
            return lastWallpaperName
        }

        if wallpaper.selectedDirectoryURL == nil {
            return "选择文件夹"
        }

        return wallpaper.isRefreshing ? "正在刷新" : "随机壁纸"
    }

    private var wallpaperSubtitle: String {
        if let selectedFolderName = wallpaper.selectedFolderName {
            if settings.wallpaperAutoRefreshEnabled {
                return wallpaper.automaticRefreshCompactText
            }

            return selectedFolderName
        }

        return wallpaper.statusMessage
    }

    private func formattedTemperature(_ temperature: Measurement<UnitTemperature>?) -> String {
        guard let temperature else {
            return "--"
        }

        let measurement = temperature.converted(to: .celsius).value.rounded()
        return "\(Int(measurement))°"
    }
}

private struct QuickLaunchShortcutReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedShortcutID: UUID?
    @Binding var isEditing: Bool
    let store: ScriptShortcutStore

    func dropEntered(info: DropInfo) {
        guard isEditing,
              let draggedShortcutID,
              draggedShortcutID != targetID
        else {
            return
        }

        _ = store.moveShortcut(id: draggedShortcutID, to: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedShortcutID = nil
        store.completeReorder()
        return true
    }
}

private struct NotchSurfaceShape: InsettableShape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get {
            .init(.init(topCornerRadius, bottomCornerRadius), insetAmount)
        }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            insetAmount = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let maxRadius = min(rect.width, rect.height) / 2
        let resolvedTop = max(0, min(topCornerRadius, maxRadius))
        let resolvedBottom = max(0, min(bottomCornerRadius, maxRadius))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + resolvedTop, y: rect.minY))

        path.addLine(
            to: CGPoint(x: rect.maxX - resolvedTop, y: rect.minY)
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + resolvedTop),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        path.addLine(
            to: CGPoint(x: rect.maxX, y: rect.maxY - resolvedBottom)
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - resolvedBottom, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        path.addLine(
            to: CGPoint(x: rect.minX + resolvedBottom, y: rect.maxY)
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - resolvedBottom),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        path.addLine(
            to: CGPoint(x: rect.minX, y: rect.minY + resolvedTop)
        )

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + resolvedTop, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
