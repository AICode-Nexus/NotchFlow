import Combine
import AppKit
import SwiftUI

@MainActor
final class NotchPanelController: ObservableObject {
    private enum ScreenSelectionStrategy {
        case panel
        case cursor
    }

    @Published private(set) var isExpanded = false
    @Published private(set) var isPinned = false
    @Published private(set) var compactPanelSize = NSSize(width: 200, height: 38)
    @Published private(set) var expandedPanelSize = NSSize(width: 420, height: 248)
    @Published private(set) var isAttachedToNotch = false

    private let settings: AppSettings
    private let nowPlaying: NowPlayingService
    private let weather: WeatherForecastService
    private let battery: BatteryStatusService
    private let clipboardHistory: ClipboardHistoryService
    private let wallpaper: WallpaperRefreshService
    private let scriptShortcuts: ScriptShortcutStore
    private let localAppSearch: LocalAppSearchService
    private let chargeLimit: ChargeLimitService
    private let aiTokenUsage: AITokenUsageService
    private let screenHealth: ScreenHealthService

    private let frameAnimationDuration: TimeInterval = 0.22
    private let minimumHoverOpenDelay: TimeInterval = 0.20
    private let minimumAutoHideDelay: TimeInterval = 0.12
    private let hoverReopenSuppressionDuration: TimeInterval = 0.30

    private var panel: FloatingNotchPanel?
    private var observers: [NSObjectProtocol] = []
    private var hoverExpandWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []
    private var isPointerInsidePanel = false
    private var hoverOpenSuppressedUntil = Date.distantPast
    private var isFrameAnimationInFlight = false
    private var needsFrameRefreshAfterAnimation = false
    private var frameAnimationCompletionTask: Task<Void, Never>?

    private var panelMetrics: NotchPanelMetrics {
        NotchPanelMetrics(textScale: CGFloat(settings.panelTextSizePreset.scale))
    }

    init(
        settings: AppSettings,
        nowPlaying: NowPlayingService,
        weather: WeatherForecastService,
        battery: BatteryStatusService,
        clipboardHistory: ClipboardHistoryService,
        wallpaper: WallpaperRefreshService,
        scriptShortcuts: ScriptShortcutStore,
        localAppSearch: LocalAppSearchService,
        chargeLimit: ChargeLimitService,
        aiTokenUsage: AITokenUsageService,
        screenHealth: ScreenHealthService
    ) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.weather = weather
        self.battery = battery
        self.clipboardHistory = clipboardHistory
        self.wallpaper = wallpaper
        self.scriptShortcuts = scriptShortcuts
        self.localAppSearch = localAppSearch
        self.chargeLimit = chargeLimit
        self.aiTokenUsage = aiTokenUsage
        self.screenHealth = screenHealth
    }

    func start() {
        guard panel == nil else {
            return
        }

        compactPanelSize = panelMetrics.baseCompactSize
        refreshExpandedPanelSize()
        createPanel()
        installObservers()
        bindNowPlayingVisibility()
        applyCurrentFrame(animated: false, screenSelection: .panel)
        syncPanelVisibility()
        updateNowPlayingCadence()
    }

    func reposition() {
        applyCurrentFrame(animated: false, screenSelection: .cursor)
    }

    func hoverChanged(isHovering: Bool) {
        isPointerInsidePanel = isHovering

        if isHovering {
            cancelScheduledCollapse()
            scheduleHoverExpandIfNeeded()
            return
        }

        cancelScheduledHoverExpand()

        guard !isPinned else {
            return
        }

        guard !pointerIsInsideInteractionZone() else {
            return
        }

        scheduleCollapse()
    }

    func toggleFromHotKey() {
        if isPinned {
            collapseToCompact()
        } else {
            expandAndPin()
        }
    }

    func expandAndPin() {
        cancelScheduledHoverExpand()
        cancelScheduledCollapse()
        isPinned = true
        expand(animated: true)
    }

    func togglePin() {
        if isPinned {
            unpin()
        } else {
            expandAndPin()
        }
    }

    func unpin() {
        isPinned = false
        scheduleCollapse()
    }

    func collapseToCompact() {
        cancelScheduledHoverExpand()
        cancelScheduledCollapse()
        isPinned = false
        collapse(animated: true, suppressHoverOpenTemporarily: false)
    }

    private var hasExpandableContent: Bool {
        true
    }

    private func expand(animated: Bool) {
        guard !isExpanded else {
            applyCurrentFrame(animated: animated, screenSelection: .panel)
            refreshNowPlayingIfEnabled()
            updateNowPlayingCadence()
            return
        }

        isExpanded = true
        applyCurrentFrame(animated: animated, screenSelection: .panel)
        refreshNowPlayingIfEnabled()
        weather.refreshIfNeeded()
        battery.refreshIfNeeded(maximumAge: 60)
        aiTokenUsage.refreshIfNeeded()
        screenHealth.refreshNow()
        updateNowPlayingCadence()
    }

    private func collapse(animated: Bool, suppressHoverOpenTemporarily: Bool = true) {
        guard isExpanded else {
            applyCurrentFrame(animated: animated, screenSelection: .panel)
            updateNowPlayingCadence()
            return
        }

        if suppressHoverOpenTemporarily {
            hoverOpenSuppressedUntil = Date().addingTimeInterval(hoverReopenSuppressionDuration)
        }

        isExpanded = false
        applyCurrentFrame(animated: animated, screenSelection: .panel)
        updateNowPlayingCadence()
    }

    private func scheduleHoverExpandIfNeeded() {
        cancelScheduledHoverExpand()

        guard settings.hoverToExpand, !isPinned, !isExpanded else {
            return
        }

        guard Date() >= hoverOpenSuppressedUntil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            guard self.settings.hoverToExpand,
                  !self.isPinned,
                  !self.isExpanded,
                  Date() >= self.hoverOpenSuppressedUntil,
                  self.pointerIsInsideInteractionZone()
            else {
                return
            }

            self.expand(animated: true)
        }

        hoverExpandWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + minimumHoverOpenDelay,
            execute: workItem
        )
    }

    private func scheduleCollapse() {
        cancelScheduledCollapse()

        guard !pointerIsInsideInteractionZone() else {
            return
        }

        let delay = max(settings.autoHideDelay, minimumAutoHideDelay)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            guard !self.pointerIsInsideInteractionZone() else {
                return
            }

            self.collapse(animated: true, suppressHoverOpenTemporarily: true)
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    private func cancelScheduledHoverExpand() {
        hoverExpandWorkItem?.cancel()
        hoverExpandWorkItem = nil
    }

    private func cancelScheduledCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private func pointerIsInsideInteractionZone() -> Bool {
        guard let panel else {
            return isPointerInsidePanel
        }

        let mouseLocation = NSEvent.mouseLocation
        let hoverFrame = expandedHoverFrame(for: panel)
        return hoverFrame.contains(mouseLocation)
    }

    private func expandedHoverFrame(for panel: NSPanel) -> CGRect {
        let frame = panel.frame

        if isExpanded {
            return frame.insetBy(dx: -12, dy: -12)
        }

        return frame.insetBy(dx: -10, dy: -8)
    }

    private func bindNowPlayingVisibility() {
        guard cancellables.isEmpty else {
            return
        }

        nowPlaying.$snapshot
            .map(\.hasContent)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$nowPlayingEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
                self?.updateNowPlayingCadence(isEnabled: isEnabled)
            }
            .store(in: &cancellables)

        scriptShortcuts.$shortcuts
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$weatherEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$deviceBatteryEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$clipboardHistoryEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$wallpaperRefreshEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$aiTokenUsageEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$screenHealthEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$quickLaunchLayoutMode
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$quickLaunchShowsLabels
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(animateFrame: true)
            }
            .store(in: &cancellables)

        settings.$panelTextSizePreset
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleLayoutRefresh(syncVisibility: true, animateFrame: true)
            }
            .store(in: &cancellables)

    }

    private func scheduleLayoutRefresh(syncVisibility: Bool = false, animateFrame: Bool = false) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.refreshExpandedLayout(animated: animateFrame)

            if syncVisibility {
                self.syncPanelVisibility(
                    reapplyFrame: !self.isExpanded || !animateFrame,
                    animated: animateFrame
                )
            }
        }
    }

    private func syncPanelVisibility(reapplyFrame: Bool = true, animated: Bool = false) {
        guard let panel else {
            return
        }

        if !hasExpandableContent {
            cancelScheduledHoverExpand()
            cancelScheduledCollapse()
            isPinned = false
            isExpanded = false
            updateNowPlayingCadence()
        }

        if reapplyFrame || !hasExpandableContent {
            applyCurrentFrame(animated: animated, screenSelection: .panel)
        }
        panel.orderFrontRegardless()
    }

    private func createPanel() {
        let panel = FloatingNotchPanel(
            contentRect: NSRect(origin: .zero, size: compactPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow

        let rootView = NotchPanelView(
            panelController: self,
            nowPlaying: nowPlaying,
            weather: weather,
            battery: battery,
            clipboardHistory: clipboardHistory,
            settings: settings,
            wallpaper: wallpaper,
            scriptShortcuts: scriptShortcuts,
            localAppSearch: localAppSearch,
            chargeLimit: chargeLimit,
            aiTokenUsage: aiTokenUsage,
            screenHealth: screenHealth
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: compactPanelSize)
        hostingController.view.autoresizingMask = [.width, .height]
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.layer?.isOpaque = false
        panel.contentViewController = hostingController
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false

        self.panel = panel
    }

    private func applyCurrentFrame(animated: Bool, screenSelection: ScreenSelectionStrategy) {
        guard let panel, let screen = preferredScreen(using: screenSelection) else {
            return
        }

        if !animated, isFrameAnimationInFlight {
            needsFrameRefreshAfterAnimation = true
            return
        }

        let metrics = NotchMetrics(screen: screen)
        let targetSize = isExpanded ? expandedPanelSize : metrics.compactSize(baseSize: panelMetrics.baseCompactSize)

        isAttachedToNotch = metrics.hasNotch

        if !isExpanded && compactPanelSize != targetSize {
            compactPanelSize = targetSize
        }

        let originX: CGFloat
        if isExpanded {
            originX = metrics.anchorX - (targetSize.width / 2)
        } else {
            originX = metrics.compactOriginX(for: targetSize.width)
                ?? (metrics.anchorX - (targetSize.width / 2))
        }

        let origin = CGPoint(
            x: originX,
            y: screen.frame.maxY - targetSize.height - metrics.topOffset(
                isExpanded: isExpanded,
                compactHeight: targetSize.height
            )
        )

        let frame = NSRect(origin: origin, size: targetSize)

        if animated {
            beginFrameAnimationTracking()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = frameAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func beginFrameAnimationTracking() {
        isFrameAnimationInFlight = true
        needsFrameRefreshAfterAnimation = false
        frameAnimationCompletionTask?.cancel()

        frameAnimationCompletionTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: .seconds(frameAnimationDuration))
            self.isFrameAnimationInFlight = false

            guard self.needsFrameRefreshAfterAnimation else {
                return
            }

            self.needsFrameRefreshAfterAnimation = false
            self.applyCurrentFrame(animated: false, screenSelection: .panel)
        }
    }

    private func refreshExpandedPanelSize() {
        let metrics = panelMetrics
        let hasModuleRow = settings.weatherEnabled
            || settings.deviceBatteryEnabled
            || settings.clipboardHistoryEnabled
            || settings.wallpaperRefreshEnabled
            || settings.aiTokenUsageEnabled
            || settings.screenHealthEnabled
            || !scriptShortcuts.shortcuts.isEmpty
        var sectionHeights: [CGFloat] = []

        if settings.nowPlayingEnabled, nowPlaying.snapshot.hasContent {
            sectionHeights.append(metrics.nowPlayingSectionHeight)
        }

        if hasModuleRow {
            sectionHeights.append(metrics.moduleSectionHeight)
        }

        sectionHeights.append(searchSectionHeight())

        let spacing = CGFloat(sectionHeights.count) * metrics.expandedSectionSpacing
        let totalHeight = metrics.headerHeightEstimate
            + metrics.expandedVerticalPadding
            + spacing
            + sectionHeights.reduce(0, +)

        let screenWidth = currentPanelScreen()?.frame.width ?? .infinity
        expandedPanelSize = NSSize(
            width: min(expandedContentWidth + metrics.horizontalPadding, screenWidth - 32),
            height: max(totalHeight, 108)
        )
    }

    private func refreshExpandedLayout(animated: Bool = false) {
        refreshExpandedPanelSize()

        guard isExpanded else {
            return
        }

        applyCurrentFrame(animated: animated, screenSelection: .panel)
    }

    private func searchSectionHeight() -> CGFloat {
        panelMetrics.searchSectionHeight
    }

    private var expandedContentWidth: CGFloat {
        max(moduleRowContentWidth, quickLaunchModuleWidth)
    }

    private var moduleRowContentWidth: CGFloat {
        let metrics = panelMetrics
        let widths = [
            settings.weatherEnabled ? metrics.moduleUnitSize : nil,
            settings.deviceBatteryEnabled ? metrics.moduleUnitSize : nil,
            settings.wallpaperRefreshEnabled ? metrics.moduleUnitSize : nil,
            settings.aiTokenUsageEnabled ? aiTokenUsageModuleWidth : nil,
            settings.screenHealthEnabled ? screenHealthModuleWidth : nil,
            settings.clipboardHistoryEnabled ? clipboardModuleWidth : nil,
            scriptShortcuts.shortcuts.isEmpty ? nil : quickLaunchModuleWidth,
        ].compactMap { $0 }

        guard !widths.isEmpty else {
            return quickLaunchModuleWidth
        }

        return widths.reduce(0, +) + (CGFloat(widths.count - 1) * metrics.moduleSpacing)
    }

    private var quickLaunchModuleWidth: CGFloat {
        (panelMetrics.moduleUnitSize * 2) + panelMetrics.moduleSpacing
    }

    private var clipboardModuleWidth: CGFloat {
        panelMetrics.moduleUnitSize * 1.5
    }

    private var aiTokenUsageModuleWidth: CGFloat {
        panelMetrics.moduleUnitSize * 2
    }

    private var screenHealthModuleWidth: CGFloat {
        panelMetrics.moduleUnitSize * 1.5
    }

    private func preferredScreen(using strategy: ScreenSelectionStrategy) -> NSScreen? {
        switch strategy {
        case .panel:
            if let panelScreen = currentPanelScreen() {
                return panelScreen
            }
            if let mouseScreen = mouseScreen() {
                return mouseScreen
            }
        case .cursor:
            if let mouseScreen = mouseScreen() {
                return mouseScreen
            }
            if let panelScreen = currentPanelScreen() {
                return panelScreen
            }
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func mouseScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }

    private func currentPanelScreen() -> NSScreen? {
        if let panelScreen = panel?.screen {
            return panelScreen
        }

        guard let panel else {
            return nil
        }

        let samplePoint = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(samplePoint) })
    }

    private func installObservers() {
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reposition()
            }
        }

        let spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reposition()
            }
        }

        observers = [screenObserver, spaceObserver]
    }

    private func updateNowPlayingCadence() {
        updateNowPlayingCadence(isEnabled: settings.nowPlayingEnabled)
    }

    private func updateNowPlayingCadence(isEnabled: Bool) {
        guard isEnabled else {
            return
        }

        nowPlaying.setInteractiveRefresh(isExpanded || isPinned)
    }

    private func refreshNowPlayingIfEnabled() {
        guard settings.nowPlayingEnabled else {
            return
        }

        nowPlaying.refresh()
    }
}

private final class FloatingNotchPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct NotchMetrics {
    let screen: NSScreen

    private let minimumCompactWidth: CGFloat = 160
    private let compactBottomReveal: CGFloat = 2
    private let compactLeftReveal: CGFloat = 1
    private let compactRightReveal: CGFloat = 2

    var hasNotch: Bool {
        screen.safeAreaInsets.top > 0
    }

    var anchorX: CGFloat {
        notchFrame?.midX ?? screen.frame.midX
    }

    func compactSize(baseSize: NSSize) -> NSSize {
        guard let notchFrame else {
            if hasNotch {
                return NSSize(
                    width: baseSize.width,
                    height: screen.safeAreaInsets.top + compactBottomReveal
                )
            }

            return baseSize
        }

        let width = max(
            minimumCompactWidth,
            min(baseSize.width, notchFrame.width + compactLeftReveal + compactRightReveal)
        )

        let height = notchFrame.height + compactBottomReveal

        return NSSize(width: width, height: height)
    }

    func compactOriginX(for width: CGFloat) -> CGFloat? {
        guard let notchFrame else {
            return nil
        }

        let desiredWidth = notchFrame.width + compactLeftReveal + compactRightReveal
        guard abs(width - desiredWidth) < 0.5 else {
            return notchFrame.midX - (width / 2)
        }

        return notchFrame.minX - compactLeftReveal
    }

    func topOffset(isExpanded: Bool, compactHeight: CGFloat) -> CGFloat {
        guard !isExpanded else {
            return expandedTopOffset
        }

        if notchFrame != nil || hasNotch {
            return 0
        }

        return expandedTopOffset
    }

    private var expandedTopOffset: CGFloat {
        if notchFrame != nil || hasNotch {
            return 0
        }

        return 8
    }

    private var notchFrame: CGRect? {
        guard #available(macOS 12.0, *),
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea
        else {
            return nil
        }

        let width = rightArea.minX - leftArea.maxX
        guard width > 0 else {
            return nil
        }

        return CGRect(
            x: leftArea.maxX,
            y: min(leftArea.minY, rightArea.minY),
            width: width,
            height: max(leftArea.height, rightArea.height)
        )
    }
}
