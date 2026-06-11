import Foundation

enum SMCPower {
    private struct KeyControl {
        let key: UInt32
        let dataSize: UInt32
        let dataType: UInt32
        let onBytes: [UInt8]
        let offBytes: [UInt8]
    }

    private static let typeUI32 = SMCComm.makeKey("u", "i", "3", "2")
    private static let typeHex = SMCComm.makeKey("h", "e", "x", "_")

    private static let chargeKeys: [KeyControl] = [
        KeyControl(
            key: SMCComm.makeKey("C", "H", "T", "E"),
            dataSize: 4,
            dataType: typeUI32,
            onBytes: [0x00, 0x00, 0x00, 0x00],
            offBytes: [0x01, 0x00, 0x00, 0x00]
        ),
        KeyControl(
            key: SMCComm.makeKey("C", "H", "0", "C"),
            dataSize: 1,
            dataType: typeHex,
            onBytes: [0x00],
            offBytes: [0x01]
        ),
    ]

    nonisolated(unsafe) private static var activeChargeKeyIndex: Int?

    static func supported() -> Bool {
        for (index, kc) in chargeKeys.enumerated() {
            if SMCComm.keyExists(key: kc.key, expectedSize: kc.dataSize, expectedType: kc.dataType) {
                activeChargeKeyIndex = index
                return true
            }
        }
        return false
    }

    static func enableCharging() -> Bool {
        guard let index = activeChargeKeyIndex else { return false }
        let kc = chargeKeys[index]
        return SMCComm.writeKey(key: kc.key, bytes: kc.onBytes)
    }

    static func disableCharging() -> Bool {
        guard let index = activeChargeKeyIndex else { return false }
        let kc = chargeKeys[index]
        return SMCComm.writeKey(key: kc.key, bytes: kc.offBytes)
    }

    static func isChargingDisabled() -> Bool {
        guard let index = activeChargeKeyIndex else { return false }
        let kc = chargeKeys[index]
        guard let value = SMCComm.readKey(key: kc.key, dataSize: kc.dataSize) else { return false }
        return value != kc.onBytes
    }
}
