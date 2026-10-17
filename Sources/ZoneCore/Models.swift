import Foundation

public struct BlockedApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var path: String

    public init(bundleID: String, name: String, path: String = "") {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

public struct BlockList: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var domains: [String]
    public var apps: [BlockedApp]

    public init(id: UUID = UUID(), name: String = "Distractions", domains: [String] = [], apps: [BlockedApp] = []) {
        self.id = id
        self.name = name
        self.domains = domains
        self.apps = apps
    }

    public var isEmpty: Bool { domains.isEmpty && apps.isEmpty }
}

public enum SessionMode: String, Codable, CaseIterable, Sendable {
    case flexible, locked
    public var title: String { self == .flexible ? "Flexible" : "Locked" }
}

public struct PausePolicy: Codable, Equatable, Sendable {
    public var minutes: Int
    public var allowance: Int

    public init(minutes: Int = 5, allowance: Int = 1) {
        self.minutes = min(60, max(1, minutes))
        self.allowance = min(20, max(0, allowance))
    }
}

public struct SessionOptions: Codable, Equatable, Sendable {
    public var mode: SessionMode
    public var pause: PausePolicy

    public init(mode: SessionMode = .flexible, pause: PausePolicy = PausePolicy()) {
        self.mode = mode
        self.pause = pause
    }
}

public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var blockList: BlockList
    public var startsAt: Date
    public var endsAt: Date
    public var options: SessionOptions
    public var scheduleID: UUID?
    public var pausesUsed: Int
    public var pausedUntil: Date?
    public var stoppedAt: Date?

    public init(id: String = UUID().uuidString, name: String, blockList: BlockList,
                startsAt: Date, endsAt: Date, options: SessionOptions = SessionOptions(), scheduleID: UUID? = nil) {
        self.id = id
        self.name = name
        self.blockList = blockList
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.options = options
        self.scheduleID = scheduleID
        self.pausesUsed = 0
    }

    public func isActive(at date: Date) -> Bool {
        stoppedAt == nil && startsAt <= date && date < endsAt
    }

    public func isPaused(at date: Date) -> Bool {
        isActive(at: date) && (pausedUntil.map { date < $0 } ?? false)
    }

    public var pausesRemaining: Int { max(0, options.pause.allowance - pausesUsed) }
}

public enum ScheduleKind: String, Codable, CaseIterable, Sendable {
    case weekly, once
}

public struct FocusSchedule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var blockListID: UUID
    public var isEnabled: Bool
    public var kind: ScheduleKind
    /// Calendar weekday: Sunday = 1, Saturday = 7. Dates follow the Mac's current time zone.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int
    public var onceStart: Date
    public var onceEnd: Date
    public var options: SessionOptions

    public init(id: UUID = UUID(), name: String = "Deep work", blockListID: UUID,
                isEnabled: Bool = true, kind: ScheduleKind = .weekly,
                weekdays: Set<Int> = [2, 3, 4, 5, 6], startMinute: Int = 9 * 60, endMinute: Int = 11 * 60,
                onceStart: Date = Date(), onceEnd: Date = Date().addingTimeInterval(3600),
                options: SessionOptions = SessionOptions()) {
        self.id = id
        self.name = name
        self.blockListID = blockListID
        self.isEnabled = isEnabled
        self.kind = kind
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.onceStart = onceStart
        self.onceEnd = onceEnd
        self.options = options
    }
}

public struct ZoneDocument: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var blockLists: [BlockList]
    public var schedules: [FocusSchedule]
    /// Includes stopped occurrences until their original end, preventing an immediate restart.
    public var sessions: [FocusSession]
    public var defaultOptions: SessionOptions
    public var defaultMinutes: Int

    public init(blockLists: [BlockList] = [BlockList()], schedules: [FocusSchedule] = [],
                sessions: [FocusSession] = [], defaultOptions: SessionOptions = SessionOptions(), defaultMinutes: Int = 25) {
        self.blockLists = blockLists
        self.schedules = schedules
        self.sessions = sessions
        self.defaultOptions = defaultOptions
        self.defaultMinutes = defaultMinutes
    }
}

public enum ZoneError: Error, LocalizedError, Equatable {
    case invalidDomain(String), invalidDuration, emptyBlockList, invalidSchedule, lockedSession, noPauses, inactiveSession
    case unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .invalidDomain(let value): "“\(value)” is not a website domain. Use a name such as youtube.com."
        case .invalidDuration: "Choose a duration between 1 minute and 24 hours."
        case .emptyBlockList: "Add a website or an app to this block list first."
        case .invalidSchedule: "Choose valid start and end times and at least one day."
        case .lockedSession: "This session is locked until its scheduled end."
        case .noPauses: "This session has no pauses left."
        case .inactiveSession: "This session is no longer active."
        case .unsupportedVersion: "This data was saved by a newer version of Zone."
        }
    }
}
