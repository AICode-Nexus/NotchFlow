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
            computedTotal: 1_200
        )
        try fixture.insert(
            id: "claude-request",
            model: "claude-opus-4-6",
            startedAtMilliseconds: 1_750_000_000_000,
            input: 9_000,
            output: 900,
            computedTotal: 9_900
        )

        let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url)
            .read(since: .distantPast)

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

    func testReaderUsesUnixMillisecondsAndFiltersRowsBeforeStartDate() throws {
        let fixture = try ZCodeUsageDatabaseFixture()
        defer { fixture.cleanup() }
        let start = Date(timeIntervalSince1970: 1_750_000_000)

        try fixture.insert(
            id: "before",
            model: "glm-5",
            startedAtMilliseconds: 1_749_999_999_999,
            input: 10,
            output: 1,
            computedTotal: 11
        )
        try fixture.insert(
            id: "inside",
            model: "glm-5.2",
            startedAtMilliseconds: 1_750_000_000_001,
            input: 20,
            output: 2,
            computedTotal: 22
        )

        let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url)
            .read(since: start)

        XCTAssertEqual(result.events.map(\.stableID), ["zcode-glm:inside"])
        XCTAssertEqual(
            result.events.first?.timestamp,
            Date(timeIntervalSince1970: 1_750_000_000.001)
        )
    }

    func testReaderCountsPositiveUsageRegardlessOfCompletionStatusAndIgnoresZeroUsage() throws {
        let fixture = try ZCodeUsageDatabaseFixture()
        defer { fixture.cleanup() }

        try fixture.insert(
            id: "cancelled-positive",
            model: "glm-5.2",
            startedAtMilliseconds: 1_750_000_000_000,
            input: 7,
            output: 3,
            computedTotal: 10,
            status: "cancelled"
        )
        try fixture.insert(
            id: "error-zero",
            model: "glm-5.2",
            startedAtMilliseconds: 1_750_000_000_001,
            computedTotal: 0,
            status: "error"
        )

        let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url)
            .read(since: .distantPast)

        XCTAssertEqual(result.events.map(\.stableID), ["zcode-glm:cancelled-positive"])
    }

    func testGLMEventsParticipateInSevenFourteenAndThirtyDayWindows() throws {
        let fixture = try ZCodeUsageDatabaseFixture()
        defer { fixture.cleanup() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z")
        )
        let startOfToday = calendar.startOfDay(for: end)

        func milliseconds(daysAgo: Int) -> Int64 {
            let date = calendar.date(
                byAdding: .day,
                value: -daysAgo,
                to: startOfToday
            )!
            return Int64(date.timeIntervalSince1970 * 1_000)
        }

        try fixture.insert(
            id: "today",
            model: "glm-5.2",
            startedAtMilliseconds: milliseconds(daysAgo: 0),
            input: 1,
            computedTotal: 1
        )
        try fixture.insert(
            id: "seven",
            model: "glm-5.2",
            startedAtMilliseconds: milliseconds(daysAgo: 6),
            input: 2,
            computedTotal: 2
        )
        try fixture.insert(
            id: "fourteen",
            model: "glm-5.2",
            startedAtMilliseconds: milliseconds(daysAgo: 13),
            input: 3,
            computedTotal: 3
        )
        try fixture.insert(
            id: "thirty",
            model: "glm-5.2",
            startedAtMilliseconds: milliseconds(daysAgo: 29),
            input: 4,
            computedTotal: 4
        )
        try fixture.insert(
            id: "outside",
            model: "glm-5.2",
            startedAtMilliseconds: milliseconds(daysAgo: 30),
            input: 100,
            computedTotal: 100
        )

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
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(
            ZCodeGLMTokenUsageSourceReader(databaseURL: missingURL)
                .read(since: .distantPast)
                .status
                .state,
            .missing
        )

        let emptyFixture = try ZCodeUsageDatabaseFixture()
        defer { emptyFixture.cleanup() }
        XCTAssertEqual(
            ZCodeGLMTokenUsageSourceReader(databaseURL: emptyFixture.url)
                .read(since: .distantPast)
                .status
                .state,
            .detected
        )

        let unsupported = try ZCodeUsageDatabaseFixture(createProductionSchema: false)
        defer { unsupported.cleanup() }
        try unsupported.execute("CREATE TABLE model_usage (id TEXT PRIMARY KEY)")
        XCTAssertEqual(
            ZCodeGLMTokenUsageSourceReader(databaseURL: unsupported.url)
                .read(since: .distantPast)
                .status
                .state,
            .unsupported
        )

        let corruptDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlow-Corrupt-ZCode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: corruptDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: corruptDirectory) }
        let corruptURL = corruptDirectory.appendingPathComponent("db.sqlite")
        try Data("not sqlite".utf8).write(to: corruptURL)
        XCTAssertEqual(
            ZCodeGLMTokenUsageSourceReader(databaseURL: corruptURL)
                .read(since: .distantPast)
                .status
                .state,
            .unreadable
        )
    }

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

        let result = ZCodeGLMTokenUsageSourceReader(databaseURL: fixture.url)
            .read(since: .distantPast)

        XCTAssertEqual(result.events.map(\.stableID), ["zcode-glm:valid"])
    }

    func testLiveDefaultDatabaseMatchesDirectTodayMetadataQuery() throws {
        guard ProcessInfo.processInfo.environment["NOTCHFLOW_VERIFY_LIVE_ZCODE"] == "1" else {
            throw XCTSkip("Live ZCode reconciliation is opt-in")
        }

        let url = ZCodeGLMTokenUsageSourceReader.defaultDatabaseURL()
        let start = Calendar.current.startOfDay(for: Date())
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

    private func directGLMTotal(
        databaseURL: URL,
        sinceMilliseconds: Int64
    ) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK,
            let database
        else {
            throw SQLiteFixtureError.openFailed
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = """
        SELECT COALESCE(SUM(computed_total_tokens), 0)
        FROM model_usage
        WHERE lower(model_id) LIKE 'glm%'
          AND computed_total_tokens > 0
          AND started_at >= ?
        """
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
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
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
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
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
