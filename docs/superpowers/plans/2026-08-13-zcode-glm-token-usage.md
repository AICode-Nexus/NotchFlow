# ZCode GLM Token Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read GLM token usage from ZCode's local SQLite database, include it in NotchFlow AI usage summaries, and pin Codex plus GLM in the notch source strip.

**Architecture:** Add a focused read-only `ZCodeGLMTokenUsageSourceReader` backed by system SQLite3 and map `model_usage` rows into the existing `AITokenUsageEvent` model. Keep aggregation unchanged, add a pure summary projection for the fixed notch sources, and leave ZCode out of storage cleanup. Build the behavior test-first with temporary SQLite fixtures.

**Tech Stack:** Swift 6, Foundation, system SQLite3, XCTest, SwiftUI, Swift Package Manager, Xcode macOS application project.

---

## File map

- Create `Sources/NotchFlow/Services/ZCodeGLMTokenUsageSourceReader.swift`: read-only SQLite schema validation, query, event mapping, and status reporting.
- Modify `Sources/NotchFlow/Services/AITokenUsageService.swift`: add `.glm`, wire the default reader, and add the pure fixed-source notch projection.
- Modify `Sources/NotchFlow/UI/NotchPanelView.swift`: render the fixed Codex/GLM projection.
- Modify `Sources/NotchFlow/UI/SettingsView.swift`: mention ZCode in the local metadata privacy explanation.
- Modify `Package.swift`: explicitly link system SQLite3 for SwiftPM.
- Modify `scripts/generate_xcodeproj.rb`: link SQLite3 in generated Xcode projects.
- Regenerate `NotchFlow.xcodeproj/project.pbxproj`: include the new source file and SQLite linker flag.
- Create `Tests/NotchFlowTests/ZCodeGLMTokenUsageReaderTests.swift`: real temporary SQLite fixtures and reader regression coverage.
- Modify `Tests/NotchFlowTests/AITokenUsageReaderTests.swift`: fixed notch-source projection and default-reader coverage.
- Modify `README.md` and `CHANGELOG.md`: describe ZCode/GLM local usage support.

### Task 1: Add the GLM source and read the ZCode happy path

**Files:**
- Create: `Tests/NotchFlowTests/ZCodeGLMTokenUsageReaderTests.swift`
- Create: `Sources/NotchFlow/Services/ZCodeGLMTokenUsageSourceReader.swift`
- Modify: `Sources/NotchFlow/Services/AITokenUsageService.swift:4-40`
- Modify: `Package.swift:12-28`
- Modify: `scripts/generate_xcodeproj.rb:93-111`
- Regenerate: `NotchFlow.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing happy-path test with a real SQLite fixture**

Create a test fixture that opens a temporary database with SQLite3, creates the production-shaped table, and inserts rows using prepared SQL. The first test must include GLM and non-GLM rows and verify exact breakdown mapping:

```swift
import Foundation
import SQLite3
@testable import NotchFlow
import XCTest

final class ZCodeGLMTokenUsageReaderTests: XCTestCase {
    func testReaderIncludesOnlyGLMRowsAndUsesComputedTotalWithoutAddingCacheAgain() throws {
        let fixture = try ZCodeUsageDatabaseFixture()
        defer { fixture.cleanup() }

        try fixture.insert(
            id: "glm-request",
            model: "GLM-5.2",
            startedAtMilliseconds: 1_750_000_000_000,
            input: 1_000,
            output: 200,
            reasoning: 30,
            cacheCreation: 40,
            cacheRead: 700,
            computedTotal: 1_200,
            status: "completed"
        )
        try fixture.insert(
            id: "claude-request",
            model: "claude-opus-4-6",
            startedAtMilliseconds: 1_750_000_000_000,
            input: 9_000,
            output: 900,
            reasoning: 0,
            cacheCreation: 0,
            cacheRead: 0,
            computedTotal: 9_900,
            status: "completed"
        )

        let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url).read(since: .distantPast)

        XCTAssertEqual(result.sourceID, .glm)
        XCTAssertEqual(result.status.state, .available)
        let event = try XCTUnwrap(result.events.only)
        XCTAssertEqual(event.stableID, "zcode-glm:glm-request")
        XCTAssertEqual(event.model, "GLM-5.2")
        XCTAssertEqual(event.breakdown.inputTokens, 1_000)
        XCTAssertEqual(event.breakdown.outputTokens, 200)
        XCTAssertEqual(event.breakdown.reasoningOutputTokens, 30)
        XCTAssertEqual(event.breakdown.cacheCreationInputTokens, 40)
        XCTAssertEqual(event.breakdown.cacheReadInputTokens, 700)
        XCTAssertEqual(event.breakdown.totalTokens, 1_200)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

private enum SQLiteFixtureError: Error {
    case openFailed
    case prepareFailed
    case bindFailed
    case queryFailed
}

private final class ZCodeUsageDatabaseFixture {
    let directoryURL: URL
    let url: URL
    private var database: OpaquePointer?

    init(createProductionSchema: Bool = true) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlow-ZCode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        url = directoryURL.appendingPathComponent("db.sqlite")
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            throw SQLiteFixtureError.openFailed
        }
        if createProductionSchema {
            try execute(Self.productionSchema)
        }
    }

    func insert(
        id: String,
        model: String,
        startedAtMilliseconds: Int64,
        input: Int = 0,
        output: Int = 0,
        reasoning: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        computedTotal: Int,
        status: String = "completed"
    ) throws {
        let sql = """
        INSERT INTO model_usage (
            id, model_id, status, started_at, input_tokens, output_tokens,
            reasoning_tokens, cache_creation_input_tokens,
            cache_read_input_tokens, computed_total_tokens
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteFixtureError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, id, -1, transient) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, model, -1, transient) == SQLITE_OK,
              sqlite3_bind_text(statement, 3, status, -1, transient) == SQLITE_OK,
              sqlite3_bind_int64(statement, 4, startedAtMilliseconds) == SQLITE_OK,
              sqlite3_bind_int64(statement, 5, Int64(input)) == SQLITE_OK,
              sqlite3_bind_int64(statement, 6, Int64(output)) == SQLITE_OK,
              sqlite3_bind_int64(statement, 7, Int64(reasoning)) == SQLITE_OK,
              sqlite3_bind_int64(statement, 8, Int64(cacheCreation)) == SQLITE_OK,
              sqlite3_bind_int64(statement, 9, Int64(cacheRead)) == SQLITE_OK,
              sqlite3_bind_int64(statement, 10, Int64(computedTotal)) == SQLITE_OK
        else {
            throw SQLiteFixtureError.bindFailed
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteFixtureError.queryFailed
        }
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteFixtureError.queryFailed
        }
    }

    func cleanup() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static let productionSchema = """
    CREATE TABLE model_usage (
        id TEXT PRIMARY KEY,
        model_id TEXT NOT NULL,
        status TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        input_tokens INTEGER NOT NULL DEFAULT 0,
        output_tokens INTEGER NOT NULL DEFAULT 0,
        reasoning_tokens INTEGER NOT NULL DEFAULT 0,
        cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0,
        cache_read_input_tokens INTEGER NOT NULL DEFAULT 0,
        computed_total_tokens INTEGER NOT NULL DEFAULT 0
    )
    """
}
```

The fixture above declares every required production column and binds inserted values rather than interpolating them. Its schema mirrors the following production subset:

```sql
CREATE TABLE model_usage (
    id TEXT PRIMARY KEY,
    model_id TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at INTEGER NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    reasoning_tokens INTEGER NOT NULL DEFAULT 0,
    cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0,
    cache_read_input_tokens INTEGER NOT NULL DEFAULT 0,
    computed_total_tokens INTEGER NOT NULL DEFAULT 0
)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter ZCodeGLMTokenUsageReaderTests.testReaderIncludesOnlyGLMRowsAndUsesComputedTotalWithoutAddingCacheAgain
```

Expected: compilation fails because `ZCodeGLMTokenUsageSourceReader` and `AITokenUsageSourceID.glm` do not exist. This is the required RED result.

- [ ] **Step 3: Add `.glm` and implement the minimum read-only reader**

Add the source identifier beside Codex and Claude:

```swift
enum AITokenUsageSourceID: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex
    case glm
    case claude
    case cursor
    case windsurf
    case copilot
    case roo
    case cline
    case `continue`
    case openAI

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .glm: return "GLM"
        case .claude: return "Claude"
        case .cursor: return "Cursor"
        case .windsurf: return "Windsurf"
        case .copilot: return "Copilot"
        case .roo: return "Roo"
        case .cline: return "Cline"
        case .continue: return "Continue"
        case .openAI: return "ChatGPT / OpenAI"
        }
    }
}
```

Create `ZCodeGLMTokenUsageSourceReader` with this public shape and query:

```swift
import Foundation
import SQLite3

struct ZCodeGLMTokenUsageSourceReader: AITokenUsageSourceReading, @unchecked Sendable {
    let sourceID: AITokenUsageSourceID = .glm
    let databaseURL: URL
    private let fileManager: FileManager

    init(
        databaseURL: URL = Self.defaultDatabaseURL(),
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    func read(since startDate: Date) -> AITokenUsageSourceReadResult {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return result(.missing, "未找到 ZCode 本地用量数据库", [])
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            if let database { sqlite3_close(database) }
            return result(.unreadable, "无法读取 ZCode 本地用量数据库", [])
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        guard hasRequiredSchema(database) else {
            return result(.unsupported, "ZCode 用量数据库结构暂不支持", [])
        }

        let sql = """
        SELECT id, model_id, started_at, input_tokens, output_tokens,
               reasoning_tokens, cache_creation_input_tokens,
               cache_read_input_tokens, computed_total_tokens
        FROM model_usage
        WHERE lower(model_id) LIKE 'glm%'
          AND started_at >= ?
          AND computed_total_tokens > 0
        ORDER BY started_at ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return result(.unreadable, "无法读取 ZCode 本地用量数据库", [])
        }
        defer { sqlite3_finalize(statement) }

        let startMilliseconds = Int64(startDate.timeIntervalSince1970 * 1_000)
        guard sqlite3_bind_int64(statement, 1, startMilliseconds) == SQLITE_OK else {
            return result(.unreadable, "无法读取 ZCode 本地用量数据库", [])
        }

        var events: [AITokenUsageEvent] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let id = text(statement, column: 0),
                      let model = text(statement, column: 1)
                else {
                    continue
                }
                let startedAt = sqlite3_column_int64(statement, 2)
                let input = Int(sqlite3_column_int64(statement, 3))
                let output = Int(sqlite3_column_int64(statement, 4))
                let reasoning = Int(sqlite3_column_int64(statement, 5))
                let cacheCreation = Int(sqlite3_column_int64(statement, 6))
                let cacheRead = Int(sqlite3_column_int64(statement, 7))
                let computedTotal = Int(sqlite3_column_int64(statement, 8))

                events.append(
                    AITokenUsageEvent(
                        sourceID: sourceID,
                        timestamp: Date(timeIntervalSince1970: Double(startedAt) / 1_000),
                        breakdown: AITokenBreakdown(
                            inputTokens: input,
                            cacheCreationInputTokens: cacheCreation,
                            cacheReadInputTokens: cacheRead,
                            outputTokens: output,
                            reasoningOutputTokens: reasoning,
                            totalTokens: computedTotal
                        ),
                        model: model,
                        stableID: "zcode-glm:\(id)"
                    )
                )
            case SQLITE_DONE:
                return result(
                    events.isEmpty ? .detected : .available,
                    events.isEmpty ? "已检测到 ZCode，暂无 GLM token 记录" : "已读取 ZCode GLM token 记录",
                    events
                )
            default:
                return result(.unreadable, "无法读取 ZCode 本地用量数据库", [])
            }
        }
    }

    private func hasRequiredSchema(_ database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(model_usage)", -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = text(statement, column: 1) {
                columns.insert(name)
            }
        }
        return Self.requiredColumns.isSubset(of: columns)
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: bytes)
    }

    private func result(
        _ state: AITokenUsageSourceState,
        _ message: String,
        _ events: [AITokenUsageEvent]
    ) -> AITokenUsageSourceReadResult {
        AITokenUsageSourceReadResult(
            sourceID: sourceID,
            status: AITokenUsageSourceStatus(id: sourceID, state: state, message: message),
            events: events
        )
    }

    private static let requiredColumns: Set<String> = [
        "id", "model_id", "started_at", "input_tokens", "output_tokens",
        "reasoning_tokens", "cache_creation_input_tokens",
        "cache_read_input_tokens", "computed_total_tokens",
    ]

    static func defaultDatabaseURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent(".zcode/cli/db/db.sqlite")
    }
}
```

Implement `hasRequiredSchema` with `PRAGMA table_info(model_usage)` and require exactly these names: `id`, `model_id`, `started_at`, `input_tokens`, `output_tokens`, `reasoning_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `computed_total_tokens`. Map total with the explicit initializer argument so cache values are not added twice:

```swift
AITokenBreakdown(
    inputTokens: input,
    cacheCreationInputTokens: cacheCreation,
    cacheReadInputTokens: cacheRead,
    outputTokens: output,
    reasoningOutputTokens: reasoning,
    totalTokens: computedTotal
)
```

Return generic status text only; never include raw SQLite errors, row contents, paths, or query text in the user-facing message.

- [ ] **Step 4: Link SQLite3 in both build systems and regenerate the project**

Add to the NotchFlow executable target in `Package.swift`:

```swift
.linkedLibrary("sqlite3"),
```

Add to every generated Xcode build configuration in `scripts/generate_xcodeproj.rb`:

```ruby
settings['OTHER_LDFLAGS'] = '$(inherited) -lsqlite3'
```

Regenerate:

```bash
ruby scripts/generate_xcodeproj.rb
```

Verify the generated project contains `ZCodeGLMTokenUsageSourceReader.swift` and `-lsqlite3`:

```bash
rg -n 'ZCodeGLMTokenUsageSourceReader|lsqlite3' NotchFlow.xcodeproj/project.pbxproj
```

Expected: both patterns are present.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
swift test --filter ZCodeGLMTokenUsageReaderTests.testReaderIncludesOnlyGLMRowsAndUsesComputedTotalWithoutAddingCacheAgain
```

Expected: 1 test passes with 0 failures.

- [ ] **Step 6: Commit Task 1**

```bash
git add Package.swift scripts/generate_xcodeproj.rb NotchFlow.xcodeproj/project.pbxproj Sources/NotchFlow/Services/AITokenUsageService.swift Sources/NotchFlow/Services/ZCodeGLMTokenUsageSourceReader.swift Tests/NotchFlowTests/ZCodeGLMTokenUsageReaderTests.swift
git commit -m "feat: read GLM usage from ZCode"
```

### Task 2: Cover time windows, statuses, and malformed data

**Files:**
- Modify: `Tests/NotchFlowTests/ZCodeGLMTokenUsageReaderTests.swift`
- Modify: `Sources/NotchFlow/Services/ZCodeGLMTokenUsageSourceReader.swift`

- [ ] **Step 1: Add failing behavior tests**

Add separate tests with explicit assertions:

```swift
func testReaderUsesUnixMillisecondsAndFiltersRowsBeforeStartDate() throws {
    let fixture = try ZCodeUsageDatabaseFixture()
    defer { fixture.cleanup() }
    let start = Date(timeIntervalSince1970: 1_750_000_000)
    try fixture.insert(id: "before", model: "glm-5", startedAtMilliseconds: 1_749_999_999_999, input: 10, output: 1, computedTotal: 11)
    try fixture.insert(id: "inside", model: "glm-5.2", startedAtMilliseconds: 1_750_000_000_001, input: 20, output: 2, computedTotal: 22)

    let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url).read(since: start)

    XCTAssertEqual(result.events.map(\.stableID), ["zcode-glm:inside"])
    XCTAssertEqual(result.events.first?.timestamp, Date(timeIntervalSince1970: 1_750_000_000.001))
}

func testReaderCountsPositiveUsageRegardlessOfCompletionStatusAndIgnoresZeroUsage() throws {
    let fixture = try ZCodeUsageDatabaseFixture()
    defer { fixture.cleanup() }
    try fixture.insert(id: "cancelled-positive", model: "glm-5.2", startedAtMilliseconds: 1_750_000_000_000, input: 7, output: 3, computedTotal: 10, status: "cancelled")
    try fixture.insert(id: "error-zero", model: "glm-5.2", startedAtMilliseconds: 1_750_000_000_001, input: 0, output: 0, computedTotal: 0, status: "error")

    let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url).read(since: .distantPast)

    XCTAssertEqual(result.events.map(\.stableID), ["zcode-glm:cancelled-positive"])
}

func testGLMEventsParticipateInSevenFourteenAndThirtyDayWindows() throws {
    let fixture = try ZCodeUsageDatabaseFixture()
    defer { fixture.cleanup() }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let end = ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z")!
    let startOfToday = calendar.startOfDay(for: end)

    func milliseconds(daysAgo: Int) -> Int64 {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)!
        return Int64(date.timeIntervalSince1970 * 1_000)
    }

    try fixture.insert(id: "today", model: "glm-5.2", startedAtMilliseconds: milliseconds(daysAgo: 0), input: 1, computedTotal: 1)
    try fixture.insert(id: "seven", model: "glm-5.2", startedAtMilliseconds: milliseconds(daysAgo: 6), input: 2, computedTotal: 2)
    try fixture.insert(id: "fourteen", model: "glm-5.2", startedAtMilliseconds: milliseconds(daysAgo: 13), input: 3, computedTotal: 3)
    try fixture.insert(id: "thirty", model: "glm-5.2", startedAtMilliseconds: milliseconds(daysAgo: 29), input: 4, computedTotal: 4)
    try fixture.insert(id: "outside", model: "glm-5.2", startedAtMilliseconds: milliseconds(daysAgo: 30), input: 100, computedTotal: 100)

    let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url).read(
        since: calendar.date(byAdding: .day, value: -29, to: startOfToday)!
    )
    let summary = AITokenUsageAggregator.summary(from: [result], calendar: calendar)

    XCTAssertEqual(summary.todayTotal(on: end, calendar: calendar), 1)
    XCTAssertEqual(summary.totalForLastDays(7, endingAt: end, calendar: calendar), 3)
    XCTAssertEqual(summary.totalForLastDays(14, endingAt: end, calendar: calendar), 6)
    XCTAssertEqual(summary.totalForLastDays(30, endingAt: end, calendar: calendar), 10)
}

func testReaderReportsMissingDetectedUnsupportedAndUnreadableStates() throws {
    let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    XCTAssertEqual(ZCodeGLMTokenUsageSourceReader(databaseURL: missingURL).read(since: .distantPast).status.state, .missing)

    let emptyFixture = try ZCodeUsageDatabaseFixture()
    defer { emptyFixture.cleanup() }
    XCTAssertEqual(ZCodeGLMTokenUsageSourceReader(databaseURL: emptyFixture.url).read(since: .distantPast).status.state, .detected)

    let unsupported = try ZCodeUsageDatabaseFixture(createProductionSchema: false)
    defer { unsupported.cleanup() }
    try unsupported.execute("CREATE TABLE model_usage (id TEXT PRIMARY KEY)")
    XCTAssertEqual(ZCodeGLMTokenUsageSourceReader(databaseURL: unsupported.url).read(since: .distantPast).status.state, .unsupported)

    let corruptDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NotchFlow-Corrupt-ZCode-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: corruptDirectory) }
    let corruptURL = corruptDirectory.appendingPathComponent("db.sqlite")
    try Data("not sqlite".utf8).write(to: corruptURL)
    XCTAssertEqual(ZCodeGLMTokenUsageSourceReader(databaseURL: corruptURL).read(since: .distantPast).status.state, .unreadable)
}
```

Add this malformed-row test so row-level corruption cannot poison the source:

```swift
func testReaderSkipsRowsWithNegativeTokenValues() throws {
    let fixture = try ZCodeUsageDatabaseFixture()
    defer { fixture.cleanup() }
    try fixture.insert(
        id: "negative",
        model: "glm-5.2",
        startedAtMilliseconds: 1_750_000_000_000,
        input: -1,
        output: 5,
        computedTotal: 4
    )
    try fixture.insert(
        id: "valid",
        model: "glm-5.2",
        startedAtMilliseconds: 1_750_000_000_001,
        input: 7,
        output: 3,
        computedTotal: 10
    )

    let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url).read(since: .distantPast)

    XCTAssertEqual(result.events.map(\.stableID), ["zcode-glm:valid"])
}
```

- [ ] **Step 2: Run the test class and verify RED**

Run:

```bash
swift test --filter ZCodeGLMTokenUsageReaderTests
```

Expected: at least the malformed/corrupt database behavior test fails because the minimal implementation does not yet distinguish every state or validate every integer.

- [ ] **Step 3: Implement the complete error and conversion behavior**

Add checked helpers:

```swift
private func nonNegativeInt(_ statement: OpaquePointer, column: Int32) -> Int? {
    guard sqlite3_column_type(statement, column) == SQLITE_INTEGER else { return nil }
    let value = sqlite3_column_int64(statement, column)
    guard value >= 0, value <= Int64(Int.max) else { return nil }
    return Int(value)
}

private func text(_ statement: OpaquePointer, column: Int32) -> String? {
    guard let bytes = sqlite3_column_text(statement, column) else { return nil }
    return String(cString: bytes)
}
```

Differentiate prepare/step failures from compatible empty data. A failed schema PRAGMA caused by `SQLITE_NOTADB`, permission errors, or busy timeout returns `.unreadable`; a successful PRAGMA with missing table/columns returns `.unsupported`. If any row has a missing/negative/overflow token or timestamp, skip only that row.

- [ ] **Step 4: Run the reader and existing aggregation tests**

Run:

```bash
swift test --filter ZCodeGLMTokenUsageReaderTests
swift test --filter AITokenUsageReaderTests
```

Expected: all focused tests pass with 0 failures.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/NotchFlow/Services/ZCodeGLMTokenUsageSourceReader.swift Tests/NotchFlowTests/ZCodeGLMTokenUsageReaderTests.swift
git commit -m "test: cover ZCode GLM usage edge cases"
```

### Task 3: Wire GLM into refresh and pin the notch sources

**Files:**
- Modify: `Tests/NotchFlowTests/AITokenUsageReaderTests.swift`
- Modify: `Sources/NotchFlow/Services/AITokenUsageService.swift:379-430,1458-1470`
- Modify: `Sources/NotchFlow/UI/NotchPanelView.swift:1217-1240`

- [ ] **Step 1: Write failing fixed-source projection tests**

Add tests that build a summary containing Codex, Claude, and GLM events on the same day:

```swift
func testNotchSourceSummariesAlwaysReturnCodexAndGLMInThatOrder() {
    let day = Date(timeIntervalSince1970: 1_750_000_000)
    let summary = AITokenUsageAggregator.summary(
        from: [
            result(.codex, day, 10),
            result(.claude, day, 9_000),
            result(.glm, day, 20),
        ],
        calendar: utcCalendar
    )

    let sources = summary.notchSourceSummaries(on: day, calendar: utcCalendar)

    XCTAssertEqual(sources.map(\.id), [.codex, .glm])
    XCTAssertEqual(sources.map(\.breakdown.totalTokens), [10, 20])
    XCTAssertEqual(summary.todayTotal(on: day, calendar: utcCalendar), 9_030)
}

func testNotchSourceSummariesIncludeZeroValuesWhenTodayHasNoRows() {
    let sources = AITokenUsageSummary.empty.notchSourceSummaries(
        on: Date(timeIntervalSince1970: 1_750_000_000),
        calendar: utcCalendar
    )

    XCTAssertEqual(sources.map(\.id), [.codex, .glm])
    XCTAssertEqual(sources.map(\.breakdown.totalTokens), [0, 0])
}
```

Add a default-reader test:

```swift
func testDefaultReadersIncludeZCodeGLMReader() {
    let readers = AITokenUsageService.defaultReaders(homeDirectory: URL(fileURLWithPath: "/tmp/notchflow-home"))
    XCTAssertEqual(readers.filter { $0.sourceID == .glm }.count, 1)
}

private func result(
    _ sourceID: AITokenUsageSourceID,
    _ timestamp: Date,
    _ totalTokens: Int
) -> AITokenUsageSourceReadResult {
    AITokenUsageSourceReadResult(
        sourceID: sourceID,
        status: AITokenUsageSourceStatus(id: sourceID, state: .available, message: "test"),
        events: [
            AITokenUsageEvent(
                sourceID: sourceID,
                timestamp: timestamp,
                breakdown: AITokenBreakdown(totalTokens: totalTokens),
                model: nil,
                stableID: "\(sourceID.rawValue)-\(totalTokens)"
            ),
        ]
    )
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --filter AITokenUsageReaderTests
```

Expected: compilation fails because `notchSourceSummaries` is missing and the default readers do not contain `.glm`.

- [ ] **Step 3: Implement the fixed-source projection and default wiring**

Add this pure method to `AITokenUsageSummary`:

```swift
func notchSourceSummaries(
    on date: Date = Date(),
    calendar: Calendar = .current
) -> [AITokenUsageSourceSummary] {
    let todayBySource = Dictionary(
        uniqueKeysWithValues: sourceSummaries(on: date, calendar: calendar).map { ($0.id, $0.breakdown) }
    )
    return [AITokenUsageSourceID.codex, .glm].map { sourceID in
        AITokenUsageSourceSummary(
            id: sourceID,
            breakdown: todayBySource[sourceID] ?? .zero
        )
    }
}
```

Insert the ZCode reader immediately after Codex in `defaultReaders`:

```swift
ZCodeGLMTokenUsageSourceReader(
    databaseURL: ZCodeGLMTokenUsageSourceReader.defaultDatabaseURL(homeDirectory: homeDirectory)
),
```

Do not add a `.glm` entry to `defaultStorageDirectories`.

- [ ] **Step 4: Update the notch view to use the fixed projection**

Replace the dynamic top-two loop:

```swift
ForEach(aiTokenUsage.summary.notchSourceSummaries(on: Date())) { source in
    HStack(spacing: 4) {
        Text(source.displayName)
            .font(panelFont(11, weight: .semibold))
            .lineLimit(1)

        Text(AITokenUsageFormatter.tokenCount(source.breakdown.totalTokens))
            .font(panelFont(11, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
    }
    .foregroundStyle(moduleSecondaryTextColor)
    .padding(.horizontal, 6)
    .frame(height: 22)
    .background(moduleTileBackgroundColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
}
```

Remove the `.prefix(2)` call. No layout change is needed because the projection always contains exactly two entries.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter AITokenUsageReaderTests
swift test --filter ZCodeGLMTokenUsageReaderTests
```

Expected: all focused tests pass with 0 failures.

- [ ] **Step 6: Commit Task 3**

```bash
git add Sources/NotchFlow/Services/AITokenUsageService.swift Sources/NotchFlow/UI/NotchPanelView.swift Tests/NotchFlowTests/AITokenUsageReaderTests.swift
git commit -m "feat: pin GLM usage in the notch"
```

### Task 4: Update privacy copy and documentation

**Files:**
- Modify: `Sources/NotchFlow/UI/SettingsView.swift:580-590`
- Modify: `README.md:24-36`
- Modify: `CHANGELOG.md:4-12`

- [ ] **Step 1: Add a failing copy regression assertion**

Add to `AITokenUsageReaderTests`:

```swift
func testAIUsagePrivacyCopyMentionsZCode() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let settings = try String(
        contentsOf: root.appendingPathComponent("Sources/NotchFlow/UI/SettingsView.swift"),
        encoding: .utf8
    )
    XCTAssertTrue(settings.contains("Codex、Claude、ZCode"))
}
```

- [ ] **Step 2: Run the assertion and verify RED**

Run:

```bash
swift test --filter AITokenUsageReaderTests.testAIUsagePrivacyCopyMentionsZCode
```

Expected: failure because current copy says only “Codex、Claude 等工具”.

- [ ] **Step 3: Update product and repository copy**

Use this Settings copy:

```text
开启后仅在本机读取 Codex、Claude、ZCode 等工具日志中的 usage/token 元数据，不读取对话正文，不上传网络。
```

Update the README feature bullet to include ZCode/GLM local usage, and add an Unreleased changelog bullet stating that GLM usage is read locally from ZCode and shown beside Codex in the notch. Do not change the cleanup confirmation: it must continue to name only Codex/Claude because ZCode is intentionally not cleanable.

- [ ] **Step 4: Verify copy test and diff hygiene**

Run:

```bash
swift test --filter AITokenUsageReaderTests.testAIUsagePrivacyCopyMentionsZCode
git diff --check
```

Expected: the test passes and `git diff --check` exits 0.

- [ ] **Step 5: Commit Task 4**

```bash
git add Sources/NotchFlow/UI/SettingsView.swift Tests/NotchFlowTests/AITokenUsageReaderTests.swift README.md CHANGELOG.md
git commit -m "docs: describe local ZCode GLM usage"
```

### Task 5: Full verification and local reconciliation

**Files:**
- No planned production edits; a review finding must be reproduced by a new test in the relevant test file before any correction.

- [ ] **Step 1: Check XcodeBuildMCP defaults**

Use `session_show_defaults` before any Xcode build action. If the configured toolset exposes a macOS build workflow, build the `NotchFlow` scheme through XcodeBuildMCP. If that workflow is unavailable, record that fact and use the existing shell fallback in Step 3.

- [ ] **Step 2: Run the complete Swift test suite**

Run:

```bash
swift test
```

Expected: all tests pass with 0 failures.

- [ ] **Step 3: Build the Release app**

Fallback command when the macOS XcodeBuildMCP workflow is unavailable:

```bash
xcodebuild -project NotchFlow.xcodeproj -scheme NotchFlow -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` and exit code 0.

- [ ] **Step 4: Reconcile against the live ZCode database without reading content**

Use SQLite CLI to calculate today's GLM total from metadata only:

```bash
sqlite3 "$HOME/.zcode/cli/db/db.sqlite" \
  "SELECT COALESCE(SUM(computed_total_tokens), 0) FROM model_usage WHERE lower(model_id) LIKE 'glm%' AND computed_total_tokens > 0 AND date(started_at / 1000, 'unixepoch', 'localtime') = date('now', 'localtime');"
```

Add this opt-in live reconciliation test to `ZCodeGLMTokenUsageReaderTests.swift` during Task 2:

```swift
func testLiveDefaultDatabaseMatchesDirectTodayMetadataQuery() throws {
    guard ProcessInfo.processInfo.environment["NOTCHFLOW_VERIFY_LIVE_ZCODE"] == "1" else {
        throw XCTSkip("Live ZCode reconciliation is opt-in")
    }

    let url = ZCodeGLMTokenUsageSourceReader.defaultDatabaseURL()
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: Date())
    let readerTotal = ZCodeGLMTokenUsageSourceReader(databaseURL: url)
        .read(since: start)
        .events
        .reduce(0) { $0 + $1.breakdown.totalTokens }
    let directTotal = try directGLMTotal(
        databaseURL: url,
        sinceMilliseconds: Int64(start.timeIntervalSince1970 * 1_000)
    )

    XCTAssertEqual(readerTotal, directTotal)
}

private func directGLMTotal(databaseURL: URL, sinceMilliseconds: Int64) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
          let database
    else {
        throw SQLiteFixtureError.openFailed
    }
    defer { sqlite3_close(database) }

    var statement: OpaquePointer?
    let sql = "SELECT COALESCE(SUM(computed_total_tokens), 0) FROM model_usage WHERE lower(model_id) LIKE 'glm%' AND computed_total_tokens > 0 AND started_at >= ?"
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
          let statement
    else {
        throw SQLiteFixtureError.prepareFailed
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_int64(statement, 1, sinceMilliseconds) == SQLITE_OK,
          sqlite3_step(statement) == SQLITE_ROW
    else {
        throw SQLiteFixtureError.queryFailed
    }
    return Int(sqlite3_column_int64(statement, 0))
}
```

Run it against the live database:

```bash
NOTCHFLOW_VERIFY_LIVE_ZCODE=1 swift test --filter ZCodeGLMTokenUsageReaderTests.testLiveDefaultDatabaseMatchesDirectTodayMetadataQuery
```

Expected: 1 test passes with 0 failures. The test queries only ID/model/time/token metadata and does not print model request payloads, messages, session titles, or workspace paths.

- [ ] **Step 5: Verify ZCode remains outside cleanup and review the final diff**

Run:

```bash
rg -n 'defaultStorageDirectories|ZCodeGLMTokenUsageSourceReader' Sources/NotchFlow/Services/AITokenUsageService.swift Sources/NotchFlow/Services/ZCodeGLMTokenUsageSourceReader.swift
git diff --check
git status --short
```

Expected: ZCode reader appears only in default readers; `defaultStorageDirectories` still creates only Codex and Claude entries; diff check exits 0; status contains only intended files.

- [ ] **Step 6: Request code review and address Critical/Important findings**

Review requirements:

```text
- SQLite connection is strictly read-only and always closed.
- Query selects only ID/model/time/token metadata.
- computed_total_tokens is not inflated by cache fields.
- GLM rows are not double-counted from Claude or rollout logs.
- ZCode is absent from destructive storage cleanup.
- Notch source order is always Codex then GLM, including zeros.
```

Fix every valid Critical or Important issue with a new failing test before changing production code, then rerun Steps 2–5.

- [ ] **Step 7: Commit any verification fixes**

If review required changes:

```bash
git add Package.swift scripts/generate_xcodeproj.rb NotchFlow.xcodeproj Sources Tests README.md CHANGELOG.md
git commit -m "fix: address ZCode GLM usage review"
```

If no files changed, do not create an empty commit.
