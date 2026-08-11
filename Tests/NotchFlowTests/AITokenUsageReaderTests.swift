import Foundation
@testable import NotchFlow
import XCTest

final class AITokenUsageReaderTests: XCTestCase {
    @MainActor
    func testRefreshReturnsBeforeSlowReadersFinish() async throws {
        let defaults = UserDefaults(suiteName: "NotchFlowTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "AITokenUsageEnabled")
        let settings = AppSettings(defaults: defaults)
        let service = AITokenUsageService(
            settings: settings,
            readers: [SlowAITokenUsageReader(delay: 0.25)],
            calendar: utcCalendar
        )

        let startedAt = Date()
        service.refresh()
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 0.05)
        XCTAssertTrue(service.isRefreshing)

        let deadline = Date().addingTimeInterval(1)
        while service.isRefreshing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(service.isRefreshing)
        XCTAssertEqual(service.summary.sourceStatuses.first?.state, .detected)
    }

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

    func testCodexReaderStreamsEntireLargeFileInsteadOfOnlyReadingTail() throws {
        let fixture = try TemporaryFixture()
        let rolloutDirectory = fixture.url
            .appendingPathComponent(".codex/sessions/2026/06/12", isDirectory: true)
        try FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)

        let earlyEvent = """
        {"timestamp":"2026-06-12T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":15},"total_token_usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":15}}}}
        """
        let unicodeLinePrefix = earlyEvent + "\n{\"type\":\"response_item\",\"payload\":\""
        let unicodePaddingCount = (1024 * 1024) - unicodeLinePrefix.utf8.count - 1
        let filler = "{\"type\":\"response_item\",\"payload\":\""
            + String(repeating: "a", count: unicodePaddingCount)
            + "测\"}\n"
            + String(repeating: "{\"type\":\"response_item\"}\n", count: 60_000)
        let lateEvent = """
        {"timestamp":"2026-06-12T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":1,"total_tokens":10},"total_token_usage":{"input_tokens":17,"cached_input_tokens":6,"output_tokens":8,"reasoning_output_tokens":3,"total_tokens":25}}}}
        """
        try (earlyEvent + "\n" + filler + lateEvent + "\n").write(
            to: rolloutDirectory.appendingPathComponent("rollout-2026-06-12T09-00-00-11111111-1111-4111-8111-111111111111.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = CodexTokenUsageSourceReader(rootDirectories: [
            fixture.url.appendingPathComponent(".codex/sessions", isDirectory: true),
        ]).read(since: Date(timeIntervalSince1970: 0))
        let summary = AITokenUsageAggregator.summary(from: [result], calendar: utcCalendar)

        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(summary.todayTotal(on: date("2026-06-12T12:00:00Z"), calendar: utcCalendar), 25)
    }

    func testCodexReaderFallsBackToInputAndOutputWithoutDoubleCountingBreakdowns() throws {
        let fixture = try TemporaryFixture()
        let rolloutDirectory = fixture.url.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)

        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":7,"output_tokens":5,"reasoning_output_tokens":2}}}}
        """.write(
            to: rolloutDirectory.appendingPathComponent("rollout-fallback.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = CodexTokenUsageSourceReader(rootDirectories: [rolloutDirectory])
            .read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.events.first?.breakdown.totalTokens, 15)
        XCTAssertEqual(result.events.first?.breakdown.cachedInputTokens, 7)
        XCTAssertEqual(result.events.first?.breakdown.reasoningOutputTokens, 2)
    }

    func testCodexReaderIncludesAppendedUsageOnLaterRefreshWithoutRecounting() throws {
        let fixture = try TemporaryFixture()
        let rolloutDirectory = fixture.url.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)
        let fileURL = rolloutDirectory.appendingPathComponent(
            "rollout-2026-06-12T09-00-00-66666666-6666-4666-8666-666666666666.jsonl"
        )
        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10},"total_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10}}}}

        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let reader = CodexTokenUsageSourceReader(rootDirectories: [rolloutDirectory])
        XCTAssertEqual(reader.read(since: Date(timeIntervalSince1970: 0)).events.count, 1)

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("""
        {"timestamp":"2026-06-12T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":11,"output_tokens":4,"total_tokens":15},"total_token_usage":{"input_tokens":18,"output_tokens":7,"total_tokens":25}}}}

        """.utf8))
        try handle.close()

        let refreshed = reader.read(since: Date(timeIntervalSince1970: 0))
        let refreshedAgain = reader.read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(refreshed.events.count, 2)
        XCTAssertEqual(refreshed.events.reduce(0) { $0 + $1.breakdown.totalTokens }, 25)
        XCTAssertEqual(refreshedAgain.events, refreshed.events)
    }

    func testCodexReaderDeduplicatesRepeatedCumulativeSnapshots() throws {
        let fixture = try TemporaryFixture()
        let rolloutDirectory = fixture.url.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)

        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10},"total_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10}}}}
        {"timestamp":"2026-06-12T01:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10},"total_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10}}}}
        """.write(
            to: rolloutDirectory.appendingPathComponent("rollout-2026-06-12T09-00-00-22222222-2222-4222-8222-222222222222.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = CodexTokenUsageSourceReader(rootDirectories: [rolloutDirectory])
            .read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(AITokenUsageAggregator.summary(from: [result], calendar: utcCalendar).sourceSummaries.first?.breakdown.totalTokens, 10)
    }

    func testCodexReaderDoesNotCountParentHistoryReplayedInSubagent() throws {
        let fixture = try TemporaryFixture()
        let rolloutDirectory = fixture.url.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)
        let parentID = "33333333-3333-4333-8333-333333333333"
        let childID = "44444444-4444-4444-8444-444444444444"

        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"session_meta","payload":{"id":"\(parentID)","source":"vscode"}}
        {"timestamp":"2026-06-12T01:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10},"total_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10}}}}
        """.write(
            to: rolloutDirectory.appendingPathComponent("rollout-2026-06-12T09-00-00-\(parentID).jsonl"),
            atomically: true,
            encoding: .utf8
        )

        try """
        {"timestamp":"2026-06-12T02:00:00Z","type":"session_meta","payload":{"id":"\(childID)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(parentID)"}}}}}
        {"timestamp":"2026-06-12T02:00:00Z","type":"session_meta","payload":{"id":"\(parentID)","source":"vscode"}}
        {"timestamp":"2026-06-12T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10},"total_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10}}}}
        {"timestamp":"2026-06-12T02:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":4,"output_tokens":1,"total_tokens":5},"total_token_usage":{"input_tokens":11,"output_tokens":4,"total_tokens":15}}}}
        """.write(
            to: rolloutDirectory.appendingPathComponent("rollout-2026-06-12T10-00-00-\(childID).jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = CodexTokenUsageSourceReader(rootDirectories: [rolloutDirectory])
            .read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(AITokenUsageAggregator.summary(from: [result], calendar: utcCalendar).sourceSummaries.first?.breakdown.totalTokens, 15)
    }

    func testCodexReaderDoesNotMoveOldParentUsageIntoCurrentWindow() throws {
        let fixture = try TemporaryFixture()
        let rolloutDirectory = fixture.url.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: rolloutDirectory, withIntermediateDirectories: true)
        let parentID = "77777777-7777-4777-8777-777777777777"
        let childID = "88888888-8888-4888-8888-888888888888"
        let parentURL = rolloutDirectory.appendingPathComponent(
            "rollout-2026-05-12T09-00-00-\(parentID).jsonl"
        )

        try """
        {"timestamp":"2026-05-12T01:00:00Z","type":"session_meta","payload":{"id":"\(parentID)","source":"vscode"}}
        {"timestamp":"2026-05-12T01:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10},"total_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10}}}}
        """.write(to: parentURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: date("2026-05-12T02:00:00Z")],
            ofItemAtPath: parentURL.path
        )

        try """
        {"timestamp":"2026-06-12T02:00:00Z","type":"session_meta","payload":{"id":"\(childID)","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(parentID)"}}}}}
        {"timestamp":"2026-06-12T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10},"total_token_usage":{"input_tokens":7,"output_tokens":3,"total_tokens":10}}}}
        {"timestamp":"2026-06-12T02:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":4,"output_tokens":1,"total_tokens":5},"total_token_usage":{"input_tokens":11,"output_tokens":4,"total_tokens":15}}}}
        """.write(
            to: rolloutDirectory.appendingPathComponent("rollout-2026-06-12T10-00-00-\(childID).jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = CodexTokenUsageSourceReader(rootDirectories: [rolloutDirectory])
            .read(since: date("2026-06-01T00:00:00Z"))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.breakdown.totalTokens, 5)
    }

    func testCodexDefaultRootsIncludeStandardArchivedSessions() throws {
        let fixture = try TemporaryFixture()
        let archivedDirectory = fixture.url.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: archivedDirectory, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9,"output_tokens":3,"total_tokens":12},"total_token_usage":{"input_tokens":9,"output_tokens":3,"total_tokens":12}}}}
        """.write(
            to: archivedDirectory.appendingPathComponent("rollout-2026-06-12T09-00-00-55555555-5555-4555-8555-555555555555.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = CodexTokenUsageSourceReader(
            rootDirectories: CodexTokenUsageSourceReader.defaultRootDirectories(homeDirectory: fixture.url)
        ).read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.status.state, .available)
        XCTAssertEqual(result.events.map(\.breakdown.totalTokens), [12])
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

    func testClaudeReaderKeepsLatestPositiveUsageForStreamingMessage() throws {
        let fixture = try TemporaryFixture()
        let projectDirectory = fixture.url.appendingPathComponent(".claude/projects/sample-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-stream","model":"claude-test","usage":{"input_tokens":0,"output_tokens":0}}}
        {"timestamp":"2026-06-12T01:00:01Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-stream","model":"claude-test","usage":{"input_tokens":20,"cache_creation_input_tokens":3,"cache_read_input_tokens":4,"output_tokens":5}}}
        """.write(
            to: projectDirectory.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = ClaudeTokenUsageSourceReader(
            projectDirectories: [fixture.url.appendingPathComponent(".claude/projects", isDirectory: true)],
            captureDirectories: []
        ).read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.breakdown.totalTokens, 32)
    }

    func testClaudeReaderKeepsFinalUsageWhenStreamingRowsAreOutOfOrder() throws {
        let fixture = try TemporaryFixture()
        let projectDirectory = fixture.url.appendingPathComponent(".claude/projects/sample-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        try """
        {"timestamp":"2026-06-12T01:00:03Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-out-of-order","model":"claude-test","usage":{"input_tokens":30,"output_tokens":5}}}
        {"timestamp":"2026-06-12T01:00:01Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-out-of-order","model":"claude-test","usage":{"input_tokens":10,"output_tokens":5}}}
        {"timestamp":"2026-06-12T01:00:02Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-out-of-order","model":"claude-test","usage":{"input_tokens":20,"output_tokens":5}}}
        """.write(
            to: projectDirectory.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = ClaudeTokenUsageSourceReader(
            projectDirectories: [fixture.url.appendingPathComponent(".claude/projects", isDirectory: true)],
            captureDirectories: []
        ).read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.breakdown.totalTokens, 35)
        XCTAssertEqual(result.events.first?.timestamp, date("2026-06-12T01:00:01Z"))
    }

    func testClaudeReaderDeduplicatesSameMessageAcrossForkedSessions() throws {
        let fixture = try TemporaryFixture()
        let projectDirectory = fixture.url.appendingPathComponent(".claude/projects/sample-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let line = """
        {"timestamp":"2026-06-12T01:00:00Z","type":"assistant","sessionId":"SESSION_ID","message":{"id":"msg-shared","model":"claude-test","usage":{"input_tokens":10,"output_tokens":5}}}
        """
        try line.replacingOccurrences(of: "SESSION_ID", with: "session-a").write(
            to: projectDirectory.appendingPathComponent("session-a.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try line
            .replacingOccurrences(of: "SESSION_ID", with: "session-b")
            .replacingOccurrences(of: "2026-06-12T01:00:00Z", with: "2026-06-13T01:00:00Z")
            .write(
                to: projectDirectory.appendingPathComponent("session-b.jsonl"),
                atomically: true,
                encoding: .utf8
            )

        let result = ClaudeTokenUsageSourceReader(
            projectDirectories: [fixture.url.appendingPathComponent(".claude/projects", isDirectory: true)],
            captureDirectories: []
        ).read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.breakdown.totalTokens, 15)
        XCTAssertEqual(result.events.first?.timestamp, date("2026-06-12T01:00:00Z"))
    }

    func testClaudeReaderUsesGreaterUsageWhenDuplicateTimestampsMatch() throws {
        let fixture = try TemporaryFixture()
        let projectDirectory = fixture.url.appendingPathComponent(".claude/projects/sample-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-tie","model":"claude-test","usage":{"input_tokens":10,"output_tokens":5}}}
        """.write(
            to: projectDirectory.appendingPathComponent("session-a.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"assistant","sessionId":"session-b","message":{"id":"msg-tie","model":"claude-test","usage":{"input_tokens":20,"output_tokens":5}}}
        """.write(
            to: projectDirectory.appendingPathComponent("session-b.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let result = ClaudeTokenUsageSourceReader(
            projectDirectories: [fixture.url.appendingPathComponent(".claude/projects", isDirectory: true)],
            captureDirectories: []
        ).read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.breakdown.totalTokens, 25)
    }

    func testClaudeReaderDeduplicatesProjectAndCaptureRecords() throws {
        let fixture = try TemporaryFixture()
        let projectDirectory = fixture.url.appendingPathComponent(".claude/projects/sample-project", isDirectory: true)
        let captureDirectory = fixture.url.appendingPathComponent(".claude/cc-capture", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)

        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"assistant","sessionId":"session-a","message":{"id":"response-shared","model":"claude-test","usage":{"input_tokens":10,"output_tokens":5}}}
        """.write(
            to: projectDirectory.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"timestamp":"2026-06-12T01:00:01Z","id":"response-shared","model":"claude-test","usage":{"input_tokens":20,"output_tokens":5}}
        """.write(
            to: captureDirectory.appendingPathComponent("response-shared.response.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = ClaudeTokenUsageSourceReader(
            projectDirectories: [fixture.url.appendingPathComponent(".claude/projects", isDirectory: true)],
            captureDirectories: [captureDirectory]
        ).read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events.first?.breakdown.totalTokens, 25)
    }

    func testClaudeDefaultRootsHonorCustomConfigDirectory() throws {
        let fixture = try TemporaryFixture()
        let customRoot = fixture.url.appendingPathComponent("custom-claude", isDirectory: true)
        let projectDirectory = customRoot.appendingPathComponent("projects/sample-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-06-12T01:00:00Z","type":"assistant","sessionId":"session-a","message":{"id":"msg-custom","model":"claude-test","usage":{"input_tokens":10,"output_tokens":5}}}
        """.write(
            to: projectDirectory.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let environment = ["CLAUDE_CONFIG_DIR": customRoot.path]
        let result = ClaudeTokenUsageSourceReader(
            projectDirectories: ClaudeTokenUsageSourceReader.defaultProjectDirectories(
                homeDirectory: fixture.url,
                environment: environment
            ),
            captureDirectories: ClaudeTokenUsageSourceReader.defaultCaptureDirectories(
                homeDirectory: fixture.url,
                environment: environment
            )
        ).read(since: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(result.status.state, .available)
        XCTAssertEqual(result.events.first?.breakdown.totalTokens, 15)
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

private struct SlowAITokenUsageReader: AITokenUsageSourceReading {
    let sourceID: AITokenUsageSourceID = .cursor
    let delay: TimeInterval

    func read(since startDate: Date) -> AITokenUsageSourceReadResult {
        Thread.sleep(forTimeInterval: delay)
        return AITokenUsageSourceReadResult(
            sourceID: sourceID,
            status: AITokenUsageSourceStatus(id: sourceID, state: .detected, message: "done"),
            events: []
        )
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
