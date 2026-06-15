import AppKit
import Combine
import Foundation

protocol WallpaperFileScanning: Sendable {
    func wallpaperURL(in directoryURL: URL, excluding lastWallpaperURL: URL?) -> URL?
}

protocol WallpaperApplying: Sendable {
    func applyWallpaper(_ wallpaperURL: URL) throws
}

struct NSWorkspaceWallpaperApplier: WallpaperApplying {
    func applyWallpaper(_ wallpaperURL: URL) throws {
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens

        for screen in screens {
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            try NSWorkspace.shared.setDesktopImageURL(wallpaperURL, for: screen, options: options)
        }
    }
}

@MainActor
final class WallpaperRefreshService: ObservableObject {
    private enum Keys {
        static let selectedFolderPath = "WallpaperRefreshSelectedFolderPath"
        static let lastWallpaperPath = "WallpaperRefreshLastWallpaperPath"
    }

    @Published private(set) var selectedDirectoryURL: URL?
    @Published private(set) var lastWallpaperURL: URL?
    @Published private(set) var isRefreshing = false
    @Published private(set) var nextRefreshDate: Date?
    @Published private(set) var statusMessage = "选择图片文件夹后即可随机刷新壁纸"

    private let settings: AppSettings
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let fileScanner: any WallpaperFileScanning
    private let wallpaperApplier: any WallpaperApplying
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        fileScanner: (any WallpaperFileScanning)? = nil,
        wallpaperApplier: any WallpaperApplying = NSWorkspaceWallpaperApplier()
    ) {
        self.settings = settings
        self.defaults = defaults
        self.fileManager = fileManager
        self.fileScanner = fileScanner ?? WallpaperRefreshFileScanner(fileManager: fileManager)
        self.wallpaperApplier = wallpaperApplier

        if let folderPath = defaults.string(forKey: Keys.selectedFolderPath), !folderPath.isEmpty {
            selectedDirectoryURL = URL(fileURLWithPath: folderPath, isDirectory: true)
            statusMessage = "已选择壁纸文件夹"
        }

        if let wallpaperPath = defaults.string(forKey: Keys.lastWallpaperPath), !wallpaperPath.isEmpty {
            lastWallpaperURL = URL(fileURLWithPath: wallpaperPath, isDirectory: false)
        }
    }

    var automaticRefreshStatusText: String {
        guard settings.wallpaperAutoRefreshEnabled else {
            return "已关闭"
        }

        guard selectedDirectoryURL != nil else {
            return "等待选择壁纸文件夹"
        }

        guard let nextRefreshDate else {
            return "准备中"
        }

        return "每 \(settings.wallpaperRefreshIntervalPreset.title)，下次 \(Self.timeFormatter.string(from: nextRefreshDate))"
    }

    var automaticRefreshCompactText: String {
        guard settings.wallpaperAutoRefreshEnabled else {
            return "自动已关闭"
        }

        guard selectedDirectoryURL != nil else {
            return "等待选择文件夹"
        }

        return "每 \(settings.wallpaperRefreshIntervalPreset.title) 自动更换"
    }

    var selectedFolderName: String? {
        selectedDirectoryURL?.lastPathComponent
    }

    var selectedFolderPath: String? {
        selectedDirectoryURL?.path
    }

    var lastWallpaperName: String? {
        lastWallpaperURL?.deletingPathExtension().lastPathComponent
    }

    var canRefresh: Bool {
        selectedDirectoryURL != nil && !isRefreshing
    }

    func start() {
        bindSettings()
        syncAutomaticRefreshSchedule()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        nextRefreshDate = nil
        cancellables.removeAll()
    }

    func chooseWallpaperFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择壁纸文件夹"
        panel.message = "NotchFlow 会从这个文件夹随机挑选图片并刷新到所有屏幕。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if let selectedDirectoryURL {
            panel.directoryURL = selectedDirectoryURL
        }

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        setWallpaperFolder(folderURL)
        refresh()
    }

    func clearWallpaperFolder() {
        refreshTask?.cancel()
        refreshTask = nil
        selectedDirectoryURL = nil
        lastWallpaperURL = nil
        isRefreshing = false
        nextRefreshDate = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        defaults.removeObject(forKey: Keys.selectedFolderPath)
        defaults.removeObject(forKey: Keys.lastWallpaperPath)
        statusMessage = "选择图片文件夹后即可随机刷新壁纸"
    }

    func refreshOrChooseFolder() {
        guard selectedDirectoryURL != nil else {
            chooseWallpaperFolder()
            return
        }

        refresh()
    }

    func refresh() {
        guard !isRefreshing else {
            return
        }

        guard let selectedDirectoryURL else {
            statusMessage = "请先选择壁纸文件夹"
            return
        }

        guard fileManager.fileExists(atPath: selectedDirectoryURL.path) else {
            statusMessage = "壁纸文件夹不可用"
            return
        }

        isRefreshing = true
        statusMessage = "正在挑选壁纸..."

        let previousWallpaperURL = lastWallpaperURL

        refreshTask = Task.detached(priority: .utility) { [fileScanner, wallpaperApplier] in
            let wallpaperURL = fileScanner.wallpaperURL(
                in: selectedDirectoryURL,
                excluding: previousWallpaperURL
            )
            guard !Task.isCancelled else {
                return
            }

            let result: WallpaperRefreshResult
            if let wallpaperURL {
                do {
                    try wallpaperApplier.applyWallpaper(wallpaperURL)
                    result = .success(wallpaperURL)
                } catch {
                    result = .failure(error.localizedDescription)
                }
            } else {
                result = .empty
            }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else {
                    return
                }

                guard self.selectedDirectoryURL == selectedDirectoryURL else {
                    self.isRefreshing = false
                    self.refreshTask = nil
                    return
                }

                switch result {
                case .empty:
                    self.isRefreshing = false
                    self.refreshTask = nil
                    self.statusMessage = "文件夹内没有可用图片"
                case let .success(wallpaperURL):
                    self.lastWallpaperURL = wallpaperURL
                    self.defaults.set(wallpaperURL.path, forKey: Keys.lastWallpaperPath)
                    self.statusMessage = "已刷新：\(wallpaperURL.deletingPathExtension().lastPathComponent)"
                    self.isRefreshing = false
                    self.refreshTask = nil
                    self.syncAutomaticRefreshSchedule()
                case let .failure(message):
                    self.statusMessage = "刷新失败：\(message)"
                    self.isRefreshing = false
                    self.refreshTask = nil
                }
            }
        }
    }

    private func setWallpaperFolder(_ folderURL: URL) {
        let resolvedURL = folderURL.standardizedFileURL
        selectedDirectoryURL = resolvedURL
        defaults.set(resolvedURL.path, forKey: Keys.selectedFolderPath)
        statusMessage = "已选择：\(resolvedURL.lastPathComponent)"
        syncAutomaticRefreshSchedule()
    }

    private func bindSettings() {
        guard cancellables.isEmpty else {
            return
        }

        settings.$wallpaperAutoRefreshEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else {
                    return
                }

                self.syncAutomaticRefreshSchedule()

                if isEnabled, self.selectedDirectoryURL == nil {
                    self.statusMessage = "自动换壁纸已开启，请先选择壁纸文件夹"
                } else if !isEnabled {
                    self.statusMessage = "自动换壁纸已关闭"
                }
            }
            .store(in: &cancellables)

        settings.$wallpaperRefreshIntervalPreset
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.syncAutomaticRefreshSchedule()
            }
            .store(in: &cancellables)
    }

    private func syncAutomaticRefreshSchedule() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        nextRefreshDate = nil

        guard settings.wallpaperAutoRefreshEnabled, selectedDirectoryURL != nil else {
            return
        }

        let interval = settings.wallpaperRefreshIntervalPreset.timeInterval
        let nextDate = Date().addingTimeInterval(interval)
        nextRefreshDate = nextDate

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private enum WallpaperRefreshResult: Sendable {
    case empty
    case success(URL)
    case failure(String)
}

private final class WallpaperRefreshFileScanner: WallpaperFileScanning, @unchecked Sendable {
    private let fileManager: FileManager
    private let supportedImageExtensions = Set([
        "avif",
        "bmp",
        "gif",
        "heic",
        "heif",
        "jpeg",
        "jpg",
        "png",
        "tif",
        "tiff",
        "webp",
    ])

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func wallpaperURL(in directoryURL: URL, excluding lastWallpaperURL: URL?) -> URL? {
        let imageURLs = imageURLs(in: directoryURL)
        let candidates = candidateWallpaperURLs(from: imageURLs, excluding: lastWallpaperURL)
        return candidates.randomElement() ?? imageURLs.randomElement()
    }

    private func imageURLs(in directoryURL: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            guard supportedImageExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else {
                continue
            }

            urls.append(fileURL.standardizedFileURL)
        }

        return urls.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private func candidateWallpaperURLs(from imageURLs: [URL], excluding lastWallpaperURL: URL?) -> [URL] {
        guard imageURLs.count > 1, let lastWallpaperURL else {
            return imageURLs
        }

        let lastPath = lastWallpaperURL.standardizedFileURL.path
        let candidates = imageURLs.filter { $0.path != lastPath }
        return candidates.isEmpty ? imageURLs : candidates
    }
}
