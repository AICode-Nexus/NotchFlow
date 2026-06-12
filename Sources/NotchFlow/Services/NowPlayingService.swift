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
    private let fallbackWeatherClient = OpenMeteoWeatherClient()
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
                refreshWeatherAttribution()
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                let weatherKitMessage = Self.message(for: error)

                do {
                    let fallbackSnapshot = try await fallbackWeatherClient.weather(for: location)
                    guard !Task.isCancelled else {
                        return
                    }

                    snapshot = fallbackSnapshot
                    attribution = OpenMeteoWeatherClient.attribution
                    lastRefreshDate = Date()
                    isLoading = false
                    statusMessage = "由 Open-Meteo 提供"
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    isLoading = false
                    if !snapshot.hasContent {
                        snapshot = .empty
                    }
                    statusMessage = weatherKitMessage
                }
            }
        }
    }

    private func refreshWeatherAttribution() {
        attributionTask?.cancel()
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

struct OpenMeteoWeatherCodeMapper {
    struct Presentation: Equatable {
        let symbolName: String
        let conditionName: String
    }

    static func presentation(for code: Int, isDay: Bool) -> Presentation {
        switch code {
        case 0:
            Presentation(symbolName: isDay ? "sun.max.fill" : "moon.stars.fill", conditionName: "晴朗")
        case 1:
            Presentation(symbolName: isDay ? "sun.max.fill" : "moon.fill", conditionName: "大致晴朗")
        case 2:
            Presentation(symbolName: isDay ? "cloud.sun.fill" : "cloud.moon.fill", conditionName: "局部多云")
        case 3:
            Presentation(symbolName: "cloud.fill", conditionName: "阴天")
        case 45, 48:
            Presentation(symbolName: "cloud.fog.fill", conditionName: "有雾")
        case 51, 53, 55:
            Presentation(symbolName: "cloud.drizzle.fill", conditionName: "毛毛雨")
        case 56, 57:
            Presentation(symbolName: "cloud.sleet.fill", conditionName: "冻毛雨")
        case 61, 63, 65:
            Presentation(symbolName: "cloud.rain.fill", conditionName: "下雨")
        case 66, 67:
            Presentation(symbolName: "cloud.sleet.fill", conditionName: "冻雨")
        case 71, 73, 75, 77:
            Presentation(symbolName: "cloud.snow.fill", conditionName: "下雪")
        case 80, 81, 82:
            Presentation(symbolName: "cloud.heavyrain.fill", conditionName: "阵雨")
        case 85, 86:
            Presentation(symbolName: "cloud.snow.fill", conditionName: "阵雪")
        case 95:
            Presentation(symbolName: "cloud.bolt.rain.fill", conditionName: "雷暴")
        case 96, 99:
            Presentation(symbolName: "cloud.hail.fill", conditionName: "雷暴冰雹")
        default:
            Presentation(symbolName: "cloud.sun.fill", conditionName: "天气")
        }
    }
}

private struct OpenMeteoWeatherClient {
    static let attribution = WeatherAttributionSnapshot(
        serviceName: "Open-Meteo",
        legalPageURL: URL(string: "https://open-meteo.com/"),
        combinedMarkDarkURL: nil,
        combinedMarkLightURL: nil
    )

    func weather(for location: CLLocation) async throws -> WeatherSnapshot {
        let url = try forecastURL(for: location)
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let forecast = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        return forecast.snapshot()
    }

    private func forecastURL(for location: CLLocation) throws -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.coordinate.longitude)),
            URLQueryItem(name: "current", value: [
                "temperature_2m",
                "relative_humidity_2m",
                "apparent_temperature",
                "is_day",
                "weather_code",
                "wind_speed_10m",
            ].joined(separator: ",")),
            URLQueryItem(name: "daily", value: [
                "temperature_2m_max",
                "temperature_2m_min",
                "uv_index_max",
            ].joined(separator: ",")),
            URLQueryItem(name: "hourly", value: [
                "temperature_2m",
                "weather_code",
            ].joined(separator: ",")),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "forecast_hours", value: "4"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        return url
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    let utcOffsetSeconds: Int?
    let current: Current
    let daily: Daily?
    let hourly: Hourly?

    enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case current
        case daily
        case hourly
    }

    func snapshot() -> WeatherSnapshot {
        let presentation = OpenMeteoWeatherCodeMapper.presentation(
            for: current.weatherCode,
            isDay: current.isDay != 0
        )

        return WeatherSnapshot(
            symbolName: presentation.symbolName,
            conditionName: presentation.conditionName,
            temperature: current.temperature.measurement(unit: .celsius),
            apparentTemperature: current.apparentTemperature?.measurement(unit: .celsius),
            highTemperature: daily?.temperatureMax.first?.measurement(unit: .celsius),
            lowTemperature: daily?.temperatureMin.first?.measurement(unit: .celsius),
            humidity: current.relativeHumidity.map { $0 / 100 },
            windSpeed: current.windSpeed.map { Measurement(value: $0, unit: UnitSpeed.kilometersPerHour) },
            uvIndex: daily?.uvIndexMax.first.map { Int($0.rounded()) },
            hourlyForecast: hourly?.snapshots(utcOffsetSeconds: utcOffsetSeconds ?? 0) ?? [],
            locationName: "当前位置"
        )
    }

    struct Current: Decodable {
        let temperature: Double
        let apparentTemperature: Double?
        let relativeHumidity: Double?
        let isDay: Int
        let weatherCode: Int
        let windSpeed: Double?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity = "relative_humidity_2m"
            case isDay = "is_day"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct Daily: Decodable {
        let temperatureMax: [Double]
        let temperatureMin: [Double]
        let uvIndexMax: [Double]

        enum CodingKeys: String, CodingKey {
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case uvIndexMax = "uv_index_max"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double]
        let weatherCode: [Int]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }

        func snapshots(utcOffsetSeconds: Int) -> [HourlyWeatherSnapshot] {
            let count = min(4, time.count, temperature.count, weatherCode.count)
            guard count > 0 else {
                return []
            }

            return (0..<count).map { index in
                let presentation = OpenMeteoWeatherCodeMapper.presentation(
                    for: weatherCode[index],
                    isDay: true
                )

                return HourlyWeatherSnapshot(
                    date: Self.date(
                        from: time[index],
                        utcOffsetSeconds: utcOffsetSeconds,
                        fallback: Date().addingTimeInterval(TimeInterval(index * 3600))
                    ),
                    symbolName: presentation.symbolName,
                    temperature: Measurement(value: temperature[index], unit: UnitTemperature.celsius)
                )
            }
        }

        private static func date(from string: String, utcOffsetSeconds: Int, fallback: Date) -> Date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            return formatter.date(from: string) ?? fallback
        }
    }
}

private extension Double {
    func measurement(unit: UnitTemperature) -> Measurement<UnitTemperature> {
        Measurement(value: self, unit: unit)
    }
}
