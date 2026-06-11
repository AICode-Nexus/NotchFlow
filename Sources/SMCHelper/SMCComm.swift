import Foundation
import IOKit
import CSMCParamStruct

private func fourCharCode(_ c0: Character, _ c1: Character, _ c2: Character, _ c3: Character) -> UInt32 {
    let b0 = UInt32(c0.asciiValue!) << 24
    let b1 = UInt32(c1.asciiValue!) << 16
    let b2 = UInt32(c2.asciiValue!) << 8
    let b3 = UInt32(c3.asciiValue!)
    return b0 | b1 | b2 | b3
}

enum SMCComm {
    nonisolated(unsafe) private static var connect: io_connect_t = 0

    static func open() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { return false }

        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 1, &conn)
        IOObjectRelease(service)
        guard kr == kIOReturnSuccess, conn != 0 else { return false }

        connect = conn
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        input.data8 = UInt8(kSMCUserClientOpen)
        IOConnectCallStructMethod(connect, UInt32(kSMCHandleYPCEvent), &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        return true
    }

    static func close() {
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        input.data8 = UInt8(kSMCUserClientClose)
        IOConnectCallStructMethod(connect, UInt32(kSMCHandleYPCEvent), &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        IOServiceClose(connect)
        connect = 0
    }

    static func getKeyInfo(key: UInt32) -> SMCKeyInfoData? {
        var input = SMCParamStruct()
        input.key = key
        input.data8 = UInt8(kSMCGetKeyInfo)

        guard let output = callSMC(&input) else { return nil }
        return output.keyInfo
    }

    static func readKey(key: UInt32, dataSize: UInt32) -> [UInt8]? {
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = dataSize
        input.data8 = UInt8(kSMCReadKey)

        guard let output = callSMC(&input) else { return nil }
        return withUnsafePointer(to: output.bytes) { ptr in
            let raw = UnsafeRawPointer(ptr)
            return (0..<Int(dataSize)).map { raw.load(fromByteOffset: $0, as: UInt8.self) }
        }
    }

    static func writeKey(key: UInt32, bytes: [UInt8]) -> Bool {
        var input = SMCParamStruct()
        input.key = key
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.data8 = UInt8(kSMCWriteKey)
        withUnsafeMutablePointer(to: &input.bytes) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            for i in 0..<bytes.count {
                raw.storeBytes(of: bytes[i], toByteOffset: i, as: UInt8.self)
            }
        }

        let result = callSMC(&input)
        guard result != nil else { return false }

        let readBack = readKey(key: key, dataSize: UInt32(bytes.count))
        return readBack == bytes
    }

    static func keyExists(key: UInt32, expectedSize: UInt32, expectedType: UInt32) -> Bool {
        guard let info = getKeyInfo(key: key) else { return false }
        return info.dataSize == expectedSize && info.dataType == expectedType
    }

    private static func callSMC(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let kr = IOConnectCallStructMethod(
            connect,
            UInt32(kSMCHandleYPCEvent),
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard kr == kIOReturnSuccess, output.result == UInt8(kSMCSuccess) else {
            return nil
        }
        return output
    }

    static func makeKey(_ c0: Character, _ c1: Character, _ c2: Character, _ c3: Character) -> UInt32 {
        fourCharCode(c0, c1, c2, c3)
    }
}
