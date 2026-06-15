import Foundation

enum CompactWeatherBatteryPresentation {
    static func symbolName(
        weatherEnabled: Bool,
        weatherSnapshot: WeatherSnapshot,
        batteryEnabled: Bool,
        primaryBattery: DeviceBatterySnapshot?
    ) -> String? {
        if weatherEnabled, weatherSnapshot.hasContent {
            return weatherSnapshot.symbolName
        }

        if batteryEnabled, let primaryBattery {
            return primaryBattery.kind.symbolName
        }

        if weatherEnabled {
            return weatherSnapshot.symbolName
        }

        return nil
    }

    static func title(
        weatherEnabled: Bool,
        weatherSnapshot: WeatherSnapshot,
        weatherStatusMessage: String,
        batteryEnabled: Bool,
        primaryBattery: DeviceBatterySnapshot?,
        accessoryCount: Int
    ) -> String? {
        if weatherEnabled, weatherSnapshot.hasContent {
            return "\(formattedTemperature(weatherSnapshot.temperature)) · \(weatherSnapshot.conditionName)"
        }

        if batteryEnabled, let primaryBattery {
            if accessoryCount > 0 {
                return "\(primaryBattery.percentageText) · \(accessoryCount) 个外设"
            }

            return primaryBattery.isCharging
                ? "正在充电 · \(primaryBattery.percentageText)"
                : "电量 \(primaryBattery.percentageText)"
        }

        if weatherEnabled {
            return weatherStatusMessage
        }

        return nil
    }

    private static func formattedTemperature(_ temperature: Measurement<UnitTemperature>?) -> String {
        guard let temperature else {
            return "--"
        }

        let measurement = temperature.converted(to: .celsius).value.rounded()
        return "\(Int(measurement))°"
    }
}

enum WeatherPanelPresentation {
    static func locationConditionText(for snapshot: WeatherSnapshot) -> String {
        guard snapshot.hasContent else {
            return ""
        }

        let locationName = cleaned(snapshot.locationName)
        let conditionName = cleaned(snapshot.conditionName)

        guard let locationName, locationName != "当前位置" else {
            return conditionName ?? ""
        }

        guard let conditionName else {
            return locationName
        }

        return "\(locationName) · \(conditionName)"
    }

    private static func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
