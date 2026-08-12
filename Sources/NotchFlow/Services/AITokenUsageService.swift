import Combine
import Foundation

enum AITokenUsageSourceID: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex
    case claude
    case cursor
    case windsurf
    case copilot
    case roo
    case cline
    case `continue`
    case openAI

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .cursor:
            return "Cursor"
        case .windsurf:
            return "Windsurf"
        case .copilot:
            return "Copilot"
        case .roo:
            return "Roo"
        case .cline:
            return "Cline"
        case .continue:
            return "Continue"
        case .openAI:
            return "ChatGPT / OpenAI"
        }
    }
}

enum AITokenUsageSourceState: String, Equatable, Codable, Sendable {
    case available
    case detected
    case missing
    case unsupported
    case unreadable

    var title: String {
        switch self {
        case .available:
            return "可统计"
        case .detected:
            return "已检测"
        case .missing:
            return "未检测到"
        case .unsupported:
            return "暂不支持"
        case .unreadable:
            return "不可读取"
        }
    }
}

struct AITokenBreakdown: Equatable, Codable, Sendable {
    var inputTokens: Int
    var cachedInputTokens: Int
    var cacheCreationInputTokens: Int
    var cacheReadInputTokens: Int
    var outputTokens: Int
    var reasoningOutputTokens: Int
    var totalTokens: Int

    init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0,
        cacheReadInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens ?? (
            inputTokens
                + cacheCreationInputTokens
                + cacheReadInputTokens
                + outputTokens
        )
    }

    static let zero = AITokenBreakdown()

    static func + (lhs: AITokenBreakdown, rhs: AITokenBreakdown) -> AITokenBreakdown {
        AITokenBreakdown(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            cacheCreationInputTokens: lhs.cacheCreationInputTokens + rhs.cacheCreationInputTokens,
            cacheReadInputTokens: lhs.cacheReadInputTokens + rhs.cacheReadInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }

    mutating func add(_ other: AITokenBreakdown) {
        self = self + other
    }
}

struct AITokenUsageEvent: Equatable, Codable, Sendable {
    let sourceID: AITokenUsageSourceID
    let timestamp: Date
    let breakdown: AITokenBreakdown
    let model: String?
    let stableID: String
}

struct AITokenUsageDirectoryInfo: Equatable, Identifiable, Sendable {
    let url: URL
    let displayPath: String
    let sizeBytes: Int64
    let sizeText: String

    var id: String { url.path }
}

struct AITokenUsageStorageDirectory: Equatable, Sendable {
    let sourceID: AITokenUsageSourceID
    let url: URL
}

struct AITokenUsageCleanupPreview: Equatable, Sendable {
    let fileCount: Int
    let bytes: Int64

    static let empty = AITokenUsageCleanupPreview(fileCount: 0, bytes: 0)
}

struct AITokenUsageStorageSnapshot: Equatable, Sendable {
    let totalBytes: Int64
    let sourceDirectories: [AITokenUsageSourceID: [AITokenUsageDirectoryInfo]]
    let cleanupPreview: AITokenUsageCleanupPreview

    static let empty = AITokenUsageStorageSnapshot(
        totalBytes: 0,
        sourceDirectories: [:],
        cleanupPreview: .empty
    )
}

struct AITokenUsageCleanupResult: Equatable, Sendable {
    let deletedFileCount: Int
    let freedBytes: Int64
    let failedFileCount: Int
}

protocol AITokenUsageStorageManaging: Sendable {
    func snapshot(retentionDays: Int, now: Date, calendar: Calendar) -> AITokenUsageStorageSnapshot
    func clearExpiredLogs(retentionDays: Int, now: Date, calendar: Calendar) -> AITokenUsageCleanupResult
}

final class AITokenUsageStorageManager: AITokenUsageStorageManaging, @unchecked Sendable {
    typealias RemoveItem = (URL) throws -> Void

    private let directories: [AITokenUsageStorageDirectory]
    private let fileManager: FileManager
    private let removeItem: RemoveItem

    init(
        directories: [AITokenUsageStorageDirectory],
        fileManager: FileManager = .default,
        removeItem: RemoveItem? = nil
    ) {
        var seenPaths: Set<String> = []
        self.directories = directories.filter { directory in
            seenPaths.insert(directory.url.standardizedFileURL.path).inserted
        }
        self.fileManager = fileManager
        self.removeItem = removeItem ?? { url in
            try fileManager.removeItem(at: url)
        }
    }

    func snapshot(
        retentionDays: Int,
        now: Date,
        calendar: Calendar
    ) -> AITokenUsageStorageSnapshot {
        guard let cutoffDate = cutoffDate(retentionDays: retentionDays, now: now, calendar: calendar) else {
            return .empty
        }

        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        var totalBytes: Int64 = 0
        var previewFileCount = 0
        var previewBytes: Int64 = 0
        var sourceDirectories: [AITokenUsageSourceID: [AITokenUsageDirectoryInfo]] = [:]

        for directory in directories where directoryExists(directory.url) {
            guard !Task.isCancelled else {
                return .empty
            }

            var directoryBytes: Int64 = 0
            for file in usageFiles(in: directory.url) {
                directoryBytes += file.size
                if let modificationDate = file.modificationDate, modificationDate < cutoffDate {
                    previewFileCount += 1
                    previewBytes += file.size
                }
            }
            totalBytes += directoryBytes

            let standardizedPath = directory.url.standardizedFileURL.path
            let displayPath = standardizedPath == homePath
                ? "~"
                : standardizedPath.hasPrefix(homePath + "/")
                    ? "~" + standardizedPath.dropFirst(homePath.count)
                    : standardizedPath
            sourceDirectories[directory.sourceID, default: []].append(
                AITokenUsageDirectoryInfo(
                    url: directory.url,
                    displayPath: String(displayPath),
                    sizeBytes: directoryBytes,
                    sizeText: Self.byteCount(directoryBytes)
                )
            )
        }

        return AITokenUsageStorageSnapshot(
            totalBytes: totalBytes,
            sourceDirectories: sourceDirectories,
            cleanupPreview: AITokenUsageCleanupPreview(
                fileCount: previewFileCount,
                bytes: previewBytes
            )
        )
    }

    func clearExpiredLogs(
        retentionDays: Int,
        now: Date,
        calendar: Calendar
    ) -> AITokenUsageCleanupResult {
        guard let cutoffDate = cutoffDate(retentionDays: retentionDays, now: now, calendar: calendar) else {
            return AITokenUsageCleanupResult(deletedFileCount: 0, freedBytes: 0, failedFileCount: 0)
        }

        var deletedFileCount = 0
        var freedBytes: Int64 = 0
        var failedFileCount = 0

        for directory in directories where directoryExists(directory.url) {
            for file in usageFiles(in: directory.url) {
                guard let modificationDate = file.modificationDate, modificationDate < cutoffDate else {
                    continue
                }

                do {
                    try removeItem(file.url)
                    deletedFileCount += 1
                    freedBytes += file.size
                } catch {
                    failedFileCount += 1
                }
            }
        }

        return AITokenUsageCleanupResult(
            deletedFileCount: deletedFileCount,
            freedBytes: freedBytes,
            failedFileCount: failedFileCount
        )
    }

    private func usageFiles(in root: URL) -> [(url: URL, size: Int64, modificationDate: Date?)] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, size: Int64, modificationDate: Date?)] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard !Task.isCancelled else {
                break
            }
            guard Self.isCleanableFile(fileURL),
                  let values = try? fileURL.resourceValues(
                      forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
                  ),
                  values.isRegularFile == true
            else {
                continue
            }
            files.append(
                (
                    url: fileURL,
                    size: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate
                )
            )
        }
        return files
    }

    private func cutoffDate(retentionDays: Int, now: Date, calendar: Calendar) -> Date? {
        guard retentionDays > 0 else {
            return nil
        }
        return calendar.date(
            byAdding: .day,
            value: -retentionDays,
            to: calendar.startOfDay(for: now)
        )
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isCleanableFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "jsonl" { return true }
        if ext == "json" && url.lastPathComponent.hasSuffix(".response.json") { return true }
        return false
    }

    static func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

struct AITokenUsageSourceStatus: Equatable, Identifiable, Codable, Sendable {
    let id: AITokenUsageSourceID
    var state: AITokenUsageSourceState
    var message: String

    var displayName: String {
        id.displayName
    }
}

struct AITokenUsageSourceReadResult: Equatable, Sendable {
    let sourceID: AITokenUsageSourceID
    let status: AITokenUsageSourceStatus
    let events: [AITokenUsageEvent]
}

struct AITokenUsageDaySummary: Equatable, Identifiable, Codable, Sendable {
    let day: Date
    var breakdown: AITokenBreakdown
    var sourceBreakdowns: [AITokenUsageSourceID: AITokenBreakdown]

    var id: Date {
        day
    }
}

struct AITokenUsageSourceSummary: Equatable, Identifiable, Codable, Sendable {
    let id: AITokenUsageSourceID
    var breakdown: AITokenBreakdown

    var displayName: String {
        id.displayName
    }
}

struct AITokenUsageSummary: Equatable, Sendable {
    var daySummaries: [AITokenUsageDaySummary]
    var sourceSummaries: [AITokenUsageSourceSummary]
    var sourceStatuses: [AITokenUsageSourceStatus]
    var refreshedAt: Date?

    static let empty = AITokenUsageSummary(
        daySummaries: [],
        sourceSummaries: [],
        sourceStatuses: [],
        refreshedAt: nil
    )

    func todayTotal(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        return daySummaries.first(where: { calendar.isDate($0.day, inSameDayAs: startOfDay) })?
            .breakdown
            .totalTokens ?? 0
    }

    func totalForLastDays(_ dayCount: Int, endingAt date: Date = Date(), calendar: Calendar = .current) -> Int {
        guard dayCount > 0,
              let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: calendar.startOfDay(for: date))
        else {
            return 0
        }

        return daySummaries
            .filter { $0.day >= start && $0.day <= calendar.startOfDay(for: date) }
            .reduce(0) { $0 + $1.breakdown.totalTokens }
    }

    var topSourceSummaries: [AITokenUsageSourceSummary] {
        sourceSummaries
            .filter { $0.breakdown.totalTokens > 0 }
            .sorted { $0.breakdown.totalTokens > $1.breakdown.totalTokens }
    }

    func sourceSummaries(on date: Date = Date(), calendar: Calendar = .current) -> [AITokenUsageSourceSummary] {
        let startOfDay = calendar.startOfDay(for: date)
        guard let daySummary = daySummaries.first(where: { calendar.isDate($0.day, inSameDayAs: startOfDay) }) else {
            return []
        }

        return daySummary.sourceBreakdowns
            .map { sourceID, breakdown in
                AITokenUsageSourceSummary(id: sourceID, breakdown: breakdown)
            }
            .sorted { $0.breakdown.totalTokens > $1.breakdown.totalTokens }
    }
}

enum AITokenUsageFormatter {
    static func tokenCount(_ value: Int) -> String {
        let doubleValue = Double(value)

        if value >= 1_000_000 {
            return String(format: "%.1fM", doubleValue / 1_000_000)
        }

        if value >= 1_000 {
            return String(format: "%.1fK", doubleValue / 1_000)
        }

        return "\(value)"
    }
}

protocol AITokenUsageSourceReading: Sendable {
    var sourceID: AITokenUsageSourceID { get }
    func read(since startDate: Date) -> AITokenUsageSourceReadResult
}

enum AITokenUsageAggregator {
    static func summary(
        from results: [AITokenUsageSourceReadResult],
        calendar: Calendar = .current,
        refreshedAt: Date? = nil
    ) -> AITokenUsageSummary {
        var dailyBreakdowns: [Date: AITokenBreakdown] = [:]
        var dailySourceBreakdowns: [Date: [AITokenUsageSourceID: AITokenBreakdown]] = [:]
        var sourceBreakdowns: [AITokenUsageSourceID: AITokenBreakdown] = [:]

        for event in results.flatMap(\.events) {
            let day = calendar.startOfDay(for: event.timestamp)
            dailyBreakdowns[day, default: .zero].add(event.breakdown)
            dailySourceBreakdowns[day, default: [:]][event.sourceID, default: .zero].add(event.breakdown)
            sourceBreakdowns[event.sourceID, default: .zero].add(event.breakdown)
        }

        let daySummaries = dailyBreakdowns
            .map { day, breakdown in
                AITokenUsageDaySummary(
                    day: day,
                    breakdown: breakdown,
                    sourceBreakdowns: dailySourceBreakdowns[day] ?? [:]
                )
            }
            .sorted { $0.day > $1.day }

        let sourceSummaries = sourceBreakdowns
            .map { sourceID, breakdown in
                AITokenUsageSourceSummary(id: sourceID, breakdown: breakdown)
            }
            .sorted { $0.breakdown.totalTokens > $1.breakdown.totalTokens }

        return AITokenUsageSummary(
            daySummaries: daySummaries,
            sourceSummaries: sourceSummaries,
            sourceStatuses: results.map(\.status),
            refreshedAt: refreshedAt
        )
    }
}

private struct CodexUsageValues: Hashable, Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let cacheWriteInputTokens: Int
    let outputTokens: Int
    let reasoningOutputTokens: Int
    let totalTokens: Int

    init(_ object: [String: Any]) {
        inputTokens = intValue(object["input_tokens"])
        cachedInputTokens = intValue(object["cached_input_tokens"])
        cacheWriteInputTokens = intValue(object["cache_write_input_tokens"])
        outputTokens = intValue(object["output_tokens"])
        reasoningOutputTokens = intValue(object["reasoning_output_tokens"])
        totalTokens = intValueIfPresent(object["total_tokens"]) ?? (inputTokens + outputTokens)
    }

    var stableDescription: String {
        [
            inputTokens,
            cachedInputTokens,
            cacheWriteInputTokens,
            outputTokens,
            reasoningOutputTokens,
            totalTokens,
        ]
        .map(String.init)
        .joined(separator: ",")
    }
}

private struct CodexUsageFingerprint: Hashable, Sendable {
    let lastUsage: CodexUsageValues
    let cumulativeUsage: CodexUsageValues?
    let cumulativeGeneration: Int
    let fallbackTimestamp: String?

    var stableDescription: String {
        [
            String(cumulativeGeneration),
            lastUsage.stableDescription,
            cumulativeUsage?.stableDescription ?? "none",
            fallbackTimestamp ?? "",
        ]
        .joined(separator: "|")
    }
}

private struct CodexRawUsageEvent: Sendable {
    let timestamp: Date
    let breakdown: AITokenBreakdown
    let fingerprint: CodexUsageFingerprint
}

private struct CodexFileSnapshot {
    let sessionID: String
    var parentThreadID: String?
    var byteOffset: UInt64 = 0
    var trailingData = Data()
    var events: [CodexRawUsageEvent] = []
    var previousCumulativeTotal: Int?
    var cumulativeGeneration = 0
}

private final class CodexTokenUsageFileCache: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [String: CodexFileSnapshot] = [:]

    func snapshot(
        for fileURL: URL,
        sessionID: String,
        fileManager: FileManager
    ) -> CodexFileSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        guard let fileSize = fileSize(of: fileURL, fileManager: fileManager) else {
            return nil
        }

        var snapshot = snapshots[sessionID] ?? CodexFileSnapshot(sessionID: sessionID)
        if fileSize < snapshot.byteOffset {
            snapshot = CodexFileSnapshot(sessionID: sessionID)
        }

        guard fileSize > snapshot.byteOffset else {
            return snapshot
        }

        guard let scanState = scanJSONLFile(
            at: fileURL,
            startingAt: snapshot.byteOffset,
            carrying: snapshot.trailingData,
            markers: [Self.tokenCountMarker, Self.sessionMetaMarker],
            handleObject: { object in
                Self.consume(object, into: &snapshot)
            }
        ) else {
            return snapshots[sessionID]
        }

        snapshot.byteOffset = scanState.byteOffset
        snapshot.trailingData = scanState.trailingData
        snapshots[sessionID] = snapshot
        return snapshot
    }

    private static func consume(_ object: [String: Any], into snapshot: inout CodexFileSnapshot) {
        if stringValue(object["type"]) == "session_meta",
           let payload = object["payload"] as? [String: Any],
           normalizedThreadID(stringValue(payload["id"])) == snapshot.sessionID
        {
            snapshot.parentThreadID = parentThreadID(from: payload)
            return
        }

        guard stringValue(object["type"]) == "event_msg",
              let payload = object["payload"] as? [String: Any],
              stringValue(payload["type"]) == "token_count",
              let timestampString = stringValue(object["timestamp"]),
              let timestamp = ISO8601DateFormatter.notchFlowDate(from: timestampString),
              let info = payload["info"] as? [String: Any],
              let lastUsageObject = info["last_token_usage"] as? [String: Any]
        else {
            return
        }

        let lastUsage = CodexUsageValues(lastUsageObject)
        guard lastUsage.totalTokens > 0 else {
            return
        }

        let cumulativeUsage = (info["total_token_usage"] as? [String: Any]).map(CodexUsageValues.init)
        if let cumulativeTotal = cumulativeUsage?.totalTokens {
            if let previous = snapshot.previousCumulativeTotal, cumulativeTotal < previous {
                snapshot.cumulativeGeneration += 1
            }
            snapshot.previousCumulativeTotal = cumulativeTotal
        }

        let fingerprint = CodexUsageFingerprint(
            lastUsage: lastUsage,
            cumulativeUsage: cumulativeUsage,
            cumulativeGeneration: snapshot.cumulativeGeneration,
            fallbackTimestamp: cumulativeUsage == nil ? timestampString : nil
        )
        let breakdown = AITokenBreakdown(
            inputTokens: lastUsage.inputTokens,
            cachedInputTokens: lastUsage.cachedInputTokens,
            cacheCreationInputTokens: lastUsage.cacheWriteInputTokens,
            outputTokens: lastUsage.outputTokens,
            reasoningOutputTokens: lastUsage.reasoningOutputTokens,
            totalTokens: lastUsage.totalTokens
        )
        snapshot.events.append(
            CodexRawUsageEvent(
                timestamp: timestamp,
                breakdown: breakdown,
                fingerprint: fingerprint
            )
        )
    }

    private static let tokenCountMarker = Data("\"token_count\"".utf8)
    private static let sessionMetaMarker = Data("\"session_meta\"".utf8)
}

struct CodexTokenUsageSourceReader: AITokenUsageSourceReading, @unchecked Sendable {
    let sourceID: AITokenUsageSourceID = .codex
    let rootDirectories: [URL]
    private let fileManager: FileManager
    private let cache: CodexTokenUsageFileCache

    init(rootDirectories: [URL] = Self.defaultRootDirectories(), fileManager: FileManager = .default) {
        self.rootDirectories = rootDirectories
        self.fileManager = fileManager
        cache = CodexTokenUsageFileCache()
    }

    func read(since startDate: Date) -> AITokenUsageSourceReadResult {
        let existingRoots = rootDirectories.filter { directoryExists($0) }
        guard !existingRoots.isEmpty else {
            return result(state: .missing, message: "未找到 Codex 会话目录", events: [])
        }

        let rolloutFileURLs = existingRoots.flatMap { self.rolloutFiles(in: $0) }
        let fileBySessionID = preferredFilesBySessionID(rolloutFileURLs)
        var requestedSessionIDs = Set(
            fileBySessionID.compactMap { sessionID, fileURL in
                shouldReadUsageFile(fileURL, since: startDate, fileManager: fileManager) ? sessionID : nil
            }
        )
        var pendingSessionIDs = Array(requestedSessionIDs)
        var snapshots: [String: CodexFileSnapshot] = [:]

        while let sessionID = pendingSessionIDs.popLast() {
            guard snapshots[sessionID] == nil,
                  let fileURL = fileBySessionID[sessionID],
                  let snapshot = cache.snapshot(
                      for: fileURL,
                      sessionID: sessionID,
                      fileManager: fileManager
                  )
            else {
                continue
            }

            snapshots[sessionID] = snapshot
            if let parentThreadID = snapshot.parentThreadID,
               fileBySessionID[parentThreadID] != nil,
               snapshots[parentThreadID] == nil
            {
                pendingSessionIDs.append(parentThreadID)
            }
        }

        // Parent sessions are loaded to identify replayed history. If one of them
        // contains an in-window event, retain the original event and date too.
        requestedSessionIDs.formUnion(snapshots.keys)
        let fingerprintsBySession = snapshots.mapValues { snapshot in
            Set(snapshot.events.map(\.fingerprint))
        }
        var parsedEvents: [AITokenUsageEvent] = []

        for sessionID in requestedSessionIDs.sorted() {
            guard let snapshot = snapshots[sessionID] else {
                continue
            }

            var seenInSession: Set<CodexUsageFingerprint> = []
            for event in snapshot.events {
                guard seenInSession.insert(event.fingerprint).inserted,
                      !isInherited(
                          event.fingerprint,
                          from: snapshot.parentThreadID,
                          snapshots: snapshots,
                          fingerprintsBySession: fingerprintsBySession
                      ),
                      event.timestamp >= startDate
                else {
                    continue
                }

                parsedEvents.append(
                    AITokenUsageEvent(
                        sourceID: sourceID,
                        timestamp: event.timestamp,
                        breakdown: event.breakdown,
                        model: nil,
                        stableID: "codex:\(sessionID):\(event.fingerprint.stableDescription)"
                    )
                )
            }
        }

        return result(
            state: parsedEvents.isEmpty ? .detected : .available,
            message: parsedEvents.isEmpty ? "已检测到 Codex，暂无 token 记录" : "已读取 Codex token 记录",
            events: parsedEvents
        )
    }

    private func result(
        state: AITokenUsageSourceState,
        message: String,
        events: [AITokenUsageEvent]
    ) -> AITokenUsageSourceReadResult {
        AITokenUsageSourceReadResult(
            sourceID: sourceID,
            status: AITokenUsageSourceStatus(id: sourceID, state: state, message: message),
            events: events
        )
    }

    private func rolloutFiles(in root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
    }

    private func preferredFilesBySessionID(_ files: [URL]) -> [String: URL] {
        var preferred: [String: URL] = [:]
        for fileURL in files {
            let sessionID = codexSessionID(from: fileURL)
            guard let current = preferred[sessionID] else {
                preferred[sessionID] = fileURL
                continue
            }

            if (fileSize(of: fileURL, fileManager: fileManager) ?? 0)
                > (fileSize(of: current, fileManager: fileManager) ?? 0)
            {
                preferred[sessionID] = fileURL
            }
        }
        return preferred
    }

    private func isInherited(
        _ fingerprint: CodexUsageFingerprint,
        from parentThreadID: String?,
        snapshots: [String: CodexFileSnapshot],
        fingerprintsBySession: [String: Set<CodexUsageFingerprint>]
    ) -> Bool {
        var currentThreadID = parentThreadID
        var visited: Set<String> = []

        while let threadID = currentThreadID, visited.insert(threadID).inserted {
            if fingerprintsBySession[threadID]?.contains(fingerprint) == true {
                return true
            }
            currentThreadID = snapshots[threadID]?.parentThreadID
        }
        return false
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func defaultRootDirectories(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex-shared/session-pool/sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex-shared/session-pool/archived_sessions", isDirectory: true),
        ]
    }
}

struct ClaudeTokenUsageSourceReader: AITokenUsageSourceReading, @unchecked Sendable {
    let sourceID: AITokenUsageSourceID = .claude
    let projectDirectories: [URL]
    let captureDirectories: [URL]
    private let fileManager: FileManager

    init(
        projectDirectories: [URL] = Self.defaultProjectDirectories(),
        captureDirectories: [URL] = Self.defaultCaptureDirectories(),
        fileManager: FileManager = .default
    ) {
        self.projectDirectories = projectDirectories
        self.captureDirectories = captureDirectories
        self.fileManager = fileManager
    }

    func read(since startDate: Date) -> AITokenUsageSourceReadResult {
        let existingProjectRoots = projectDirectories.filter { directoryExists($0) }
        let existingCaptureRoots = captureDirectories.filter { directoryExists($0) }
        guard !existingProjectRoots.isEmpty || !existingCaptureRoots.isEmpty else {
            return result(state: .missing, message: "未找到 Claude 本地记录目录", events: [])
        }

        var latestEventsByStableID: [String: AITokenUsageEvent] = [:]
        var earliestTimestampsByStableID: [String: Date] = [:]

        func merge(_ event: AITokenUsageEvent) {
            earliestTimestampsByStableID[event.stableID] = min(
                earliestTimestampsByStableID[event.stableID] ?? event.timestamp,
                event.timestamp
            )

            guard let existing = latestEventsByStableID[event.stableID] else {
                latestEventsByStableID[event.stableID] = event
                return
            }

            let useIncomingUsage = event.timestamp > existing.timestamp
                || (event.timestamp == existing.timestamp
                    && event.breakdown.totalTokens >= existing.breakdown.totalTokens)
            if useIncomingUsage {
                latestEventsByStableID[event.stableID] = event
            }
        }

        for fileURL in existingProjectRoots.flatMap({ jsonlFiles(in: $0, since: startDate) }) {
            for event in tokenEvents(inProjectFile: fileURL, since: startDate) {
                merge(event)
            }
        }

        for fileURL in existingCaptureRoots.flatMap({ captureFiles(in: $0, since: startDate) }) {
            if let event = tokenEvent(inCaptureFile: fileURL, since: startDate) {
                merge(event)
            }
        }

        let parsedEvents = latestEventsByStableID.map { stableID, event in
            AITokenUsageEvent(
                sourceID: event.sourceID,
                timestamp: earliestTimestampsByStableID[stableID] ?? event.timestamp,
                breakdown: event.breakdown,
                model: event.model,
                stableID: stableID
            )
        }

        return result(
            state: parsedEvents.isEmpty ? .detected : .available,
            message: parsedEvents.isEmpty ? "已检测到 Claude，暂无 token 记录" : "已读取 Claude token 记录",
            events: parsedEvents
        )
    }

    private func result(
        state: AITokenUsageSourceState,
        message: String,
        events: [AITokenUsageEvent]
    ) -> AITokenUsageSourceReadResult {
        AITokenUsageSourceReadResult(
            sourceID: sourceID,
            status: AITokenUsageSourceStatus(id: sourceID, state: state, message: message),
            events: events
        )
    }

    private func jsonlFiles(in root: URL, since startDate: Date) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                guard url.pathExtension == "jsonl" else {
                    return false
                }
                if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modDate < startDate {
                    return false
                }
                return true
            }
    }

    private func captureFiles(in root: URL, since startDate: Date) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                guard url.lastPathComponent.hasSuffix(".response.json") else {
                    return false
                }
                if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modDate < startDate {
                    return false
                }
                return true
            }
    }

    private func tokenEvents(
        inProjectFile fileURL: URL,
        since startDate: Date
    ) -> [AITokenUsageEvent] {
        var events: [AITokenUsageEvent] = []
        _ = scanJSONLFile(
            at: fileURL,
            startingAt: 0,
            carrying: Data(),
            markers: [Self.usageMarker],
            handleObject: { object in
                if let event = claudeProjectEvent(
                    from: object,
                    fileURL: fileURL,
                    since: startDate
                ) {
                    events.append(event)
                }
            }
        )
        return events
    }

    private func claudeProjectEvent(
        from object: [String: Any],
        fileURL: URL,
        since startDate: Date
    ) -> AITokenUsageEvent? {
        guard let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let timestampString = stringValue(object["timestamp"]),
              let timestamp = ISO8601DateFormatter.notchFlowDate(from: timestampString),
              timestamp >= startDate
        else {
            return nil
        }

        let sessionID = stringValue(object["sessionId"]) ?? fileURL.deletingPathExtension().lastPathComponent
        let messageID = stringValue(message["id"]) ?? stringValue(object["uuid"]) ?? timestampString
        let breakdown = claudeBreakdown(from: usage)
        guard breakdown.totalTokens > 0 else {
            return nil
        }

        let stableID = stringValue(message["id"]) != nil
            ? "claude:\(messageID)"
            : "claude-project:\(sessionID):\(messageID)"

        return AITokenUsageEvent(
            sourceID: sourceID,
            timestamp: timestamp,
            breakdown: breakdown,
            model: stringValue(message["model"]),
            stableID: stableID
        )
    }

    private func tokenEvent(
        inCaptureFile fileURL: URL,
        since startDate: Date
    ) -> AITokenUsageEvent? {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = object["usage"] as? [String: Any]
        else {
            return nil
        }

        let timestamp = stringValue(object["timestamp"])
            .flatMap(ISO8601DateFormatter.notchFlowDate(from:))
            ?? fileModificationDate(fileURL)
            ?? Date.distantPast
        guard timestamp >= startDate else {
            return nil
        }

        let breakdown = claudeBreakdown(from: usage)
        guard breakdown.totalTokens > 0 else {
            return nil
        }

        let responseID = stringValue(object["id"])
        let stableID = responseID.map { "claude:\($0)" } ?? "claude-capture:\(fileURL.path)"

        return AITokenUsageEvent(
            sourceID: sourceID,
            timestamp: timestamp,
            breakdown: breakdown,
            model: stringValue(object["model"]),
            stableID: stableID
        )
    }

    private func claudeBreakdown(from usage: [String: Any]) -> AITokenBreakdown {
        AITokenBreakdown(
            inputTokens: intValue(usage["input_tokens"]),
            cacheCreationInputTokens: intValue(usage["cache_creation_input_tokens"]),
            cacheReadInputTokens: intValue(usage["cache_read_input_tokens"]),
            outputTokens: intValue(usage["output_tokens"])
        )
    }

    private func fileModificationDate(_ url: URL) -> Date? {
        try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func defaultProjectDirectories(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String]? = nil
    ) -> [URL] {
        [
            configurationRoot(homeDirectory: homeDirectory, environment: environment)
                .appendingPathComponent("projects", isDirectory: true),
        ]
    }

    static func defaultCaptureDirectories(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String]? = nil
    ) -> [URL] {
        [
            configurationRoot(homeDirectory: homeDirectory, environment: environment)
                .appendingPathComponent("cc-capture", isDirectory: true),
        ]
    }

    private static func configurationRoot(
        homeDirectory: URL,
        environment: [String: String]?
    ) -> URL {
        let environment = environment ?? ProcessInfo.processInfo.environment
        guard let customPath = environment["CLAUDE_CONFIG_DIR"], !customPath.isEmpty else {
            return homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        }
        return URL(fileURLWithPath: customPath, isDirectory: true).standardizedFileURL
    }

    private static let usageMarker = Data("\"usage\"".utf8)
}

private struct JSONLScanState {
    let byteOffset: UInt64
    let trailingData: Data
}

private func scanJSONLFile(
    at fileURL: URL,
    startingAt byteOffset: UInt64,
    carrying trailingData: Data,
    markers: [Data],
    handleObject: ([String: Any]) -> Void
) -> JSONLScanState? {
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
        return nil
    }
    defer { try? handle.close() }

    do {
        try handle.seek(toOffset: byteOffset)
        var buffer = trailingData

        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            guard !Task.isCancelled else {
                return nil
            }
            buffer.append(chunk)
            var lineStart = buffer.startIndex

            while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                let lineRange = lineStart ..< newline
                let containsRelevantMarker = markers.contains { marker in
                    buffer.range(of: marker, options: [], in: lineRange) != nil
                }
                if containsRelevantMarker,
                   let object = jsonObject(from: Data(buffer[lineRange]))
                {
                    handleObject(object)
                }
                lineStart = buffer.index(after: newline)
            }

            if lineStart > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex ..< lineStart)
            }
        }

        // A JSONL file does not always end with a newline. Parse a complete,
        // relevant trailing object; carry the remainder into the next append scan.
        if !buffer.isEmpty {
            let containsRelevantMarker = markers.contains { buffer.range(of: $0) != nil }
            if containsRelevantMarker, let object = jsonObject(from: buffer) {
                handleObject(object)
                buffer.removeAll(keepingCapacity: false)
            }
        }

        return JSONLScanState(
            byteOffset: try handle.offset(),
            trailingData: buffer
        )
    } catch {
        return nil
    }
}

private func jsonObject(from data: Data) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func codexSessionID(from fileURL: URL) -> String {
    let stem = fileURL.deletingPathExtension().lastPathComponent
    let suffix = String(stem.suffix(36))
    if UUID(uuidString: suffix) != nil {
        return suffix.lowercased()
    }
    return fileURL.standardizedFileURL.path.lowercased()
}

private func normalizedThreadID(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
        return nil
    }
    return value.lowercased()
}

private func parentThreadID(from payload: [String: Any]) -> String? {
    guard let source = payload["source"] as? [String: Any],
          let subagent = source["subagent"] as? [String: Any],
          let threadSpawn = subagent["thread_spawn"] as? [String: Any]
    else {
        return nil
    }
    return normalizedThreadID(stringValue(threadSpawn["parent_thread_id"]))
}

private func fileSize(of fileURL: URL, fileManager: FileManager) -> UInt64? {
    guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) else {
        return nil
    }
    if let number = attributes[.size] as? NSNumber {
        return number.uint64Value
    }
    if let value = attributes[.size] as? Int {
        return UInt64(value)
    }
    return nil
}

private func shouldReadUsageFile(_ fileURL: URL, since startDate: Date, fileManager: FileManager) -> Bool {
    guard let modificationDate = try? fileManager
        .attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    else {
        return true
    }
    return modificationDate >= startDate
}

struct AITokenUsagePresenceSourceReader: AITokenUsageSourceReading, @unchecked Sendable {
    let sourceID: AITokenUsageSourceID
    let candidatePaths: [URL]
    private let fileManager: FileManager

    init(sourceID: AITokenUsageSourceID, candidatePaths: [URL], fileManager: FileManager = .default) {
        self.sourceID = sourceID
        self.candidatePaths = candidatePaths
        self.fileManager = fileManager
    }

    func read(since startDate: Date) -> AITokenUsageSourceReadResult {
        let detected = candidatePaths.contains { fileManager.fileExists(atPath: $0.path) }
        let state: AITokenUsageSourceState = detected ? .unsupported : .missing
        let message = detected ? "已检测，暂无 token 数据支持" : "未检测到本机记录"

        return AITokenUsageSourceReadResult(
            sourceID: sourceID,
            status: AITokenUsageSourceStatus(id: sourceID, state: state, message: message),
            events: []
        )
    }
}

@MainActor
final class AITokenUsageService: ObservableObject {
    @Published private(set) var summary: AITokenUsageSummary = .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage = "AI 用量统计已关闭"
    @Published private(set) var diskUsageText = "计算中..."
    @Published private(set) var diskUsageBytes: Int64 = 0
    @Published private(set) var sourceDirectories: [AITokenUsageSourceID: [AITokenUsageDirectoryInfo]] = [:]
    @Published private(set) var cleanupPreview: AITokenUsageCleanupPreview = .empty
    @Published private(set) var isCalculatingStorage = false
    @Published private(set) var isClearing = false
    @Published private(set) var lastClearResult: String?

    private let settings: AppSettings
    private let calendar: Calendar
    private let refreshWorker: AITokenUsageRefreshWorker
    private let storageManager: AITokenUsageStorageManaging
    private let nowProvider: @Sendable () -> Date
    private let refreshInterval: TimeInterval = 5 * 60
    private let historyDays = 30
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var storageTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings,
        readers: [AITokenUsageSourceReading]? = nil,
        storageManager: AITokenUsageStorageManaging? = nil,
        calendar: Calendar = .current,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settings = settings
        self.calendar = calendar
        self.storageManager = storageManager ?? AITokenUsageStorageManager(
            directories: Self.defaultStorageDirectories()
        )
        self.nowProvider = nowProvider
        refreshWorker = AITokenUsageRefreshWorker(
            readers: readers ?? Self.defaultReaders(),
            calendar: calendar
        )
    }

    var todayTotalTokens: Int {
        summary.todayTotal(calendar: calendar)
    }

    var sevenDayTotalTokens: Int {
        summary.totalForLastDays(7, calendar: calendar)
    }

    var thirtyDayTotalTokens: Int {
        summary.totalForLastDays(30, calendar: calendar)
    }

    var lastRefreshText: String {
        guard let refreshedAt = summary.refreshedAt else {
            return "尚未刷新"
        }

        return Self.timeFormatter.string(from: refreshedAt)
    }

    var cleanupPreviewText: String {
        if isCalculatingStorage {
            return "计算中..."
        }
        guard cleanupPreview.fileCount > 0 else {
            return "没有可清理文件"
        }
        return "\(cleanupPreview.fileCount) 个文件、\(AITokenUsageStorageManager.byteCount(cleanupPreview.bytes))"
    }

    func start() {
        bindSettings()
        calculateDiskUsage()

        if settings.aiTokenUsageEnabled {
            scheduleRefreshTimer()
            refresh()
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        storageTask?.cancel()
        storageTask = nil
        cleanupTask?.cancel()
        cleanupTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        isRefreshing = false
        isCalculatingStorage = false
        isClearing = false
        cancellables.removeAll()
    }

    func refreshIfNeeded(maximumAge: TimeInterval = 120) {
        guard settings.aiTokenUsageEnabled else {
            return
        }

        guard let refreshedAt = summary.refreshedAt else {
            refresh()
            return
        }

        if Date().timeIntervalSince(refreshedAt) > maximumAge {
            refresh()
        }
    }

    func refresh() {
        guard settings.aiTokenUsageEnabled else {
            refreshTask?.cancel()
            refreshTask = nil
            summary = .empty
            isRefreshing = false
            statusMessage = "AI 用量统计已关闭"
            return
        }

        guard !isRefreshing, !isClearing else {
            return
        }

        isRefreshing = true
        statusMessage = "正在统计 AI 用量..."

        let startDate = calendar.date(
            byAdding: .day,
            value: -(historyDays - 1),
            to: calendar.startOfDay(for: Date())
        ) ?? Date(timeIntervalSinceNow: -TimeInterval(historyDays * 24 * 60 * 60))

        refreshTask = Task.detached(priority: .utility) { [refreshWorker] in
            let result = refreshWorker.refresh(since: startDate)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else {
                    return
                }

                self.summary = result.summary
                self.statusMessage = result.statusMessage
                self.isRefreshing = false
                self.refreshTask = nil
                self.calculateDiskUsage()
            }
        }
    }

    private func bindSettings() {
        guard cancellables.isEmpty else {
            return
        }

        settings.$aiTokenUsageEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else {
                    return
                }

                if isEnabled {
                    self.scheduleRefreshTimer()
                    self.refresh()
                } else {
                    self.refreshTimer?.invalidate()
                    self.refreshTimer = nil
                    self.refreshTask?.cancel()
                    self.refreshTask = nil
                    self.summary = .empty
                    self.isRefreshing = false
                    self.statusMessage = "AI 用量统计已关闭"
                }
            }
            .store(in: &cancellables)

        settings.$logRetentionPreset
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.calculateDiskUsage()
            }
            .store(in: &cancellables)
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()

        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    static func defaultReaders(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AITokenUsageSourceReading] {
        [
            CodexTokenUsageSourceReader(rootDirectories: CodexTokenUsageSourceReader.defaultRootDirectories(homeDirectory: homeDirectory)),
            ClaudeTokenUsageSourceReader(
                projectDirectories: ClaudeTokenUsageSourceReader.defaultProjectDirectories(homeDirectory: homeDirectory),
                captureDirectories: ClaudeTokenUsageSourceReader.defaultCaptureDirectories(homeDirectory: homeDirectory)
            ),
            AITokenUsagePresenceSourceReader(
                sourceID: .cursor,
                candidatePaths: [
                    homeDirectory.appendingPathComponent(".cursor", isDirectory: true),
                    homeDirectory.appendingPathComponent("Library/Application Support/Cursor", isDirectory: true),
                ]
            ),
            AITokenUsagePresenceSourceReader(
                sourceID: .windsurf,
                candidatePaths: [
                    homeDirectory.appendingPathComponent(".windsurf", isDirectory: true),
                    homeDirectory.appendingPathComponent("Library/Application Support/Windsurf", isDirectory: true),
                ]
            ),
            AITokenUsagePresenceSourceReader(
                sourceID: .copilot,
                candidatePaths: [
                    homeDirectory.appendingPathComponent(".copilot", isDirectory: true),
                    homeDirectory.appendingPathComponent("Library/Application Support/Code/User/globalStorage/github.copilot-chat", isDirectory: true),
                ]
            ),
            AITokenUsagePresenceSourceReader(
                sourceID: .roo,
                candidatePaths: [homeDirectory.appendingPathComponent(".roo", isDirectory: true)]
            ),
            AITokenUsagePresenceSourceReader(
                sourceID: .cline,
                candidatePaths: [
                    homeDirectory.appendingPathComponent(".cline", isDirectory: true),
                    homeDirectory.appendingPathComponent("Documents/Cline", isDirectory: true),
                ]
            ),
            AITokenUsagePresenceSourceReader(
                sourceID: .continue,
                candidatePaths: [homeDirectory.appendingPathComponent(".continue", isDirectory: true)]
            ),
            AITokenUsagePresenceSourceReader(
                sourceID: .openAI,
                candidatePaths: [
                    homeDirectory.appendingPathComponent("Library/Application Support/com.openai.chat", isDirectory: true),
                    homeDirectory.appendingPathComponent("Library/Application Support/OpenAI", isDirectory: true),
                ]
            ),
        ]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - Disk Usage & Cleanup

    private nonisolated static func defaultStorageDirectories(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [AITokenUsageStorageDirectory] {
        let codexDirectories = [
            homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex-shared/session-pool/sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex-shared/session-pool/archived_sessions", isDirectory: true),
        ].map { AITokenUsageStorageDirectory(sourceID: .codex, url: $0) }

        let claudeDirectories = (
            ClaudeTokenUsageSourceReader.defaultProjectDirectories(homeDirectory: homeDirectory)
                + ClaudeTokenUsageSourceReader.defaultCaptureDirectories(homeDirectory: homeDirectory)
        ).map { AITokenUsageStorageDirectory(sourceID: .claude, url: $0) }

        return codexDirectories + claudeDirectories
    }

    func calculateDiskUsage() {
        storageTask?.cancel()
        isCalculatingStorage = true

        let retentionDays = settings.logRetentionPreset.rawValue
        let now = nowProvider()
        let calendar = calendar
        let storageManager = storageManager

        storageTask = Task.detached(priority: .utility) { [weak self] in
            let snapshot = storageManager.snapshot(
                retentionDays: retentionDays,
                now: now,
                calendar: calendar
            )
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.applyStorageSnapshot(snapshot)
                self.isCalculatingStorage = false
                self.storageTask = nil
            }
        }
    }

    func clearOldLogs(retentionDays: Int) {
        guard !isClearing, retentionDays > 0 else { return }

        isClearing = true
        lastClearResult = nil

        let runningRefreshTask = refreshTask
        let runningStorageTask = storageTask
        runningRefreshTask?.cancel()
        runningStorageTask?.cancel()
        let storageManager = storageManager
        let calendar = calendar
        let now = nowProvider()

        cleanupTask = Task { @MainActor [weak self] in
            await runningRefreshTask?.value
            await runningStorageTask?.value
            guard let self, !Task.isCancelled else { return }

            self.refreshTask = nil
            self.storageTask = nil
            self.isRefreshing = false
            self.isCalculatingStorage = true

            let result = await Task.detached(priority: .utility) {
                storageManager.clearExpiredLogs(
                    retentionDays: retentionDays,
                    now: now,
                    calendar: calendar
                )
            }.value
            let snapshot = await Task.detached(priority: .utility) {
                storageManager.snapshot(
                    retentionDays: retentionDays,
                    now: now,
                    calendar: calendar
                )
            }.value

            guard !Task.isCancelled else { return }
            self.applyStorageSnapshot(snapshot)
            self.isCalculatingStorage = false
            self.lastClearResult = Self.cleanupResultText(result)
            self.summary = .empty
            self.isClearing = false
            self.cleanupTask = nil
            self.refresh()
        }
    }

    private func applyStorageSnapshot(_ snapshot: AITokenUsageStorageSnapshot) {
        diskUsageBytes = snapshot.totalBytes
        diskUsageText = AITokenUsageStorageManager.byteCount(snapshot.totalBytes)
        sourceDirectories = snapshot.sourceDirectories
        cleanupPreview = snapshot.cleanupPreview
    }

    private nonisolated static func cleanupResultText(_ result: AITokenUsageCleanupResult) -> String {
        let failureSuffix = result.failedFileCount > 0
            ? "；另有 \(result.failedFileCount) 个文件清除失败"
            : ""

        if result.deletedFileCount > 0 {
            return "已清除 \(result.deletedFileCount) 个文件，释放 \(AITokenUsageStorageManager.byteCount(result.freedBytes))\(failureSuffix)"
        }
        if result.failedFileCount > 0 {
            return "没有成功清除文件\(failureSuffix)"
        }
        return "没有需要清除的文件"
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let notchFlowInternetDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let notchFlowInternetDateWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func notchFlowDate(from string: String) -> Date? {
        notchFlowInternetDateWithFractionalSeconds.date(from: string)
            ?? notchFlowInternetDate.date(from: string)
    }
}

private struct AITokenUsageRefreshResult: Sendable {
    let summary: AITokenUsageSummary
    let statusMessage: String
}

private final class AITokenUsageRefreshWorker: @unchecked Sendable {
    private let readers: [AITokenUsageSourceReading]
    private let calendar: Calendar

    init(readers: [AITokenUsageSourceReading], calendar: Calendar) {
        self.readers = readers
        self.calendar = calendar
    }

    func refresh(since startDate: Date) -> AITokenUsageRefreshResult {
        let results = readers.map { $0.read(since: startDate) }
        let summary = AITokenUsageAggregator.summary(
            from: results,
            calendar: calendar,
            refreshedAt: Date()
        )
        let statusMessage = summary.todayTotal(calendar: calendar) > 0
            ? "已刷新今日 AI token 用量"
            : "暂无今日 AI token 记录"

        return AITokenUsageRefreshResult(summary: summary, statusMessage: statusMessage)
    }
}

private func stringValue(_ value: Any?) -> String? {
    value as? String
}

private func intValueIfPresent(_ value: Any?) -> Int? {
    switch value {
    case let int as Int:
        return int
    case let double as Double:
        return Int(double)
    case let number as NSNumber:
        return number.intValue
    case let string as String:
        return Int(string)
    default:
        return nil
    }
}

private func intValue(_ value: Any?) -> Int {
    intValueIfPresent(value) ?? 0
}
