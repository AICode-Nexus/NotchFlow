import Combine
import Foundation

enum AITokenUsageSourceID: String, CaseIterable, Identifiable, Codable {
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

enum AITokenUsageSourceState: String, Equatable, Codable {
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

struct AITokenBreakdown: Equatable, Codable {
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

struct AITokenUsageEvent: Equatable, Codable {
    let sourceID: AITokenUsageSourceID
    let timestamp: Date
    let breakdown: AITokenBreakdown
    let model: String?
    let stableID: String
}

struct AITokenUsageSourceStatus: Equatable, Identifiable, Codable {
    let id: AITokenUsageSourceID
    var state: AITokenUsageSourceState
    var message: String

    var displayName: String {
        id.displayName
    }
}

struct AITokenUsageSourceReadResult: Equatable {
    let sourceID: AITokenUsageSourceID
    let status: AITokenUsageSourceStatus
    let events: [AITokenUsageEvent]
}

struct AITokenUsageDaySummary: Equatable, Identifiable, Codable {
    let day: Date
    var breakdown: AITokenBreakdown
    var sourceBreakdowns: [AITokenUsageSourceID: AITokenBreakdown]

    var id: Date {
        day
    }
}

struct AITokenUsageSourceSummary: Equatable, Identifiable, Codable {
    let id: AITokenUsageSourceID
    var breakdown: AITokenBreakdown

    var displayName: String {
        id.displayName
    }
}

struct AITokenUsageSummary: Equatable {
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

protocol AITokenUsageSourceReading {
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

struct CodexTokenUsageSourceReader: AITokenUsageSourceReading {
    let sourceID: AITokenUsageSourceID = .codex
    let rootDirectories: [URL]
    private let fileManager: FileManager

    init(rootDirectories: [URL] = Self.defaultRootDirectories(), fileManager: FileManager = .default) {
        self.rootDirectories = rootDirectories
        self.fileManager = fileManager
    }

    func read(since startDate: Date) -> AITokenUsageSourceReadResult {
        let existingRoots = rootDirectories.filter { directoryExists($0) }
        guard !existingRoots.isEmpty else {
            return result(state: .missing, message: "未找到 Codex 会话目录", events: [])
        }

        let parsedEvents = existingRoots
            .flatMap { rolloutFiles(in: $0) }
            .flatMap { tokenEvents(in: $0, since: startDate) }

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
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasPrefix("rollout-") && $0.pathExtension == "jsonl" }
    }

    private func tokenEvents(in fileURL: URL, since startDate: Date) -> [AITokenUsageEvent] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                codexEvent(from: String(line), fileURL: fileURL, since: startDate)
            }
    }

    private func codexEvent(from line: String, fileURL: URL, since startDate: Date) -> AITokenUsageEvent? {
        guard let object = jsonObject(from: line),
              stringValue(object["type"]) == "event_msg",
              let payload = object["payload"] as? [String: Any],
              stringValue(payload["type"]) == "token_count",
              let timestampString = stringValue(object["timestamp"]),
              let timestamp = ISO8601DateFormatter.notchFlowDate(from: timestampString),
              timestamp >= startDate,
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any]
        else {
            return nil
        }

        let breakdown = AITokenBreakdown(
            inputTokens: intValue(usage["input_tokens"]),
            cachedInputTokens: intValue(usage["cached_input_tokens"]),
            outputTokens: intValue(usage["output_tokens"]),
            reasoningOutputTokens: intValue(usage["reasoning_output_tokens"]),
            totalTokens: intValue(usage["total_tokens"])
        )

        guard breakdown.totalTokens > 0 else {
            return nil
        }

        return AITokenUsageEvent(
            sourceID: sourceID,
            timestamp: timestamp,
            breakdown: breakdown,
            model: nil,
            stableID: "\(fileURL.path):\(timestampString)"
        )
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func defaultRootDirectories(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex-shared/session-pool/sessions", isDirectory: true),
            homeDirectory.appendingPathComponent(".codex-shared/session-pool/archived_sessions", isDirectory: true),
        ]
    }
}

struct ClaudeTokenUsageSourceReader: AITokenUsageSourceReading {
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

        var seenStableIDs: Set<String> = []
        var parsedEvents: [AITokenUsageEvent] = []

        for fileURL in existingProjectRoots.flatMap({ jsonlFiles(in: $0) }) {
            parsedEvents.append(
                contentsOf: tokenEvents(
                    inProjectFile: fileURL,
                    since: startDate,
                    seenStableIDs: &seenStableIDs
                )
            )
        }

        for fileURL in existingCaptureRoots.flatMap({ captureFiles(in: $0) }) {
            if let event = tokenEvent(
                inCaptureFile: fileURL,
                since: startDate,
                seenStableIDs: &seenStableIDs
            ) {
                parsedEvents.append(event)
            }
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

    private func jsonlFiles(in root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
    }

    private func captureFiles(in root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasSuffix(".response.json") }
    }

    private func tokenEvents(
        inProjectFile fileURL: URL,
        since startDate: Date,
        seenStableIDs: inout Set<String>
    ) -> [AITokenUsageEvent] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                claudeProjectEvent(
                    from: String(line),
                    fileURL: fileURL,
                    since: startDate,
                    seenStableIDs: &seenStableIDs
                )
            }
    }

    private func claudeProjectEvent(
        from line: String,
        fileURL: URL,
        since startDate: Date,
        seenStableIDs: inout Set<String>
    ) -> AITokenUsageEvent? {
        guard let object = jsonObject(from: line),
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let timestampString = stringValue(object["timestamp"]),
              let timestamp = ISO8601DateFormatter.notchFlowDate(from: timestampString),
              timestamp >= startDate
        else {
            return nil
        }

        let sessionID = stringValue(object["sessionId"]) ?? fileURL.deletingPathExtension().lastPathComponent
        let messageID = stringValue(message["id"]) ?? stringValue(object["uuid"]) ?? timestampString
        let stableID = "claude-project:\(sessionID):\(messageID)"
        guard seenStableIDs.insert(stableID).inserted else {
            return nil
        }

        let breakdown = claudeBreakdown(from: usage)
        guard breakdown.totalTokens > 0 else {
            return nil
        }

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
        since startDate: Date,
        seenStableIDs: inout Set<String>
    ) -> AITokenUsageEvent? {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = object["usage"] as? [String: Any]
        else {
            return nil
        }

        let timestamp = fileModificationDate(fileURL) ?? Date.distantPast
        guard timestamp >= startDate else {
            return nil
        }

        let stableID = "claude-capture:\(stringValue(object["id"]) ?? fileURL.path)"
        guard seenStableIDs.insert(stableID).inserted else {
            return nil
        }

        let breakdown = claudeBreakdown(from: usage)
        guard breakdown.totalTokens > 0 else {
            return nil
        }

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

    static func defaultProjectDirectories(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true),
        ]
    }

    static func defaultCaptureDirectories(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".claude/cc-capture", isDirectory: true),
        ]
    }
}

struct AITokenUsagePresenceSourceReader: AITokenUsageSourceReading {
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

    private let settings: AppSettings
    private let readers: [AITokenUsageSourceReading]
    private let calendar: Calendar
    private let refreshInterval: TimeInterval = 5 * 60
    private let historyDays = 30
    private var refreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings,
        readers: [AITokenUsageSourceReading]? = nil,
        calendar: Calendar = .current
    ) {
        self.settings = settings
        self.calendar = calendar
        self.readers = readers ?? Self.defaultReaders()
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

    func start() {
        bindSettings()

        if settings.aiTokenUsageEnabled {
            scheduleRefreshTimer()
            refresh()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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
            summary = .empty
            statusMessage = "AI 用量统计已关闭"
            return
        }

        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        statusMessage = "正在读取本机 AI 用量..."

        let startDate = calendar.date(
            byAdding: .day,
            value: -(historyDays - 1),
            to: calendar.startOfDay(for: Date())
        ) ?? Date(timeIntervalSinceNow: -TimeInterval(historyDays * 24 * 60 * 60))

        let results = readers.map { $0.read(since: startDate) }
        let nextSummary = AITokenUsageAggregator.summary(
            from: results,
            calendar: calendar,
            refreshedAt: Date()
        )

        summary = nextSummary
        statusMessage = nextSummary.todayTotal(calendar: calendar) > 0
            ? "已刷新今日 AI token 用量"
            : "暂无今日 AI token 记录"
        isRefreshing = false
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
                    self.summary = .empty
                    self.statusMessage = "AI 用量统计已关闭"
                }
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

private func jsonObject(from line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }

    return object
}

private func stringValue(_ value: Any?) -> String? {
    value as? String
}

private func intValue(_ value: Any?) -> Int {
    switch value {
    case let int as Int:
        return int
    case let double as Double:
        return Int(double)
    case let number as NSNumber:
        return number.intValue
    case let string as String:
        return Int(string) ?? 0
    default:
        return 0
    }
}
