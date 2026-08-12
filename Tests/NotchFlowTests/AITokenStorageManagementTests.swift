import Foundation
@testable import NotchFlow
import XCTest

final class AITokenStorageManagementTests: XCTestCase {
    @MainActor
    func testSettingsViewDirectlyObservesRetentionAndUsageState() {
        let view = SettingsView(model: .shared)
        let observedProperties = Set(Mirror(reflecting: view).children.compactMap(\.label))

        XCTAssertTrue(observedProperties.contains("_settings"))
        XCTAssertTrue(observedProperties.contains("_aiTokenUsage"))
    }

    @MainActor
    func testRetentionChangeRecalculatesPreviewUsingNewPreset() async throws {
        let defaults = UserDefaults(suiteName: "NotchFlowTests-\(UUID().uuidString)")!
        defaults.set(false, forKey: "AITokenUsageEnabled")
        defaults.set(LogRetentionPreset.thirtyDays.rawValue, forKey: "LogRetentionPreset")
        let settings = AppSettings(defaults: defaults)
        let storage = RetentionRecordingStorageManager()
        let service = AITokenUsageService(
            settings: settings,
            readers: [EmptyAITokenUsageReader()],
            storageManager: storage,
            calendar: utcCalendar
        )
        defer { service.stop() }

        service.start()
        try await waitUntil { storage.retentionDays.last == 30 }

        settings.logRetentionPreset = .fourteenDays
        try await waitUntil { storage.retentionDays.last == 14 }

        XCTAssertEqual(storage.retentionDays.last, 14)
    }

    func testSnapshotCountsCleanableFilesAndPreviewsExpiredFiles() throws {
        let fixture = try TemporaryStorageFixture()
        let codex = try fixture.makeDirectory("codex")
        let claude = try fixture.makeDirectory("claude")
        let now = date("2026-08-12T06:00:00Z")
        let oldDate = date("2026-07-01T00:00:00Z")
        let recentDate = date("2026-08-10T00:00:00Z")

        try fixture.writeFile("old.jsonl", bytes: 11, in: codex, modificationDate: oldDate)
        try fixture.writeFile("recent.jsonl", bytes: 13, in: codex, modificationDate: recentDate)
        try fixture.writeFile("capture.response.json", bytes: 17, in: claude, modificationDate: oldDate)
        try fixture.writeFile("ignored.json", bytes: 19, in: claude, modificationDate: oldDate)

        let manager = AITokenUsageStorageManager(
            directories: [
                AITokenUsageStorageDirectory(sourceID: .codex, url: codex),
                AITokenUsageStorageDirectory(sourceID: .claude, url: claude),
            ]
        )
        let snapshot = manager.snapshot(
            retentionDays: 30,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(snapshot.totalBytes, 41)
        XCTAssertEqual(snapshot.cleanupPreview.fileCount, 2)
        XCTAssertEqual(snapshot.cleanupPreview.bytes, 28)
        XCTAssertEqual(snapshot.sourceDirectories[.codex]?.map(\.sizeBytes), [24])
        XCTAssertEqual(snapshot.sourceDirectories[.claude]?.map(\.sizeBytes), [17])
    }

    func testCleanupDeletesOnlyExpiredUsageLogsAndReportsFailures() throws {
        let fixture = try TemporaryStorageFixture()
        let root = try fixture.makeDirectory("usage")
        let now = date("2026-08-12T06:00:00Z")
        let oldDate = date("2026-07-01T00:00:00Z")
        let recentDate = date("2026-08-10T00:00:00Z")
        let removable = try fixture.writeFile("removable.jsonl", bytes: 11, in: root, modificationDate: oldDate)
        let failing = try fixture.writeFile("failing.jsonl", bytes: 13, in: root, modificationDate: oldDate)
        let recent = try fixture.writeFile("recent.jsonl", bytes: 17, in: root, modificationDate: recentDate)
        let ignored = try fixture.writeFile("ignored.txt", bytes: 19, in: root, modificationDate: oldDate)

        let manager = AITokenUsageStorageManager(
            directories: [AITokenUsageStorageDirectory(sourceID: .codex, url: root)],
            removeItem: { url in
                if url.standardizedFileURL.path == failing.standardizedFileURL.path {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.removeItem(at: url)
            }
        )
        let result = manager.clearExpiredLogs(
            retentionDays: 30,
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(result.deletedFileCount, 1)
        XCTAssertEqual(result.freedBytes, 11)
        XCTAssertEqual(result.failedFileCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: removable.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failing.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ignored.path))
    }

    @MainActor
    func testRefreshRecalculatesStorageAfterLogsGrow() async throws {
        let fixture = try TemporaryStorageFixture()
        let root = try fixture.makeDirectory("usage")
        try fixture.writeFile("first.jsonl", bytes: 11, in: root, modificationDate: Date())
        let defaults = UserDefaults(suiteName: "NotchFlowTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "AITokenUsageEnabled")
        let settings = AppSettings(defaults: defaults)
        let service = AITokenUsageService(
            settings: settings,
            readers: [EmptyAITokenUsageReader()],
            storageManager: AITokenUsageStorageManager(
                directories: [AITokenUsageStorageDirectory(sourceID: .codex, url: root)]
            ),
            calendar: utcCalendar
        )
        defer { service.stop() }

        service.start()
        try await waitUntil { !service.isRefreshing && service.diskUsageBytes == 11 }
        try fixture.writeFile("second.jsonl", bytes: 13, in: root, modificationDate: Date())

        service.refresh()
        try await waitUntil { !service.isRefreshing && service.diskUsageBytes == 24 }

        XCTAssertEqual(service.diskUsageBytes, 24)
    }

    @MainActor
    func testCleanupWaitsForRunningUsageRefreshAndReportsFailures() async throws {
        let defaults = UserDefaults(suiteName: "NotchFlowTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "AITokenUsageEnabled")
        let settings = AppSettings(defaults: defaults)
        let reader = CancellationAwareAITokenUsageReader()
        let storage = RecordingAITokenUsageStorageManager(reader: reader)
        let service = AITokenUsageService(
            settings: settings,
            readers: [reader],
            storageManager: storage,
            calendar: utcCalendar
        )
        defer { service.stop() }

        service.start()
        try await waitUntil { reader.hasStarted }
        service.clearOldLogs(retentionDays: 30)
        try await waitUntil { !service.isClearing && storage.didClear }

        XCTAssertTrue(storage.readerHadFinishedWhenClearing)
        XCTAssertEqual(
            service.lastClearResult,
            "已清除 1 个文件，释放 \(AITokenUsageStorageManager.byteCount(11))；另有 2 个文件清除失败"
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter.notchFlowInternetDate.date(from: value)!
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }
}

private struct EmptyAITokenUsageReader: AITokenUsageSourceReading {
    let sourceID: AITokenUsageSourceID = .codex

    func read(since startDate: Date) -> AITokenUsageSourceReadResult {
        AITokenUsageSourceReadResult(
            sourceID: sourceID,
            status: AITokenUsageSourceStatus(id: sourceID, state: .detected, message: "empty"),
            events: []
        )
    }
}

private final class CancellationAwareAITokenUsageReader: AITokenUsageSourceReading, @unchecked Sendable {
    let sourceID: AITokenUsageSourceID = .codex
    private let lock = NSLock()
    private var started = false
    private var finished = false

    var hasStarted: Bool {
        lock.withLock { started }
    }

    var hasFinished: Bool {
        lock.withLock { finished }
    }

    func read(since startDate: Date) -> AITokenUsageSourceReadResult {
        lock.withLock { started = true }
        while !Task.isCancelled {
            Thread.sleep(forTimeInterval: 0.005)
        }
        lock.withLock { finished = true }
        return AITokenUsageSourceReadResult(
            sourceID: sourceID,
            status: AITokenUsageSourceStatus(id: sourceID, state: .detected, message: "cancelled"),
            events: []
        )
    }
}

private final class RecordingAITokenUsageStorageManager: AITokenUsageStorageManaging, @unchecked Sendable {
    private let lock = NSLock()
    private let reader: CancellationAwareAITokenUsageReader
    private var cleared = false
    private var finishedAtClear = false

    init(reader: CancellationAwareAITokenUsageReader) {
        self.reader = reader
    }

    var didClear: Bool {
        lock.withLock { cleared }
    }

    var readerHadFinishedWhenClearing: Bool {
        lock.withLock { finishedAtClear }
    }

    func snapshot(retentionDays: Int, now: Date, calendar: Calendar) -> AITokenUsageStorageSnapshot {
        .empty
    }

    func clearExpiredLogs(retentionDays: Int, now: Date, calendar: Calendar) -> AITokenUsageCleanupResult {
        lock.withLock {
            finishedAtClear = reader.hasFinished
            cleared = true
        }
        return AITokenUsageCleanupResult(
            deletedFileCount: 1,
            freedBytes: 11,
            failedFileCount: 2
        )
    }
}

private final class RetentionRecordingStorageManager: AITokenUsageStorageManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRetentionDays: [Int] = []

    var retentionDays: [Int] {
        lock.withLock { recordedRetentionDays }
    }

    func snapshot(retentionDays: Int, now: Date, calendar: Calendar) -> AITokenUsageStorageSnapshot {
        lock.withLock {
            recordedRetentionDays.append(retentionDays)
        }
        return .empty
    }

    func clearExpiredLogs(retentionDays: Int, now: Date, calendar: Calendar) -> AITokenUsageCleanupResult {
        AITokenUsageCleanupResult(deletedFileCount: 0, freedBytes: 0, failedFileCount: 0)
    }
}

private final class TemporaryStorageFixture {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func makeDirectory(_ name: String) throws -> URL {
        let directory = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    func writeFile(_ name: String, bytes: Int, in directory: URL, modificationDate: Date) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try Data(repeating: 0x61, count: bytes).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: fileURL.path)
        return fileURL
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
