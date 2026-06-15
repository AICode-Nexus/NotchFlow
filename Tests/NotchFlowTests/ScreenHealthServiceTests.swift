import Foundation
@testable import NotchFlow
import XCTest

final class ScreenHealthServiceTests: XCTestCase {
    @MainActor
    func testActiveInputIncrementsTodayAndContinuousDurations() {
        let fixture = makeFixture()

        fixture.service.tick()
        fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
        fixture.activity.secondsSinceLastInput = 0
        fixture.service.tick()

        XCTAssertEqual(fixture.service.snapshot.todayActiveSeconds, 60, accuracy: 0.1)
        XCTAssertEqual(fixture.service.snapshot.continuousActiveSeconds, 60, accuracy: 0.1)
        XCTAssertEqual(fixture.service.snapshot.status, .normal)
    }

    @MainActor
    func testShortIdlePausesCountingWithoutResettingContinuousDuration() {
        let fixture = makeFixture()

        fixture.service.tick()
        fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
        fixture.activity.secondsSinceLastInput = 0
        fixture.service.tick()

        fixture.clock.now = fixture.clock.now.addingTimeInterval(120)
        fixture.activity.secondsSinceLastInput = 120
        fixture.service.tick()

        XCTAssertEqual(fixture.service.snapshot.todayActiveSeconds, 60, accuracy: 0.1)
        XCTAssertEqual(fixture.service.snapshot.continuousActiveSeconds, 60, accuracy: 0.1)
    }

    @MainActor
    func testFiveMinuteIdleResetsContinuousDurationAndClearsReminder() {
        let fixture = makeFixture()

        fixture.service.tick()
        fixture.clock.now = fixture.clock.now.addingTimeInterval(45 * 60)
        fixture.activity.secondsSinceLastInput = 0
        fixture.service.tick()
        XCTAssertEqual(fixture.service.snapshot.status, .breakDue)

        fixture.clock.now = fixture.clock.now.addingTimeInterval(5 * 60)
        fixture.activity.secondsSinceLastInput = 5 * 60
        fixture.service.tick()

        XCTAssertEqual(fixture.service.snapshot.continuousActiveSeconds, 0, accuracy: 0.1)
        XCTAssertEqual(fixture.service.snapshot.status, .resting)
        XCTAssertFalse(fixture.service.snapshot.shouldShowRestReminder)
    }

    @MainActor
    func testDayRolloverResetsTodayActiveDuration() {
        let fixture = makeFixture(startingAt: date("2026-06-12T23:58:00Z"))

        fixture.service.tick()
        fixture.clock.now = fixture.clock.now.addingTimeInterval(60)
        fixture.activity.secondsSinceLastInput = 0
        fixture.service.tick()
        XCTAssertEqual(fixture.service.snapshot.todayActiveSeconds, 60, accuracy: 0.1)

        fixture.clock.now = date("2026-06-13T09:00:00Z")
        fixture.activity.secondsSinceLastInput = 0
        fixture.service.tick()

        XCTAssertEqual(fixture.service.snapshot.todayActiveSeconds, 60, accuracy: 0.1)
    }

    @MainActor
    func testDisabledSettingStopsCountingAndHidesReminder() {
        let fixture = makeFixture()
        fixture.settings.screenHealthEnabled = false

        fixture.service.tick()
        fixture.clock.now = fixture.clock.now.addingTimeInterval(60 * 60)
        fixture.activity.secondsSinceLastInput = 0
        fixture.service.tick()

        XCTAssertEqual(fixture.service.snapshot.todayActiveSeconds, 0, accuracy: 0.1)
        XCTAssertEqual(fixture.service.snapshot.continuousActiveSeconds, 0, accuracy: 0.1)
        XCTAssertEqual(fixture.service.snapshot.status, .normal)
        XCTAssertFalse(fixture.service.snapshot.shouldShowRestReminder)
    }

    @MainActor
    func testDefaultFortyFiveMinuteThresholdEntersBreakDueState() {
        let fixture = makeFixture()

        fixture.service.tick()
        fixture.clock.now = fixture.clock.now.addingTimeInterval(45 * 60)
        fixture.activity.secondsSinceLastInput = 0
        fixture.service.tick()

        XCTAssertEqual(fixture.service.snapshot.continuousActiveSeconds, 45 * 60, accuracy: 0.1)
        XCTAssertEqual(fixture.service.snapshot.status, .breakDue)
        XCTAssertTrue(fixture.service.snapshot.shouldShowRestReminder)
    }

    @MainActor
    private func makeFixture(startingAt startDate: Date? = nil) -> ScreenHealthFixture {
        let defaults = UserDefaults(suiteName: "NotchFlowScreenHealthTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let clock = FakeScreenHealthClock(now: startDate ?? date("2026-06-12T09:00:00Z"))
        let activity = FakeScreenActivityProvider()
        let calendar = utcCalendar
        let service = ScreenHealthService(
            settings: settings,
            defaults: defaults,
            clock: clock,
            activityProvider: activity,
            calendar: calendar,
            timerInterval: nil
        )

        return ScreenHealthFixture(
            defaults: defaults,
            settings: settings,
            clock: clock,
            activity: activity,
            service: service
        )
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

final class ScreenHealthPresentationTests: XCTestCase {
    func testExpandedCardContentFitsInsideModuleHeightWhenReminderVisible() {
        let textScales = PanelTextSizePreset.allCases.map { CGFloat($0.scale) }

        for textScale in textScales {
            let layout = ScreenHealthPanelLayout(
                metrics: NotchPanelMetrics(textScale: textScale),
                showsRestReminder: true
            )

            XCTAssertLessThanOrEqual(
                layout.requiredContentHeight,
                layout.availableContentHeight + 0.1
            )
        }
    }

    func testDurationFormatterUsesCompactChineseLabels() {
        XCTAssertEqual(ScreenHealthFormatter.duration(0), "0 分钟")
        XCTAssertEqual(ScreenHealthFormatter.duration(45 * 60), "45 分钟")
        XCTAssertEqual(ScreenHealthFormatter.duration(75 * 60), "1 小时 15 分钟")
    }

    func testCompactPresentationOnlyShowsBreakDueReminder() {
        let normal = ScreenHealthSnapshot(
            day: Date(timeIntervalSince1970: 0),
            todayActiveSeconds: 60 * 60,
            continuousActiveSeconds: 20 * 60,
            healthScore: 92,
            status: .normal,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let breakDue = ScreenHealthSnapshot(
            day: Date(timeIntervalSince1970: 0),
            todayActiveSeconds: 3 * 60 * 60,
            continuousActiveSeconds: 45 * 60,
            healthScore: 64,
            status: .breakDue,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertNil(ScreenHealthCompactPresentation.title(isEnabled: true, snapshot: normal))
        XCTAssertEqual(
            ScreenHealthCompactPresentation.title(isEnabled: true, snapshot: breakDue),
            "休息一下 · 连续 45 分钟"
        )
        XCTAssertEqual(ScreenHealthCompactPresentation.symbolName(isEnabled: true, snapshot: breakDue), "pause.circle.fill")
        XCTAssertNil(ScreenHealthCompactPresentation.title(isEnabled: false, snapshot: breakDue))
    }
}

private struct ScreenHealthFixture {
    let defaults: UserDefaults
    let settings: AppSettings
    let clock: FakeScreenHealthClock
    let activity: FakeScreenActivityProvider
    let service: ScreenHealthService
}

private final class FakeScreenHealthClock: ScreenHealthClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class FakeScreenActivityProvider: ScreenActivityProviding {
    var secondsSinceLastInput: TimeInterval = 0
    var isSessionActive = true

    func start() {}
    func stop() {}
}
