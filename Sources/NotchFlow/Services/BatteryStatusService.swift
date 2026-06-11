import AppKit
import Foundation
import IOKit.hid
import IOKit.ps

@MainActor
final class BatteryStatusService: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot.empty
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "等待读取设备电量"

    private let refreshInterval: TimeInterval = 120
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastRefreshDate: Date?

    func start() {
        guard refreshTimer == nil else {
            return
        }

        installObservers()
        scheduleRefreshTimer()
        refresh(force: true)
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()

        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func refresh(force: Bool = false) {
        if !force,
           let lastRefreshDate,
           Date().timeIntervalSince(lastRefreshDate) < 30,
           snapshot.hasContent
        {
            return
        }

        refreshTask?.cancel()
        isLoading = true
        statusMessage = snapshot.hasContent ? "更新设备电量..." : "读取设备电量..."

        refreshTask = Task.detached(priority: .utility) { [currentSnapshot = snapshot] in
            let collection = Self.collectSnapshot(previousSnapshot: currentSnapshot)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self.snapshot = collection.snapshot
                self.statusMessage = collection.statusMessage
                self.isLoading = false
                self.lastRefreshDate = collection.snapshot.updatedAt
            }
        }
    }

    func refreshIfNeeded(maximumAge: TimeInterval = 90) {
        guard let lastRefreshDate else {
            refresh(force: true)
            return
        }

        guard Date().timeIntervalSince(lastRefreshDate) >= maximumAge else {
            return
        }

        refresh(force: true)
    }

    private func installObservers() {
        guard observers.isEmpty else {
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        observers = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
        ].map { name in
            notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh(force: true)
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
}

private extension BatteryStatusService {
    struct BatteryCollection {
        let snapshot: BatterySnapshot
        let statusMessage: String
    }

    struct BluetoothInventory {
        var batterySnapshots: [DeviceBatterySnapshot]
        var disconnectedNames: Set<String>
    }

    nonisolated static let bluetoothTransports = Set([
        "bluetooth",
        "bluetoothlowenergy",
        "bt-aacp",
    ])

    nonisolated static func collectSnapshot(previousSnapshot: BatterySnapshot) -> BatteryCollection {
        let internalBattery = internalBatterySnapshot()
        let hidAccessories = hidAccessorySnapshots()
        let bluetoothInventory = bluetoothInventory()
        let accessories = mergeAccessories(primary: hidAccessories, fallback: bluetoothInventory.batterySnapshots)

        let snapshot = BatterySnapshot(
            internalBattery: internalBattery,
            accessories: accessories,
            disconnectedAccessories: bluetoothInventory.disconnectedNames.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            },
            updatedAt: Date()
        )

        return BatteryCollection(
            snapshot: snapshot,
            statusMessage: statusMessage(for: snapshot, previousSnapshot: previousSnapshot)
        )
    }

    nonisolated static func internalBatterySnapshot() -> DeviceBatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for powerSource in list {
            guard let description = IOPSGetPowerSourceDescription(info, powerSource)?
                .takeUnretainedValue() as? [String: Any]
            else {
                continue
            }

            let powerSourceType = description[kIOPSTypeKey] as? String
            let transportType = description[kIOPSTransportTypeKey] as? String

            guard powerSourceType == kIOPSInternalBatteryType
                || (powerSourceType == nil && transportType == "Internal")
            else {
                continue
            }

            let name = (description[kIOPSNameKey] as? String)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "MacBook"
            let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            let isCharged = (description[kIOPSIsChargedKey] as? Bool) ?? false

            if let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
               let maxCapacity = description[kIOPSMaxCapacityKey] as? Int,
               maxCapacity > 0
            {
                let percentage = clampPercentage(
                    Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
                )

                return DeviceBatterySnapshot(
                    id: "internal-battery",
                    name: name,
                    percentage: percentage,
                    isCharging: isCharging && !isCharged,
                    kind: .mac,
                    transport: "Internal"
                )
            }
        }

        return nil
    }

    nonisolated static func hidAccessorySnapshots() -> [DeviceBatterySnapshot] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return []
        }
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        return devices.compactMap { hidAccessorySnapshot(for: $0) }
    }

    nonisolated static func hidAccessorySnapshot(for device: IOHIDDevice) -> DeviceBatterySnapshot? {
        guard let transport = stringProperty(for: device, key: kIOHIDTransportKey),
              bluetoothTransports.contains(transport.lowercased())
        else {
            return nil
        }

        if boolProperty(for: device, key: kIOHIDBuiltInKey) == true {
            return nil
        }

        guard let percentage = hidBatteryPercentage(for: device) else {
            return nil
        }

        let rawName = stringProperty(for: device, key: kIOHIDProductKey) ?? "蓝牙设备"
        let name = cleanedAccessoryName(rawName)
        let minorType = stringProperty(for: device, key: "DeviceMinorType")
        let identifier = hidDeviceIdentifier(for: device, fallbackName: name)

        return DeviceBatterySnapshot(
            id: identifier,
            name: name,
            percentage: percentage,
            isCharging: hidChargingState(for: device),
            kind: .infer(name: name, minorType: minorType),
            transport: transport
        )
    }

    nonisolated static func hidBatteryPercentage(for device: IOHIDDevice) -> Int? {
        for key in [
            "BatteryPercent",
            "BatteryLevel",
            "BatteryPercentComposed",
        ] {
            if let value = numberProperty(for: device, key: key) {
                return clampPercentage(value)
            }
        }

        let elements = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
        var candidates: [Int] = []

        for element in elements {
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            guard isBatteryElement(usagePage: usagePage, usage: usage) else {
                continue
            }

            guard let value = hidValue(for: device, element: element)
            else {
                continue
            }

            let rawValue = Int(IOHIDValueGetIntegerValue(value))
            let logicalMin = Int(IOHIDElementGetLogicalMin(element))
            let logicalMax = Int(IOHIDElementGetLogicalMax(element))

            if let normalized = normalizeBatteryValue(rawValue, logicalMin: logicalMin, logicalMax: logicalMax) {
                candidates.append(normalized)
            }
        }

        return candidates.first
    }

    nonisolated static func hidChargingState(for device: IOHIDDevice) -> Bool {
        if let directValue = boolProperty(for: device, key: "BatteryCharging") {
            return directValue
        }

        let elements = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []

        for element in elements {
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            guard usagePage == UInt32(kHIDPage_BatterySystem),
                  usage == UInt32(kHIDUsage_BS_Charging)
            else {
                continue
            }

            guard let value = hidValue(for: device, element: element)
            else {
                continue
            }

            return IOHIDValueGetIntegerValue(value) != 0
        }

        return false
    }

    nonisolated static func isBatteryElement(usagePage: UInt32, usage: UInt32) -> Bool {
        if usagePage == UInt32(kHIDPage_GenericDeviceControls),
           usage == UInt32(kHIDUsage_GenDevControls_BatteryStrength)
        {
            return true
        }

        if usagePage == UInt32(kHIDPage_Digitizer),
           usage == UInt32(kHIDUsage_Dig_BatteryStrength)
        {
            return true
        }

        if usagePage == UInt32(kHIDPage_BatterySystem) {
            return usage == UInt32(kHIDUsage_BS_RelativeStateOfCharge)
                || usage == UInt32(kHIDUsage_BS_AbsoluteStateOfCharge)
        }

        return false
    }

    nonisolated static func normalizeBatteryValue(_ rawValue: Int, logicalMin: Int, logicalMax: Int) -> Int? {
        if (0 ... 100).contains(rawValue) {
            return rawValue
        }

        guard logicalMax > logicalMin, rawValue >= logicalMin else {
            return nil
        }

        let percentage = ((Double(rawValue - logicalMin) / Double(logicalMax - logicalMin)) * 100).rounded()
        return clampPercentage(Int(percentage))
    }

    nonisolated static func hidValue(for device: IOHIDDevice, element: IOHIDElement) -> IOHIDValue? {
        let pointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
        defer {
            pointer.deallocate()
        }

        guard IOHIDDeviceGetValue(device, element, pointer) == kIOReturnSuccess else {
            return nil
        }

        return pointer.pointee.takeUnretainedValue()
    }

    nonisolated static func stringProperty(for device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }

        if let stringValue = value as? String {
            return stringValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        }

        return nil
    }

    nonisolated static func numberProperty(for device: IOHIDDevice, key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }

        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }

        if let stringValue = value as? String {
            return parsePercentageValue(stringValue)
        }

        return nil
    }

    nonisolated static func boolProperty(for device: IOHIDDevice, key: String) -> Bool? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        if let stringValue = value as? String {
            return parseBooleanValue(stringValue)
        }

        return nil
    }

    nonisolated static func hidDeviceIdentifier(for device: IOHIDDevice, fallbackName: String) -> String {
        for key in [
            kIOHIDPhysicalDeviceUniqueIDKey,
            kIOHIDSerialNumberKey,
            kIOHIDUniqueIDKey,
        ] {
            if let value = stringProperty(for: device, key: key), !value.isEmpty {
                return "hid-\(value)"
            }
        }

        let vendorID = stringProperty(for: device, key: "VendorID") ?? "0"
        let productID = stringProperty(for: device, key: "ProductID") ?? "0"
        return "hid-\(vendorID)-\(productID)-\(normalizedToken(fallbackName))"
    }

    nonisolated static func bluetoothInventory() -> BluetoothInventory {
        guard let data = runCommand(
            launchPath: "/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-json"]
        ) else {
            return BluetoothInventory(batterySnapshots: [], disconnectedNames: [])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [Any]
        else {
            return BluetoothInventory(batterySnapshots: [], disconnectedNames: [])
        }

        var inventory = BluetoothInventory(batterySnapshots: [], disconnectedNames: [])
        for section in sections {
            collectBluetoothDevices(
                from: section,
                inheritedName: nil,
                connectivityHint: nil,
                inventory: &inventory
            )
        }

        return inventory
    }

    nonisolated static func collectBluetoothDevices(
        from node: Any,
        inheritedName: String?,
        connectivityHint: Bool?,
        inventory: inout BluetoothInventory
    ) {
        if let array = node as? [Any] {
            for item in array {
                collectBluetoothDevices(
                    from: item,
                    inheritedName: inheritedName,
                    connectivityHint: connectivityHint,
                    inventory: &inventory
                )
            }
            return
        }

        guard let dictionary = node as? [String: Any] else {
            return
        }

        if dictionary.count == 1,
           let (name, value) = dictionary.first,
           let nested = value as? [String: Any]
        {
            collectBluetoothDevices(
                from: nested,
                inheritedName: name,
                connectivityHint: connectivityHint,
                inventory: &inventory
            )
            return
        }

        if isBluetoothDevicePayload(dictionary),
           connectivityHint == false,
           let inheritedName
        {
            inventory.disconnectedNames.insert(cleanedAccessoryName(inheritedName))
        }

        if isBluetoothDevicePayload(dictionary),
           let snapshot = bluetoothAccessorySnapshot(
               name: inheritedName,
               payload: dictionary,
               connectivityHint: connectivityHint
           )
        {
            inventory.batterySnapshots.append(snapshot)
        }

        for (key, value) in dictionary {
            let nextConnectivityHint: Bool?
            switch key {
            case "device_connected":
                nextConnectivityHint = true
            case "device_not_connected":
                nextConnectivityHint = false
            default:
                nextConnectivityHint = connectivityHint
            }

            collectBluetoothDevices(
                from: value,
                inheritedName: key.hasPrefix("device_") ? inheritedName : key,
                connectivityHint: nextConnectivityHint,
                inventory: &inventory
            )
        }
    }

    nonisolated static func isBluetoothDevicePayload(_ payload: [String: Any]) -> Bool {
        payload.keys.contains(where: { $0.hasPrefix("device_") })
    }

    nonisolated static func bluetoothAccessorySnapshot(
        name: String?,
        payload: [String: Any],
        connectivityHint: Bool?
    ) -> DeviceBatterySnapshot? {
        if connectivityHint == false {
            return nil
        }

        if let connectedValue = payload["device_connected"] as? String,
           parseBooleanValue(connectedValue) == false
        {
            return nil
        }

        guard let percentage = bluetoothBatteryPercentage(from: payload) else {
            return nil
        }

        let rawName = name ?? (payload["device_name"] as? String) ?? "蓝牙设备"
        let cleanedName = cleanedAccessoryName(rawName)
        let minorType = payload["device_minorType"] as? String
        let address = payload["device_address"] as? String
        let productID = payload["device_productID"] as? String ?? "0"
        let identifier = address.map { "bt-\($0)" } ?? "bt-\(productID)-\(normalizedToken(cleanedName))"

        return DeviceBatterySnapshot(
            id: identifier,
            name: cleanedName,
            percentage: percentage,
            isCharging: bluetoothChargingState(from: payload),
            kind: .infer(name: cleanedName, minorType: minorType),
            transport: "Bluetooth"
        )
    }

    nonisolated static func bluetoothBatteryPercentage(from payload: [String: Any]) -> Int? {
        var primaryValues: [Int] = []
        var componentValues: [Int] = []

        for (key, value) in payload {
            let loweredKey = key.lowercased()
            guard loweredKey.contains("battery") else {
                continue
            }

            guard let percentage = parsePercentageValue(value) else {
                continue
            }

            if loweredKey.contains("left") || loweredKey.contains("right") || loweredKey.contains("case") {
                componentValues.append(percentage)
            } else {
                primaryValues.append(percentage)
            }
        }

        if !primaryValues.isEmpty {
            return clampPercentage(Int((Double(primaryValues.reduce(0, +)) / Double(primaryValues.count)).rounded()))
        }

        if !componentValues.isEmpty {
            return clampPercentage(Int((Double(componentValues.reduce(0, +)) / Double(componentValues.count)).rounded()))
        }

        return nil
    }

    nonisolated static func bluetoothChargingState(from payload: [String: Any]) -> Bool {
        for (key, value) in payload {
            let loweredKey = key.lowercased()
            guard loweredKey.contains("charging") || loweredKey.contains("charge") else {
                continue
            }

            if let stringValue = value as? String,
               let boolValue = parseBooleanValue(stringValue)
            {
                return boolValue
            }

            if let numberValue = value as? NSNumber {
                return numberValue.boolValue
            }
        }

        return false
    }

    nonisolated static func mergeAccessories(primary: [DeviceBatterySnapshot], fallback: [DeviceBatterySnapshot]) -> [DeviceBatterySnapshot] {
        var merged: [String: DeviceBatterySnapshot] = [:]

        for accessory in fallback {
            merged[dedupeKey(for: accessory)] = accessory
        }

        for accessory in primary {
            let key = dedupeKey(for: accessory)
            if let existing = merged[key] {
                merged[key] = preferredAccessory(primary: accessory, fallback: existing)
            } else {
                merged[key] = accessory
            }
        }

        return merged.values.sorted(by: accessorySort)
    }

    nonisolated static func preferredAccessory(primary: DeviceBatterySnapshot, fallback: DeviceBatterySnapshot) -> DeviceBatterySnapshot {
        if !primary.name.isEmpty, primary.name != "蓝牙设备" {
            return primary
        }

        return DeviceBatterySnapshot(
            id: primary.id,
            name: fallback.name,
            percentage: primary.percentage,
            isCharging: primary.isCharging || fallback.isCharging,
            kind: primary.kind == .generic ? fallback.kind : primary.kind,
            transport: primary.transport ?? fallback.transport
        )
    }

    nonisolated static func dedupeKey(for accessory: DeviceBatterySnapshot) -> String {
        if accessory.id.hasPrefix("bt-") || accessory.id.hasPrefix("hid-") {
            return accessory.id.lowercased()
        }

        return normalizedToken(accessory.name)
    }

    nonisolated static func accessorySort(lhs: DeviceBatterySnapshot, rhs: DeviceBatterySnapshot) -> Bool {
        if lhs.kind.sortPriority != rhs.kind.sortPriority {
            return lhs.kind.sortPriority < rhs.kind.sortPriority
        }

        if lhs.percentage != rhs.percentage {
            return lhs.percentage > rhs.percentage
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    nonisolated static func cleanedAccessoryName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "蓝牙设备"
        }

        return trimmed
            .replacingOccurrences(of: "的Magic Trackpad", with: " 触控板")
            .replacingOccurrences(of: "的键盘", with: " 键盘")
            .replacingOccurrences(of: "的触控板", with: " 触控板")
    }

    nonisolated static func normalizedToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
    }

    nonisolated static func clampPercentage(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }

    nonisolated static func parsePercentageValue(_ value: Any) -> Int? {
        if let numberValue = value as? NSNumber {
            return clampPercentage(numberValue.intValue)
        }

        if let stringValue = value as? String {
            return parsePercentageValue(stringValue)
        }

        return nil
    }

    nonisolated static func parsePercentageValue(_ value: String) -> Int? {
        let digits = value.filter(\.isNumber)
        guard let parsed = Int(digits) else {
            return nil
        }

        return clampPercentage(parsed)
    }

    nonisolated static func parseBooleanValue(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "yes", "true", "1", "attrib_on", "connected", "charging":
            return true
        case "no", "false", "0", "attrib_off", "disconnected":
            return false
        default:
            return nil
        }
    }

    nonisolated static func runCommand(launchPath: String, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        return data
    }

    nonisolated static func statusMessage(for snapshot: BatterySnapshot, previousSnapshot: BatterySnapshot) -> String {
        if let internalBattery = snapshot.internalBattery {
            if snapshot.accessories.isEmpty {
                return internalBattery.isCharging
                    ? "Mac 正在充电，当前 \(internalBattery.percentageText)"
                    : "Mac 当前电量 \(internalBattery.percentageText)"
            }

            return "Mac \(internalBattery.percentageText)，已连接 \(snapshot.accessoryCount) 个外设"
        }

        if !snapshot.accessories.isEmpty {
            return "已读取 \(snapshot.accessoryCount) 个蓝牙外设电量"
        }

        if previousSnapshot.hasContent {
            return "暂时没读到设备电量"
        }

        return "暂时没读到设备电量"
    }
}
