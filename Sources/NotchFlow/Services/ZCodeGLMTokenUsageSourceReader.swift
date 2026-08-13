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
            if let database {
                sqlite3_close(database)
            }
            return result(.unreadable, "无法读取 ZCode 本地用量数据库", [])
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        switch schemaState(database) {
        case .supported:
            break
        case .unsupported:
            return result(.unsupported, "ZCode 用量数据库结构暂不支持", [])
        case .unreadable:
            return result(.unreadable, "无法读取 ZCode 本地用量数据库", [])
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
                guard let event = event(from: statement) else {
                    continue
                }
                events.append(event)
            case SQLITE_DONE:
                return result(
                    events.isEmpty ? .detected : .available,
                    events.isEmpty
                        ? "已检测到 ZCode，暂无 GLM token 记录"
                        : "已读取 ZCode GLM token 记录",
                    events
                )
            default:
                return result(.unreadable, "无法读取 ZCode 本地用量数据库", [])
            }
        }
    }

    static func defaultDatabaseURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent(".zcode/cli/db/db.sqlite")
    }

    private func event(from statement: OpaquePointer) -> AITokenUsageEvent? {
        guard let id = text(statement, column: 0),
              let model = text(statement, column: 1)
        else {
            return nil
        }

        guard let startedAt = nonNegativeInt64(statement, column: 2),
              let input = nonNegativeInt(statement, column: 3),
              let output = nonNegativeInt(statement, column: 4),
              let reasoning = nonNegativeInt(statement, column: 5),
              let cacheCreation = nonNegativeInt(statement, column: 6),
              let cacheRead = nonNegativeInt(statement, column: 7),
              let computedTotal = nonNegativeInt(statement, column: 8),
              computedTotal > 0
        else {
            return nil
        }

        return AITokenUsageEvent(
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
    }

    private func schemaState(_ database: OpaquePointer) -> SchemaState {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA table_info(model_usage)",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
            let statement
        else {
            return .unreadable
        }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let name = text(statement, column: 1) {
                    columns.insert(name)
                }
            case SQLITE_DONE:
                return Self.requiredColumns.isSubset(of: columns)
                    ? .supported
                    : .unsupported
            default:
                return .unreadable
            }
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: bytes)
    }

    private func nonNegativeInt64(
        _ statement: OpaquePointer,
        column: Int32
    ) -> Int64? {
        guard sqlite3_column_type(statement, column) == SQLITE_INTEGER else {
            return nil
        }
        let value = sqlite3_column_int64(statement, column)
        return value >= 0 ? value : nil
    }

    private func nonNegativeInt(
        _ statement: OpaquePointer,
        column: Int32
    ) -> Int? {
        guard let value = nonNegativeInt64(statement, column: column),
              value <= Int64(Int.max)
        else {
            return nil
        }
        return Int(value)
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
        "id",
        "model_id",
        "started_at",
        "input_tokens",
        "output_tokens",
        "reasoning_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
        "computed_total_tokens",
    ]

    private enum SchemaState {
        case supported
        case unsupported
        case unreadable
    }
}
