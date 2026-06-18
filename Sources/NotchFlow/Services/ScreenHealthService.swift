import AppKit
import Combine
import CoreGraphics
import Foundation

enum ScreenHealthStatus: String, Equatable, Codable, Sendable {
    case normal
    case nearingBreak
    case breakDue
    case resting

    var title: String {
        switch self {
        case .normal:
            return "状态良好"
        case .nearingBreak:
            return "快到休息时间"
        case .breakDue:
            return "该休息了"
        case .resting:
            return "正在休息"
        }
    }
}

struct ScreenHealthSnapshot: Equatable, Codable, Sendable {
    let day: Date
    let todayActiveSeconds: TimeInterval
    let continuousActiveSeconds: TimeInterval
    let healthScore: Int
    let status: ScreenHealthStatus
    let updatedAt: Date

    var shouldShowRestReminder: Bool {
        status == .breakDue
    }

    static func empty(on date: Date = Date(), calendar: Calendar = .current) -> ScreenHealthSnapshot {
        ScreenHealthSnapshot(
            day: calendar.startOfDay(for: date),
            todayActiveSeconds: 0,
            continuousActiveSeconds: 0,
            healthScore: 100,
            status: .normal,
            updatedAt: date
        )
    }
}

enum ScreenHealthFormatter {
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours) 小时 \(minutes) 分钟"
        }

        if hours > 0 {
            return "\(hours) 小时"
        }

        return "\(minutes) 分钟"
    }

    static func compactDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours)时\(minutes)分"
        }

        if hours > 0 {
            return "\(hours)小时"
        }

        return "\(minutes)分"
    }

    static func score(_ value: Int) -> String {
        "\(value) 分"
    }
}

enum ScreenHealthCompactPresentation {
    static func symbolName(isEnabled: Bool, snapshot: ScreenHealthSnapshot) -> String? {
        guard isEnabled, snapshot.shouldShowRestReminder else {
            return nil
        }

        return "pause.circle.fill"
    }

    static func title(isEnabled: Bool, snapshot: ScreenHealthSnapshot) -> String? {
        guard isEnabled, snapshot.shouldShowRestReminder else {
            return nil
        }

        return "休息一下 · 连续 \(ScreenHealthFormatter.duration(snapshot.continuousActiveSeconds))"
    }
}

protocol ScreenHealthClock: AnyObject {
    var now: Date { get }
}

final class SystemScreenHealthClock: ScreenHealthClock {
    var now: Date {
        Date()
    }
}

@MainActor
protocol ScreenActivityProviding: AnyObject {
    var secondsSinceLastInput: TimeInterval { get }
    var isSessionActive: Bool { get }
    func start()
    func stop()
}

@MainActor
final class SystemScreenActivityProvider: ScreenActivityProviding {
    private(set) var isSessionActive = true
    private var observers: [NSObjectProtocol] = []

    var secondsSinceLastInput: TimeInterval {
        let eventTypes: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .scrollWheel,
        ]

        let intervals = eventTypes
            .map {
                CGEventSource.secondsSinceLastEventType(
                    CGEventSourceStateID.combinedSessionState,
                    eventType: $0
                )
            }
            .filter { $0.isFinite && $0 >= 0 }

        return intervals.min() ?? .greatestFiniteMagnitude
    }

    func start() {
        guard observers.isEmpty else {
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        observers = [
            notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSessionActive = false
                }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSessionActive = true
                }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSessionActive = false
                }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSessionActive = true
                }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSessionActive = false
                }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isSessionActive = true
                }
            },
        ]
    }

    func stop() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}

@MainActor
final class ScreenHealthService: ObservableObject {
    private enum Keys {
        static let day = "ScreenHealthCurrentDay"
        static let todayActiveSeconds = "ScreenHealthTodayActiveSeconds"
        static let continuousActiveSeconds = "ScreenHealthContinuousActiveSeconds"
        static let updatedAt = "ScreenHealthUpdatedAt"
    }

    @Published private(set) var snapshot: ScreenHealthSnapshot
    @Published private(set) var statusMessage = "屏幕健康已开启"

    private let settings: AppSettings
    private let defaults: UserDefaults
    private let clock: ScreenHealthClock
    private let activityProvider: ScreenActivityProviding
    private let calendar: Calendar
    private let timerInterval: TimeInterval?

    private let activeInputWindow: TimeInterval = 60
    private let breakResetInterval: TimeInterval = 5 * 60
    private let maximumAccrualInterval: TimeInterval = 60

    private var refreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var lastSampleDate: Date?
    private var todayActiveSeconds: TimeInterval
    private var continuousActiveSeconds: TimeInterval

    init(
        settings: AppSettings,
        defaults: UserDefaults = .standard,
        clock: ScreenHealthClock = SystemScreenHealthClock(),
        activityProvider: ScreenActivityProviding = SystemScreenActivityProvider(),
        calendar: Calendar = .current,
        timerInterval: TimeInterval? = 15
    ) {
        self.settings = settings
        self.defaults = defaults
        self.clock = clock
        self.activityProvider = activityProvider
        self.calendar = calendar
        self.timerInterval = timerInterval

        let now = clock.now
        let startOfDay = calendar.startOfDay(for: now)
        let storedDay = Date(timeIntervalSince1970: defaults.double(forKey: Keys.day))
        let storedUpdatedAt = Date(timeIntervalSince1970: defaults.double(forKey: Keys.updatedAt))
        let canReuseStoredDurations = calendar.isDate(storedDay, inSameDayAs: startOfDay)

        todayActiveSeconds = canReuseStoredDurations
            ? max(0, defaults.double(forKey: Keys.todayActiveSeconds))
            : 0
        continuousActiveSeconds = canReuseStoredDurations && now.timeIntervalSince(storedUpdatedAt) < breakResetInterval
            ? max(0, defaults.double(forKey: Keys.continuousActiveSeconds))
            : 0
        snapshot = ScreenHealthSnapshot(
            day: startOfDay,
            todayActiveSeconds: todayActiveSeconds,
            continuousActiveSeconds: continuousActiveSeconds,
            healthScore: 100,
            status: .normal,
            updatedAt: now
        )
        updateSnapshot(statusOverride: nil, at: now)
    }

    func start() {
        activityProvider.start()
        bindSettings()
        scheduleTimer()
        tick()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        activityProvider.stop()
        cancellables.removeAll()
        persist()
    }

    func tick() {
        let now = clock.now
        let startOfDay = calendar.startOfDay(for: now)
        let didRollOverDay = !calendar.isDate(snapshot.day, inSameDayAs: startOfDay)

        if didRollOverDay {
            todayActiveSeconds = 0
        }

        guard settings.screenHealthEnabled else {
            lastSampleDate = now
            continuousActiveSeconds = 0
            updateSnapshot(statusOverride: .normal, at: now)
            persist()
            return
        }

        let elapsed = lastSampleDate.map { lastSampleDate in
            let rawElapsed = max(0, now.timeIntervalSince(lastSampleDate))
            return didRollOverDay ? min(rawElapsed, maximumAccrualInterval) : rawElapsed
        } ?? 0
        let inputIdleSeconds = activityProvider.secondsSinceLastInput
        let completedBreak = !activityProvider.isSessionActive || inputIdleSeconds >= breakResetInterval
        let recentlyActive = activityProvider.isSessionActive && inputIdleSeconds <= activeInputWindow
        var statusOverride: ScreenHealthStatus?

        if completedBreak {
            if continuousActiveSeconds > 0 || todayActiveSeconds > 0 {
                statusOverride = .resting
            }
            continuousActiveSeconds = 0
        } else if recentlyActive {
            todayActiveSeconds += elapsed
            continuousActiveSeconds += elapsed
        }

        lastSampleDate = now
        updateSnapshot(statusOverride: statusOverride, at: now)
        persist()
    }

    func refreshNow() {
        tick()
    }

    private func bindSettings() {
        guard cancellables.isEmpty else {
            return
        }

        settings.$screenHealthEnabled
            .combineLatest(
                settings.$screenBreakReminderEnabled,
                settings.$screenBreakReminderThresholdPreset
            )
            .sink { [weak self] _ in
                self?.tick()
            }
            .store(in: &cancellables)
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        guard let timerInterval else {
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func updateSnapshot(statusOverride: ScreenHealthStatus?, at now: Date) {
        let startOfDay = calendar.startOfDay(for: now)
        let status = statusOverride ?? computedStatus()
        snapshot = ScreenHealthSnapshot(
            day: startOfDay,
            todayActiveSeconds: todayActiveSeconds,
            continuousActiveSeconds: continuousActiveSeconds,
            healthScore: computedHealthScore(),
            status: status,
            updatedAt: now
        )
        statusMessage = status.title
    }

    private func computedStatus() -> ScreenHealthStatus {
        guard settings.screenHealthEnabled else {
            return .normal
        }

        guard settings.screenBreakReminderEnabled else {
            return .normal
        }

        let threshold = settings.screenBreakReminderThresholdPreset.timeInterval
        if continuousActiveSeconds >= threshold {
            return .breakDue
        }

        if continuousActiveSeconds >= threshold * 0.8 {
            return .nearingBreak
        }

        return .normal
    }

    private func computedHealthScore() -> Int {
        let threshold = max(settings.screenBreakReminderThresholdPreset.timeInterval, 60)
        let continuousPenalty = min(55, Int((continuousActiveSeconds / threshold) * 35))
        let dailyExcess = max(0, todayActiveSeconds - (4 * 60 * 60))
        let dailyPenalty = min(30, Int((dailyExcess / 3600) * 5))

        return max(0, 100 - continuousPenalty - dailyPenalty)
    }

    private func persist() {
        defaults.set(snapshot.day.timeIntervalSince1970, forKey: Keys.day)
        defaults.set(todayActiveSeconds, forKey: Keys.todayActiveSeconds)
        defaults.set(continuousActiveSeconds, forKey: Keys.continuousActiveSeconds)
        defaults.set(snapshot.updatedAt.timeIntervalSince1970, forKey: Keys.updatedAt)
    }
}
