import Foundation
@testable import NotchFlow
import XCTest

final class AITokenUsageReaderTests: XCTestCase {
    func testCodexReaderAggregatesTokenCountEventsByLocalDayAndIgnoresMalformedLines() throws {
        let fixture = try TemporaryFixture()
        let rolloutDirectory = fixture.url
            .appendingPathComponent(".codex")
            .appendingPathComponent("sessions")
            .appendingPathComponent("2026")
            .appendingPathComponent("06")
            .appendingPathComponent("12")
        try FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)

        try """
        not-json
        {"timestamp":"2026-06-12T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":15}}}}
        {"timestamp":"2026-06-12T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":50,"total_tokens":150}}}}
        {"timestamp":"2026-06-12T03:00:00Z","type":"response_item","payload":{"type":"message"}}
        {"timestamp":"2026-06-12T04:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":1,"total_tokens":10}}}}
        """
        .write(
            to: rolloutDirectory.appendingPathComponent("rollout-test.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let reader = CodexTokenUsageSourceReader(rootDirectories: [
            fixture.url.appendingPathComponent(".codex").appendingPathComponent("sessions"),
        ])
        let result = reader.read(since: Date(timeIntervalSince1970: 0))
        let summary = AITokenUsageAggregator.summary(from: [result], calendar: utcCalendar)

        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.status.state, .available)
        XCTAssertEqual(summary.todayTotal(on: date("2026-06-12T12:00:00Z"), calendar: utcCalendar), 25)
        XCTAssertEqual(summary.sourceSummaries.first?.breakdown.inputTokens, 17)
        XCTAssertEqual(summary.sourceSummaries.first?.breakdown.cachedInputTokens, 6)
        XCTAssertEqual(summary.sourceSummaries.first?.breakdown.outputTokens, 8)
        XCTAssertEqual(summary.sourceSummaries.first?.breakdown.reasoningOutputTokens, 3)
    }

    func testClaudeReaderDeduplicatesMessagesAndIncludesCacheTokens() throws {
        let fixture = try TemporaryFixture()
        let projectDirectory = fixture.url
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
            .appendingPathComponent("sample-project")
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-1","model":"claude-test","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":5}}}
        {"timestamp":"2026-06-12T01:00:01Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-1","model":"claude-test","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":5}}}
        {"timestamp":"2026-06-12T02:00:00Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-2","model":"claude-test","usage":{"input_tokens":3,"cache_creation_input_tokens":4,"cache_read_input_tokens":5,"output_tokens":6}}}
        """
        .write(
            to: projectDirectory.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let reader = ClaudeTokenUsageSourceReader(
            projectDirectories: [fixture.url.appendingPathComponent(".claude").appendingPathComponent("projects")],
            captureDirectories: []
        )
        let result = reader.read(since: Date(timeIntervalSince1970: 0))
        let summary = AITokenUsageAggregator.summary(from: [result], calendar: utcCalendar)

        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(summary.todayTotal(on: date("2026-06-12T12:00:00Z"), calendar: utcCalendar), 83)
        XCTAssertEqual(summary.sourceSummaries.first?.breakdown.inputTokens, 13)
        XCTAssertEqual(summary.sourceSummaries.first?.breakdown.cacheCreationInputTokens, 24)
        XCTAssertEqual(summary.sourceSummaries.first?.breakdown.cacheReadInputTokens, 35)
        XCTAssertEqual(summary.sourceSummaries.first?.breakdown.outputTokens, 11)
    }

    func testReadersReportMissingDirectoriesWithoutThrowing() throws {
        let fixture = try TemporaryFixture()
        let missing = fixture.url.appendingPathComponent("missing")

        let codex = CodexTokenUsageSourceReader(rootDirectories: [missing])
            .read(since: Date(timeIntervalSince1970: 0))
        let claude = ClaudeTokenUsageSourceReader(projectDirectories: [missing], captureDirectories: [])
            .read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(codex.status.state, .missing)
        XCTAssertEqual(codex.events, [])
        XCTAssertEqual(claude.status.state, .missing)
        XCTAssertEqual(claude.events, [])
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ isoString: String) -> Date {
        ISO8601DateFormatter.notchFlowInternetDate.date(from: isoString)!
    }
}

private final class TemporaryFixture {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchFlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
