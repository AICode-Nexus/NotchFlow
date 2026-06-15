import Foundation
import CoreLocation
@testable import NotchFlow
import XCTest

final class WeatherBatteryRegressionTests: XCTestCase {
    @MainActor
    func testWeatherSyncUsesCurrentSystemAuthorizationAndRequestsLocation() {
        let settings = AppSettings()
        settings.weatherEnabled = true
        let locationManager = FakeWeatherLocationManager(authorizationStatus: .notDetermined)
        let service = WeatherForecastService(settings: settings, locationManager: locationManager)

        XCTAssertEqual(service.authorizationStatus, .notDetermined)

        locationManager.authorizationStatus = .authorizedAlways
        service.synchronizeAuthorizationStatus(refreshIfAuthorized: true)

        XCTAssertEqual(service.authorizationStatus, .authorizedAlways)
        XCTAssertEqual(locationManager.requestLocationCallCount, 1)
    }

    func testWeatherEntitlementStaysEnabled() throws {
        let entitlementURL = packageRoot()
            .appendingPathComponent("App")
            .appendingPathComponent("NotchFlow.entitlements")

        let data = try Data(contentsOf: entitlementURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["com.apple.developer.weatherkit"] as? Bool, true)
    }

    func testCompactPresentationFallsBackToBatteryWhenWeatherHasNoContent() {
        let battery = DeviceBatterySnapshot(
            id: "internal-battery",
            name: "MacBook",
            percentage: 82,
            isCharging: false,
            kind: .mac,
            transport: "Internal"
        )

        XCTAssertEqual(
            CompactWeatherBatteryPresentation.title(
                weatherEnabled: true,
                weatherSnapshot: .empty,
                weatherStatusMessage: "WeatherKit 权限不可用",
                batteryEnabled: true,
                primaryBattery: battery,
                accessoryCount: 0
            ),
            "电量 82%"
        )
        XCTAssertEqual(
            CompactWeatherBatteryPresentation.symbolName(
                weatherEnabled: true,
                weatherSnapshot: .empty,
                batteryEnabled: true,
                primaryBattery: battery
            ),
            "laptopcomputer"
        )
    }

    func testCompactPresentationKeepsWeatherWhenWeatherHasContent() {
        let battery = DeviceBatterySnapshot(
            id: "internal-battery",
            name: "MacBook",
            percentage: 82,
            isCharging: false,
            kind: .mac,
            transport: "Internal"
        )
        let weather = WeatherSnapshot(
            symbolName: "sun.max.fill",
            conditionName: "晴朗",
            temperature: Measurement(value: 26, unit: UnitTemperature.celsius),
            apparentTemperature: nil,
            highTemperature: nil,
            lowTemperature: nil,
            humidity: nil,
            windSpeed: nil,
            uvIndex: nil,
            hourlyForecast: [],
            locationName: "当前位置"
        )

        XCTAssertEqual(
            CompactWeatherBatteryPresentation.title(
                weatherEnabled: true,
                weatherSnapshot: weather,
                weatherStatusMessage: "由 Apple Weather 提供",
                batteryEnabled: true,
                primaryBattery: battery,
                accessoryCount: 0
            ),
            "26° · 晴朗"
        )
        XCTAssertEqual(
            CompactWeatherBatteryPresentation.symbolName(
                weatherEnabled: true,
                weatherSnapshot: weather,
                batteryEnabled: true,
                primaryBattery: battery
            ),
            "sun.max.fill"
        )
    }

    func testOpenMeteoWeatherCodeMappingProducesPanelPresentation() {
        XCTAssertEqual(
            OpenMeteoWeatherCodeMapper.presentation(for: 0, isDay: true),
            OpenMeteoWeatherCodeMapper.Presentation(symbolName: "sun.max.fill", conditionName: "晴朗")
        )
        XCTAssertEqual(
            OpenMeteoWeatherCodeMapper.presentation(for: 0, isDay: false),
            OpenMeteoWeatherCodeMapper.Presentation(symbolName: "moon.stars.fill", conditionName: "晴朗")
        )
        XCTAssertEqual(
            OpenMeteoWeatherCodeMapper.presentation(for: 63, isDay: true),
            OpenMeteoWeatherCodeMapper.Presentation(symbolName: "cloud.rain.fill", conditionName: "下雨")
        )
    }

    func testWeatherLocationNameFormatterPrefersDistrictAndCity() {
        XCTAssertEqual(
            WeatherLocationNameFormatter.displayName(
                subLocality: "南山区",
                locality: "深圳市",
                administrativeArea: "广东省",
                country: "中国"
            ),
            "南山区 · 深圳市"
        )
        XCTAssertEqual(
            WeatherLocationNameFormatter.displayName(
                subLocality: nil,
                locality: "上海市",
                administrativeArea: "上海市",
                country: "中国"
            ),
            "上海市"
        )
        XCTAssertEqual(
            WeatherLocationNameFormatter.displayName(
                subLocality: nil,
                locality: nil,
                administrativeArea: nil,
                country: nil
            ),
            "当前位置"
        )
    }

    func testWeatherPanelPresentationShowsResolvedLocationWithCondition() {
        let weather = WeatherSnapshot(
            symbolName: "cloud.fill",
            conditionName: "阴天",
            temperature: Measurement(value: 25, unit: UnitTemperature.celsius),
            apparentTemperature: nil,
            highTemperature: nil,
            lowTemperature: nil,
            humidity: nil,
            windSpeed: nil,
            uvIndex: nil,
            hourlyForecast: [],
            locationName: "南山区 · 深圳市"
        )

        XCTAssertEqual(
            WeatherPanelPresentation.locationConditionText(for: weather),
            "南山区 · 深圳市 · 阴天"
        )
        XCTAssertEqual(
            WeatherPanelPresentation.locationConditionText(for: .empty),
            ""
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private final class FakeWeatherLocationManager: WeatherLocationManaging {
    var authorizationStatus: CLAuthorizationStatus
    var locationServicesEnabled = true
    weak var delegate: CLLocationManagerDelegate?
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers
    private(set) var requestAuthorizationCallCount = 0
    private(set) var requestLocationCallCount = 0

    init(authorizationStatus: CLAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        requestAuthorizationCallCount += 1
    }

    func requestLocation() {
        requestLocationCallCount += 1
    }
}
