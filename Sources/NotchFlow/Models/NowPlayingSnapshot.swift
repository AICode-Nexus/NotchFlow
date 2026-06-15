import AppKit
import Foundation
import WeatherKit

struct NowPlayingSnapshot: Equatable {
    let title: String
    let artist: String
    let album: String
    let sourceApp: String
    let isPlaying: Bool
    let artworkData: Data?

    var hasContent: Bool {
        !title.isEmpty
    }

    var shouldDisplay: Bool {
        isPlaying && hasContent
    }

    var subtitle: String {
        let primary = artist.isEmpty ? "Waiting for media" : artist
        guard !album.isEmpty else {
            return primary
        }

        return "\(primary) - \(album)"
    }

    var artworkImage: NSImage? {
        guard let artworkData else {
            return nil
        }

        return NSImage(data: artworkData)
    }

    static let empty = NowPlayingSnapshot(
        title: "",
        artist: "",
        album: "",
        sourceApp: "",
        isPlaying: false,
        artworkData: nil
    )
}

struct WeatherSnapshot: Equatable {
    let symbolName: String
    let conditionName: String
    let temperature: Measurement<UnitTemperature>?
    let apparentTemperature: Measurement<UnitTemperature>?
    let highTemperature: Measurement<UnitTemperature>?
    let lowTemperature: Measurement<UnitTemperature>?
    let humidity: Double?
    let windSpeed: Measurement<UnitSpeed>?
    let uvIndex: Int?
    let hourlyForecast: [HourlyWeatherSnapshot]
    let locationName: String

    var hasContent: Bool {
        temperature != nil
    }

    static let empty = WeatherSnapshot(
        symbolName: "cloud.sun.fill",
        conditionName: "",
        temperature: nil,
        apparentTemperature: nil,
        highTemperature: nil,
        lowTemperature: nil,
        humidity: nil,
        windSpeed: nil,
        uvIndex: nil,
        hourlyForecast: [],
        locationName: "当前位置"
    )
}

struct HourlyWeatherSnapshot: Equatable, Identifiable {
    let date: Date
    let symbolName: String
    let temperature: Measurement<UnitTemperature>

    var id: Date {
        date
    }
}

enum WeatherLocationNameFormatter {
    static func displayName(
        subLocality: String?,
        locality: String?,
        administrativeArea: String?,
        country: String?
    ) -> String {
        let localParts = [
            cleaned(subLocality),
            cleaned(locality),
            cleaned(administrativeArea),
        ]
        var uniqueParts: [String] = []

        for part in localParts.compactMap({ $0 }) where !uniqueParts.contains(part) {
            uniqueParts.append(part)
        }

        switch uniqueParts.count {
        case 0:
            return cleaned(country) ?? "当前位置"
        case 1:
            return uniqueParts[0]
        default:
            return uniqueParts.prefix(2).joined(separator: " · ")
        }
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct WeatherAttributionSnapshot: Equatable {
    let serviceName: String
    let legalPageURL: URL?
    let combinedMarkDarkURL: URL?
    let combinedMarkLightURL: URL?

    var hasContent: Bool {
        legalPageURL != nil || combinedMarkDarkURL != nil || combinedMarkLightURL != nil
    }

    static let empty = WeatherAttributionSnapshot(
        serviceName: "Apple Weather",
        legalPageURL: nil,
        combinedMarkDarkURL: nil,
        combinedMarkLightURL: nil
    )
}

extension WeatherSnapshot {
    init(weather: WeatherKit.Weather) {
        let today = weather.dailyForecast.first
        let hours = Array(weather.hourlyForecast.prefix(4)).map {
            HourlyWeatherSnapshot(
                date: $0.date,
                symbolName: $0.symbolName,
                temperature: $0.temperature
            )
        }

        self.init(
            symbolName: weather.currentWeather.symbolName,
            conditionName: weather.currentWeather.condition.localizedDisplayName,
            temperature: weather.currentWeather.temperature,
            apparentTemperature: weather.currentWeather.apparentTemperature,
            highTemperature: today?.highTemperature,
            lowTemperature: today?.lowTemperature,
            humidity: weather.currentWeather.humidity,
            windSpeed: weather.currentWeather.wind.speed,
            uvIndex: weather.currentWeather.uvIndex.value,
            hourlyForecast: hours,
            locationName: "当前位置"
        )
    }

    func withLocationName(_ locationName: String?) -> WeatherSnapshot {
        WeatherSnapshot(
            symbolName: symbolName,
            conditionName: conditionName,
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            highTemperature: highTemperature,
            lowTemperature: lowTemperature,
            humidity: humidity,
            windSpeed: windSpeed,
            uvIndex: uvIndex,
            hourlyForecast: hourlyForecast,
            locationName: WeatherLocationNameFormatter.displayName(
                subLocality: locationName,
                locality: nil,
                administrativeArea: nil,
                country: nil
            )
        )
    }
}

extension WeatherAttributionSnapshot {
    init(attribution: WeatherKit.WeatherAttribution) {
        self.init(
            serviceName: attribution.serviceName,
            legalPageURL: attribution.legalPageURL,
            combinedMarkDarkURL: attribution.combinedMarkDarkURL,
            combinedMarkLightURL: attribution.combinedMarkLightURL
        )
    }
}

private extension WeatherCondition {
    var localizedDisplayName: String {
        switch self {
        case .blizzard:
            "暴风雪"
        case .blowingDust:
            "扬沙"
        case .blowingSnow:
            "风雪"
        case .breezy:
            "微风"
        case .clear:
            "晴朗"
        case .cloudy:
            "阴天"
        case .drizzle:
            "毛毛雨"
        case .flurries:
            "阵雪"
        case .foggy:
            "有雾"
        case .freezingDrizzle:
            "冻毛雨"
        case .freezingRain:
            "冻雨"
        case .frigid:
            "严寒"
        case .hail:
            "冰雹"
        case .haze:
            "霾"
        case .heavyRain:
            "大雨"
        case .heavySnow:
            "大雪"
        case .hot:
            "炎热"
        case .hurricane:
            "飓风"
        case .isolatedThunderstorms:
            "局部雷暴"
        case .mostlyClear:
            "大致晴朗"
        case .mostlyCloudy:
            "大致多云"
        case .partlyCloudy:
            "局部多云"
        case .rain:
            "下雨"
        case .scatteredThunderstorms:
            "零星雷暴"
        case .sleet:
            "雨夹雪"
        case .smoky:
            "烟霾"
        case .snow:
            "下雪"
        case .strongStorms:
            "强对流"
        case .sunFlurries:
            "晴间阵雪"
        case .sunShowers:
            "晴间阵雨"
        case .thunderstorms:
            "雷暴"
        case .tropicalStorm:
            "热带风暴"
        case .windy:
            "大风"
        case .wintryMix:
            "雨雪混合"
        @unknown default:
            description
        }
    }
}
