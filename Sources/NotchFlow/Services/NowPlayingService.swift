import AppKit
import Combine
import CoreLocation
import Foundation
import WeatherKit

@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var snapshot = NowPlayingSnapshot.empty
    @Published private(set) var sourceLabel = "Idle"

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var pollingInterval: TimeInterval = 2.0

    func start() {
        installObservers()
        scheduleTimer()
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()

        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func setInteractiveRefresh(_ isInteractive: Bool) {
        let nextInterval = isInteractive ? 1.0 : 2.0
        guard pollingInterval != nextInterval else {
            return
        }

        pollingInterval = nextInterval
        scheduleTimer()
    }

    func refresh() {
        refreshTask?.cancel()

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            if let remotePayload = await MediaRemoteBridge.shared.fetchNowPlaying() {
                snapshot = NowPlayingSnapshot(
                    title: remotePayload.title,
                    artist: remotePayload.artist,
                    album: remotePayload.album,
                    sourceApp: "System Now Playing",
                    isPlaying: remotePayload.isPlaying,
                    artworkData: remotePayload.artworkData
                )
                sourceLabel = "System"
                return
            }

            if let musicPayload = MusicAppleScriptBridge.fetchNowPlaying() {
                snapshot = NowPlayingSnapshot(
                    title: musicPayload.title,
                    artist: musicPayload.artist,
                    album: musicPayload.album,
                    sourceApp: "Music",
                    isPlaying: musicPayload.isPlaying,
                    artworkData: nil
                )
                sourceLabel = "Music"
                return
            }

            snapshot = .empty
            sourceLabel = "Idle"
        }
    }

    func togglePlayPause() {
        if MediaRemoteBridge.shared.send(.togglePlayPause) {
            scheduleRefresh(after: 0.35)
            return
        }

        if MusicAppleScriptBridge.togglePlayPause() {
            scheduleRefresh(after: 0.35)
        }
    }

    func nextTrack() {
        if MediaRemoteBridge.shared.send(.nextTrack) {
            scheduleRefresh(after: 0.35)
            return
        }

        if MusicAppleScriptBridge.nextTrack() {
            scheduleRefresh(after: 0.35)
        }
    }

    func previousTrack() {
        if MediaRemoteBridge.shared.send(.previousTrack) {
            scheduleRefresh(after: 0.35)
            return
        }

        if MusicAppleScriptBridge.previousTrack() {
            scheduleRefresh(after: 0.35)
        }
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            refresh()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func installObservers() {
        guard observers.isEmpty else {
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        let refreshNames = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
        ]

        observers = refreshNames.map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }
    }
}

@MainActor
final class WeatherForecastService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var snapshot = WeatherSnapshot.empty
    @Published private(set) var attribution = WeatherAttributionSnapshot.empty
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "等待获取天气"

    private let settings: AppSettings
    private let locationManager = CLLocationManager()
    private let weatherService = WeatherKit.WeatherService.shared
    private let refreshInterval: TimeInterval = 30 * 60
    private var refreshTimer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var attributionTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var lastRefreshDate: Date?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func start() {
        guard refreshTimer == nil else {
            return
        }

        authorizationStatus = locationManager.authorizationStatus
        bindSettings()
        scheduleRefreshTimer()

        if settings.weatherEnabled {
            refresh(force: true)
        } else {
            statusMessage = "天气已关闭"
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        fetchTask?.cancel()
        attributionTask?.cancel()
        cancellables.removeAll()
    }

    func requestLocationAuthorization() {
        guard settings.weatherEnabled else {
            return
        }

        guard CLLocationManager.locationServicesEnabled() else {
            snapshot = .empty
            statusMessage = "定位服务不可用"
            return
        }

        let status = locationManager.authorizationStatus
        authorizationStatus = status

        if status == .notDetermined {
            isLoading = true
            statusMessage = "请求定位权限..."
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func refresh(force: Bool = false) {
        guard settings.weatherEnabled else {
            clearWeather()
            statusMessage = "天气已关闭"
            return
        }

        guard CLLocationManager.locationServicesEnabled() else {
            snapshot = .empty
            isLoading = false
            statusMessage = "定位服务不可用"
            return
        }

        if !force,
           let lastRefreshDate,
           snapshot.hasContent,
           Date().timeIntervalSince(lastRefreshDate) < refreshInterval / 2 {
            return
        }

        let status = locationManager.authorizationStatus
        authorizationStatus = status

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .notDetermined:
            requestLocationAuthorization()
        case .restricted:
            snapshot = .empty
            isLoading = false
            statusMessage = "定位权限受限"
        case .denied:
            snapshot = .empty
            isLoading = false
            statusMessage = "请在系统设置中允许定位"
        @unknown default:
            snapshot = .empty
            isLoading = false
            statusMessage = "无法访问天气"
        }
    }

    func refreshIfNeeded(maximumAge: TimeInterval = 10 * 60) {
        guard settings.weatherEnabled else {
            return
        }

        guard !snapshot.hasContent || lastRefreshDate == nil || Date().timeIntervalSince(lastRefreshDate!) >= maximumAge else {
            return
        }

        refresh(force: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            refresh(force: true)
        case .notDetermined:
            statusMessage = "等待定位权限"
        case .restricted:
            snapshot = .empty
            isLoading = false
            statusMessage = "定位权限受限"
        case .denied:
            snapshot = .empty
            isLoading = false
            statusMessage = "请在系统设置中允许定位"
        @unknown default:
            snapshot = .empty
            isLoading = false
            statusMessage = "无法访问天气"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isLoading = false
            statusMessage = "未获取到当前位置"
            return
        }

        fetchWeather(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        if snapshot.hasContent {
            statusMessage = "天气更新失败"
        } else {
            statusMessage = Self.message(for: error)
        }
    }

    private func bindSettings() {
        guard cancellables.isEmpty else {
            return
        }

        settings.$weatherEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else {
                    return
                }

                if isEnabled {
                    self.statusMessage = "准备获取天气"
                    self.refresh(force: true)
                } else {
                    self.clearWeather()
                    self.statusMessage = "天气已关闭"
                }
            }
            .store(in: &cancellables)
    }

    private func requestLocation() {
        isLoading = true
        statusMessage = snapshot.hasContent ? "更新天气中..." : "获取当前位置天气..."
        locationManager.requestLocation()
    }

    private func fetchWeather(for location: CLLocation) {
        fetchTask?.cancel()
        attributionTask?.cancel()

        fetchTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let weather = try await weatherService.weather(for: location)
                guard !Task.isCancelled else {
                    return
                }

                snapshot = WeatherSnapshot(weather: weather)
                lastRefreshDate = Date()
                isLoading = false
                statusMessage = "由 Apple Weather 提供"
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                isLoading = false
                if !snapshot.hasContent {
                    snapshot = .empty
                }
                statusMessage = Self.message(for: error)
            }
        }

        attributionTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let fetchedAttribution = try await weatherService.attribution
                guard !Task.isCancelled else {
                    return
                }

                attribution = WeatherAttributionSnapshot(attribution: fetchedAttribution)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
            }
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(force: true)
            }
        }
    }

    private func clearWeather() {
        fetchTask?.cancel()
        attributionTask?.cancel()
        snapshot = .empty
        attribution = .empty
        isLoading = false
        lastRefreshDate = nil
    }

    private static func message(for error: Error) -> String {
        if let weatherError = error as? WeatherKit.WeatherError {
            switch weatherError {
            case .permissionDenied:
                return "WeatherKit 权限不可用"
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        let description = error.localizedDescription
        let normalized = description.lowercased()
        if normalized.contains("entitlement") || normalized.contains("jwt") {
            return "需要为 App ID 打开 WeatherKit capability"
        }

        if normalized.contains("network") || normalized.contains("internet") {
            return "网络不可用"
        }

        return "天气暂不可用"
    }
}
