import Foundation

struct DeviceBatterySnapshot: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case mac
        case keyboard
        case trackpad
        case mouse
        case headphones
        case controller
        case stylus
        case generic

        var symbolName: String {
            switch self {
            case .mac:
                return "laptopcomputer"
            case .keyboard:
                return "keyboard"
            case .trackpad:
                return "cursorarrow.click"
            case .mouse:
                return "magicmouse"
            case .headphones:
                return "headphones"
            case .controller:
                return "gamecontroller"
            case .stylus:
                return "pencil"
            case .generic:
                return "battery.100"
            }
        }

        var sortPriority: Int {
            switch self {
            case .trackpad:
                return 0
            case .keyboard:
                return 1
            case .mouse:
                return 2
            case .headphones:
                return 3
            case .controller:
                return 4
            case .stylus:
                return 5
            case .generic:
                return 6
            case .mac:
                return 7
            }
        }

        static func infer(name: String, minorType: String? = nil) -> Self {
            let source = "\(name) \(minorType ?? "")".lowercased()

            if source.contains("macbook") || source.contains("laptop") {
                return .mac
            }

            if source.contains("trackpad") || source.contains("触控板") {
                return .trackpad
            }

            if source.contains("keyboard") || source.contains("键盘") {
                return .keyboard
            }

            if source.contains("mouse") || source.contains("鼠标") {
                return .mouse
            }

            if source.contains("headphone")
                || source.contains("airpods")
                || source.contains("耳机")
                || source.contains("buds")
            {
                return .headphones
            }

            if source.contains("controller") || source.contains("gamepad") {
                return .controller
            }

            if source.contains("pencil") || source.contains("pen") {
                return .stylus
            }

            return .generic
        }
    }

    let id: String
    let name: String
    let percentage: Int
    let isCharging: Bool
    let kind: Kind
    let transport: String?

    var percentageText: String {
        "\(percentage)%"
    }
}

struct BatterySnapshot: Equatable {
    let internalBattery: DeviceBatterySnapshot?
    let accessories: [DeviceBatterySnapshot]
    let disconnectedAccessories: [String]
    let updatedAt: Date?

    var hasContent: Bool {
        internalBattery != nil || !accessories.isEmpty
    }

    var accessoryCount: Int {
        accessories.count
    }

    var disconnectedAccessoryCount: Int {
        disconnectedAccessories.count
    }

    var disconnectedAccessoryHint: String? {
        guard !disconnectedAccessories.isEmpty else {
            return nil
        }

        if disconnectedAccessories.count <= 2 {
            return disconnectedAccessories.joined(separator: "、")
        }

        let preview = disconnectedAccessories.prefix(2).joined(separator: "、")
        return "\(preview) 等 \(disconnectedAccessories.count) 个"
    }

    static let empty = BatterySnapshot(
        internalBattery: nil,
        accessories: [],
        disconnectedAccessories: [],
        updatedAt: nil
    )
}
