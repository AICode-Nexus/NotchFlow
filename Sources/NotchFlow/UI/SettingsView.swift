import SwiftUI

private enum SettingsTab: Hashable {
    case general
    case weather
    case battery
    case clipboard
    case wallpaper
    case nowPlaying
    case aiUsage
    case shortcuts

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .weather:
            return "天气"
        case .battery:
            return "电量"
        case .clipboard:
            return "剪贴板"
        case .wallpaper:
            return "壁纸"
        case .nowPlaying:
            return "媒体"
        case .aiUsage:
            return "AI 用量"
        case .shortcuts:
            return "快捷启动"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .weather:
            return "cloud.sun"
        case .battery:
            return "battery.100"
        case .clipboard:
            return "doc.on.clipboard"
        case .wallpaper:
            return "photo.on.rectangle.angled"
        case .nowPlaying:
            return "music.note"
        case .aiUsage:
            return "sparkles"
        case .shortcuts:
            return "bolt.fill"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: NotchFlowAppModel
    @State private var selectedTab: SettingsTab = .general
    @State private var showClearConfirmation = false

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsForm {
                generalSections
            }
            .tabItem {
                Label(SettingsTab.general.title, systemImage: SettingsTab.general.systemImage)
            }
            .tag(SettingsTab.general)

            settingsForm {
                weatherSections
            }
            .tabItem {
                Label(SettingsTab.weather.title, systemImage: SettingsTab.weather.systemImage)
            }
            .tag(SettingsTab.weather)

            settingsForm {
                batterySections
            }
            .tabItem {
                Label(SettingsTab.battery.title, systemImage: SettingsTab.battery.systemImage)
            }
            .tag(SettingsTab.battery)

            settingsForm {
                clipboardSections
            }
            .tabItem {
                Label(SettingsTab.clipboard.title, systemImage: SettingsTab.clipboard.systemImage)
            }
            .tag(SettingsTab.clipboard)

            settingsForm {
                wallpaperSections
            }
            .tabItem {
                Label(SettingsTab.wallpaper.title, systemImage: SettingsTab.wallpaper.systemImage)
            }
            .tag(SettingsTab.wallpaper)

            settingsForm {
                nowPlayingSections
            }
            .tabItem {
                Label(SettingsTab.nowPlaying.title, systemImage: SettingsTab.nowPlaying.systemImage)
            }
            .tag(SettingsTab.nowPlaying)

            settingsForm {
                aiUsageSections
            }
            .tabItem {
                Label(SettingsTab.aiUsage.title, systemImage: SettingsTab.aiUsage.systemImage)
            }
            .tag(SettingsTab.aiUsage)

            settingsForm {
                shortcutsSections
            }
            .tabItem {
                Label(SettingsTab.shortcuts.title, systemImage: SettingsTab.shortcuts.systemImage)
            }
            .tag(SettingsTab.shortcuts)
        }
        .frame(width: 620, height: 540)
    }

    private var autoHideDelayLabel: String {
        if model.settings.autoHideDelay == 0 {
            return "立即"
        }

        return String(format: "%.1f 秒", model.settings.autoHideDelay)
    }

    private var weatherPermissionLabel: String {
        switch model.weather.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "已允许"
        case .notDetermined:
            "待授权"
        case .restricted:
            "受限"
        case .denied:
            "已拒绝"
        @unknown default:
            "未知"
        }
    }

    private var aiUsageTodayLabel: String {
        "\(AITokenUsageFormatter.tokenCount(model.aiTokenUsage.todayTotalTokens)) token"
    }

    private var aiUsageSevenDayLabel: String {
        "\(AITokenUsageFormatter.tokenCount(model.aiTokenUsage.sevenDayTotalTokens)) token"
    }

    private var aiUsageThirtyDayLabel: String {
        "\(AITokenUsageFormatter.tokenCount(model.aiTokenUsage.thirtyDayTotalTokens)) token"
    }

    @ViewBuilder
    private var generalSections: some View {
        Section("交互") {
            Toggle(
                "悬停展开面板",
                isOn: Binding(
                    get: { model.settings.hoverToExpand },
                    set: { model.settings.hoverToExpand = $0 }
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("自动收起延迟")
                    Spacer()
                    Text(autoHideDelayLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { model.settings.autoHideDelay },
                        set: { model.settings.autoHideDelay = $0 }
                    ),
                    in: 0.0 ... 3.0,
                    step: 0.1
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

            HStack {
                Text("全局快捷键")
                Spacer()
                Text(model.settings.hotKeyDescription)
                    .foregroundStyle(.secondary)
            }
        }

        Section("启动") {
            Toggle(
                "开机自启",
                isOn: Binding(
                    get: { model.launchAtLogin.isEnabled },
                    set: { enabled in
                        Task {
                            await model.launchAtLogin.setEnabled(enabled)
                        }
                    }
                )
            )
            .disabled(model.launchAtLogin.isWorking || !model.launchAtLogin.isSupported)

            Text(model.launchAtLogin.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Section("面板") {
            Picker(
                "配色模式",
                selection: Binding(
                    get: { model.settings.panelAppearanceMode },
                    set: { model.settings.panelAppearanceMode = $0 }
                )
            ) {
                ForEach(PanelAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker(
                "面板字号",
                selection: Binding(
                    get: { model.settings.panelTextSizePreset },
                    set: { model.settings.panelTextSizePreset = $0 }
                )
            ) {
                ForEach(PanelTextSizePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Button("展开并固定面板") {
                model.panelController.expandAndPin()
            }

            Button("收起到紧凑态") {
                model.collapsePanel()
            }

            Button("重新定位到当前屏幕") {
                model.repositionPanel()
            }
        }
    }

    @ViewBuilder
    private var weatherSections: some View {
        Section("天气") {
            Toggle(
                "显示天气",
                isOn: Binding(
                    get: { model.settings.weatherEnabled },
                    set: { model.settings.weatherEnabled = $0 }
                )
            )

            LabeledContent("定位权限", value: weatherPermissionLabel)
            LabeledContent("状态", value: model.weather.statusMessage)

            HStack {
                Button("请求定位权限") {
                    model.weather.requestLocationAuthorization()
                }
                .disabled(!model.settings.weatherEnabled || model.weather.authorizationStatus != .notDetermined)

                Button("立即刷新天气") {
                    model.weather.refresh(force: true)
                }
                .disabled(!model.settings.weatherEnabled)
            }
        }
    }

    @ViewBuilder
    private var batterySections: some View {
        Section("设备电量") {
            Toggle(
                "显示设备电量",
                isOn: Binding(
                    get: { model.settings.deviceBatteryEnabled },
                    set: { model.settings.deviceBatteryEnabled = $0 }
                )
            )

            LabeledContent(
                "Mac 电量",
                value: model.battery.snapshot.internalBattery?.percentageText ?? "不可用"
            )
            LabeledContent("已连接蓝牙外设", value: "\(model.battery.snapshot.accessoryCount) 个")
            LabeledContent("状态", value: model.battery.statusMessage)

            Button("立即刷新设备电量") {
                model.battery.refresh(force: true)
            }
            .disabled(!model.settings.deviceBatteryEnabled)
        }

        Section("充电限制") {
            Toggle(
                "启用充电限制",
                isOn: Binding(
                    get: { model.settings.chargeLimitEnabled },
                    set: { enabled in
                        model.chargeLimit.setEnabled(enabled)
                    }
                )
            )

            LabeledContent("状态", value: model.chargeLimit.state.displayText)

            if !model.chargeLimit.isHelperInstalled {
                Button("安装 Helper") {
                    model.chargeLimit.installHelper()
                }
            }

            if model.settings.chargeLimitEnabled {
                LabeledContent("当前电量", value: "\(model.chargeLimit.currentPercent)%")
                LabeledContent("充电上限", value: "\(model.settings.chargeLimitMax)%")
                LabeledContent("恢复阈值", value: "\(model.settings.chargeLimitMin)%")
            }

            Text("电量达到 \(model.settings.chargeLimitMax)% 时自动停止充电，低于 \(model.settings.chargeLimitMin)% 时恢复。保护电池寿命。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var clipboardSections: some View {
        Section("剪贴板") {
            Toggle(
                "显示剪贴板历史",
                isOn: Binding(
                    get: { model.settings.clipboardHistoryEnabled },
                    set: { model.settings.clipboardHistoryEnabled = $0 }
                )
            )

            LabeledContent("已记录文本", value: "\(model.clipboardHistory.entries.count) 条")
            LabeledContent("状态", value: model.clipboardHistory.statusMessage)

            Text("仅在本机保存纯文本历史，不会上传到网络。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("清空剪贴板历史") {
                model.clipboardHistory.clearHistory()
            }
            .disabled(model.clipboardHistory.entries.isEmpty)
        }
    }

    @ViewBuilder
    private var wallpaperSections: some View {
        Section("壁纸刷新") {
            Toggle(
                "显示壁纸刷新",
                isOn: Binding(
                    get: { model.settings.wallpaperRefreshEnabled },
                    set: { model.settings.wallpaperRefreshEnabled = $0 }
                )
            )

            LabeledContent("壁纸文件夹") {
                Text(model.wallpaper.selectedFolderPath ?? "未选择")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            LabeledContent("最近壁纸", value: model.wallpaper.lastWallpaperName ?? "暂无")
            LabeledContent("状态", value: model.wallpaper.statusMessage)
            LabeledContent("定时状态", value: model.wallpaper.automaticRefreshStatusText)

            Text("从选定文件夹随机挑选图片，并应用到当前所有屏幕。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(
                "自动定时换壁纸",
                isOn: Binding(
                    get: { model.settings.wallpaperAutoRefreshEnabled },
                    set: { model.settings.wallpaperAutoRefreshEnabled = $0 }
                )
            )

            Picker(
                "更换间隔",
                selection: Binding(
                    get: { model.settings.wallpaperRefreshIntervalPreset },
                    set: { model.settings.wallpaperRefreshIntervalPreset = $0 }
                )
            ) {
                ForEach(WallpaperRefreshIntervalPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .disabled(!model.settings.wallpaperAutoRefreshEnabled)

            HStack {
                Button("选择壁纸文件夹") {
                    model.wallpaper.chooseWallpaperFolder()
                }

                Button("立即刷新壁纸") {
                    model.wallpaper.refreshOrChooseFolder()
                }
                .disabled(model.wallpaper.isRefreshing)

                Button("清除文件夹") {
                    model.wallpaper.clearWallpaperFolder()
                }
                .disabled(model.wallpaper.selectedDirectoryURL == nil)
            }
        }
    }

    @ViewBuilder
    private var nowPlayingSections: some View {
        Section("正在播放") {
            Toggle(
                "启用媒体检测",
                isOn: Binding(
                    get: { model.settings.nowPlayingEnabled },
                    set: { model.settings.nowPlayingEnabled = $0 }
                )
            )

            if model.settings.nowPlayingEnabled {
                LabeledContent("当前状态", value: model.nowPlaying.snapshot.isPlaying ? "播放中" : "空闲 / 暂停")
                LabeledContent("当前标题", value: model.nowPlaying.snapshot.title)
                LabeledContent("数据来源", value: model.nowPlaying.sourceLabel)

                Button("立即刷新媒体状态") {
                    model.nowPlaying.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private var aiUsageSections: some View {
        Section("本机 AI token") {
            Toggle(
                "显示 AI 用量",
                isOn: Binding(
                    get: { model.settings.aiTokenUsageEnabled },
                    set: { model.settings.aiTokenUsageEnabled = $0 }
                )
            )

            Text("开启后仅在本机读取 Codex、Claude 等工具日志中的 usage/token 元数据，不读取对话正文，不上传网络。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LabeledContent("状态", value: model.aiTokenUsage.statusMessage)
            LabeledContent("最近刷新", value: model.aiTokenUsage.lastRefreshText)
            LabeledContent("今日", value: aiUsageTodayLabel)
            LabeledContent("近 7 天", value: aiUsageSevenDayLabel)
            LabeledContent("近 30 天", value: aiUsageThirtyDayLabel)

            Button("立即刷新 AI 用量") {
                model.aiTokenUsage.refresh()
            }
            .disabled(!model.settings.aiTokenUsageEnabled || model.aiTokenUsage.isRefreshing)
        }

        Section("数据源") {
            if model.aiTokenUsage.summary.sourceStatuses.isEmpty {
                Text(model.settings.aiTokenUsageEnabled ? "刷新后显示数据源状态" : "开启后检测本机 AI 工具记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.aiTokenUsage.summary.sourceStatuses) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(status.displayName)
                            Spacer()
                            Text(status.state.title)
                                .foregroundStyle(status.state == .available ? .primary : .secondary)
                        }

                        Text(status.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let dirs = model.aiTokenUsage.sourceDirectories[status.id], !dirs.isEmpty {
                            ForEach(dirs) { dir in
                                HStack(spacing: 4) {
                                    Text(dir.displayPath)
                                        .font(.footnote)
                                        .foregroundStyle(.blue)
                                        .onTapGesture {
                                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.url.path)
                                        }
                                    Spacer()
                                    Text(dir.sizeText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        Section("存储管理") {
            LabeledContent("日志占用", value: model.aiTokenUsage.diskUsageText)

            Picker(
                "保留天数",
                selection: Binding(
                    get: { model.settings.logRetentionPreset },
                    set: { model.settings.logRetentionPreset = $0 }
                )
            ) {
                ForEach(LogRetentionPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Button("清除历史日志") {
                showClearConfirmation = true
            }
            .disabled(model.aiTokenUsage.isClearing)
            .confirmationDialog(
                "确认清除",
                isPresented: $showClearConfirmation
            ) {
                Button("清除超过 \(model.settings.logRetentionPreset.title) 的日志", role: .destructive) {
                    model.aiTokenUsage.clearOldLogs(retentionDays: model.settings.logRetentionPreset.rawValue)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除修改时间超过 \(model.settings.logRetentionPreset.title) 的 AI 工具日志文件（.jsonl），此操作不可撤销。")
            }

            if model.aiTokenUsage.isClearing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在清除...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let result = model.aiTokenUsage.lastClearResult {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var shortcutsSections: some View {
        ScriptShortcutsSettingsSection(settings: model.settings, store: model.scriptShortcuts)
    }

    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
