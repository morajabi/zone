import Foundation
import Testing
@testable import ZoneCore

struct SessionTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tehran")!
        return value
    }
    func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int = 19, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    let list = BlockList(name: "Work", domains: ["example.com"], apps: [.init(bundleID: "com.example.game", name: "Game")])

    @Test func domainsNormalizeAndRespectBoundaries() throws {
        #expect(try DomainRule.normalize(" HTTPS://WWW.Example.COM/ ") == "example.com")
        #expect(try DomainRule.normalize("*.example.com") == "example.com")
        #expect(try DomainRule.normalize("example.com.") == "example.com")
        #expect(DomainRule.matches(host: "deep.sub.example.com", domain: "example.com"))
        #expect(!DomainRule.matches(host: "notexample.com", domain: "example.com"))
        #expect(!DomainRule.matches(host: "example.com.evil.com", domain: "example.com"))
        #expect(try DomainRule.parseList("example.com, www.example.com\nother.com") == ["example.com", "other.com"])
    }

    @Test(arguments: ["https://example.com/private", "example.com:8080", "https://user@example.com", "a..com", "-bad.com", "file:///etc/hosts", "127.0.0.1", "localhost", "example.com?search=hello"])
    func rejectsAmbiguousRules(_ input: String) { #expect(throws: ZoneError.self) { try DomainRule.normalize(input) } }

    @Test func exactSessionBoundariesAndSleepCatchUp() throws {
        let now = date()
        let session = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: now)
        #expect(!session.isActive(at: now.addingTimeInterval(-1)))
        #expect(session.isActive(at: now))
        #expect(session.isActive(at: now.addingTimeInterval(1499)))
        #expect(!session.isActive(at: now.addingTimeInterval(1500)))
        let rules = EffectiveRules(document: .init(sessions: [session]), at: now.addingTimeInterval(3600))
        #expect(rules.domains.isEmpty)
        #expect(rules.applicationIDs.isEmpty)
    }

    @Test func lockedSessionsAllowOnlyConfiguredPauses() throws {
        let now = date()
        var session = try SessionEngine.start(list: list, minutes: 25,
            options: .init(mode: .locked, pause: .init(minutes: 5, allowance: 1)), at: now)
        #expect(throws: ZoneError.lockedSession) { try SessionEngine.stop(&session, at: now) }
        try SessionEngine.pause(&session, at: now)
        #expect(session.pausesRemaining == 0)
        #expect(session.isPaused(at: now.addingTimeInterval(299)))
        #expect(!session.isPaused(at: now.addingTimeInterval(300)))
        #expect(session.endsAt == now.addingTimeInterval(1500))
        #expect(throws: ZoneError.noPauses) { try SessionEngine.pause(&session, at: now.addingTimeInterval(301)) }
        #expect(throws: ZoneError.lockedSession) { try SessionEngine.stop(&session, at: now.addingTimeInterval(301)) }
    }

    @Test func earlyResumeDoesNotRefundPause() throws {
        let now = date()
        var session = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: now)
        try SessionEngine.pause(&session, at: now)
        SessionEngine.resume(&session)
        #expect(!session.isPaused(at: now))
        #expect(session.pausesRemaining == 0)
        #expect(throws: ZoneError.noPauses) { try SessionEngine.pause(&session, at: now) }
    }

    @Test func pausesNeverExtendPastSession() throws {
        let now = date()
        var session = try SessionEngine.start(list: list, minutes: 1, options: .init(pause: .init(minutes: 60)), at: now)
        try SessionEngine.pause(&session, at: now.addingTimeInterval(30))
        #expect(session.pausedUntil == session.endsAt)
    }

    @Test func overlappingSessionsKeepTheirOwnRules() throws {
        let now = date()
        var first = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: now)
        let second = try SessionEngine.start(list: BlockList(domains: ["other.com", "example.com"]), minutes: 45, options: .init(), at: now)
        try SessionEngine.pause(&first, at: now)
        let document = ZoneDocument(sessions: [first, second])
        #expect(EffectiveRules(document: document, at: now).domains == ["example.com", "other.com"])
        #expect(EffectiveRules(document: document, at: now).applicationIDs.isEmpty)
        #expect(EffectiveRules(document: document, at: now.addingTimeInterval(300)).applicationIDs == ["com.example.game"])
    }

    @Test func overnightUsesStartDayAndStopsAtExactEnd() throws {
        // Monday night into Tuesday.
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 23 * 60, endMinute: 2 * 60)
        let interval = try #require(SessionEngine.activeInterval(for: schedule, at: date(2026, 10, 20, 1), calendar: calendar))
        #expect(interval.start == date(2026, 10, 19, 23))
        #expect(interval.end == date(2026, 10, 20, 2))
        #expect(SessionEngine.activeInterval(for: schedule, at: interval.end, calendar: calendar) == nil)
        #expect(SessionEngine.activeInterval(for: schedule, at: date(2026, 10, 21, 1), calendar: calendar) == nil)
    }

    @Test func stoppedRecurringOccurrenceDoesNotRestart() throws {
        let now = date()
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 9 * 60, endMinute: 11 * 60)
        var document = ZoneDocument(blockLists: [list], schedules: [schedule])
        SessionEngine.materialize(&document, at: now, calendar: calendar)
        #expect(document.sessions.count == 1)
        try SessionEngine.stop(&document.sessions[0], at: now)
        SessionEngine.materialize(&document, at: now.addingTimeInterval(60), calendar: calendar)
        #expect(document.sessions.count == 1)
        #expect(SessionEngine.activeSessions(in: document, at: now, calendar: calendar).isEmpty)
        SessionEngine.materialize(&document, at: date(2026, 10, 26, 10), calendar: calendar)
        #expect(document.sessions.count == 1)
        #expect(document.sessions[0].isActive(at: date(2026, 10, 26, 10)))
    }

    @Test func editsCannotWeakenExistingLockedSession() {
        let now = date()
        var schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 9 * 60, endMinute: 11 * 60,
                                     options: .init(mode: .locked, pause: .init(allowance: 0)))
        var document = ZoneDocument(blockLists: [list], schedules: [schedule])
        SessionEngine.materialize(&document, at: now, calendar: calendar)
        document.blockLists[0].domains = []
        document.blockLists[0].apps = []
        schedule.isEnabled = false
        document.schedules = [schedule]
        SessionEngine.materialize(&document, at: now, calendar: calendar)
        #expect(document.sessions[0].blockList == list)
        #expect(document.sessions[0].options.mode == .locked)
        #expect(document.sessions[0].options.pause.allowance == 0)
        #expect(EffectiveRules(document: document, at: now, calendar: calendar).blocks(host: "example.com"))
    }

    @Test func oneOffCanStartAfterMissedWake() {
        let now = date()
        let schedule = FocusSchedule(blockListID: list.id, kind: .once, onceStart: now.addingTimeInterval(-3600), onceEnd: now.addingTimeInterval(3600))
        let document = ZoneDocument(blockLists: [list], schedules: [schedule])
        let active = SessionEngine.activeSessions(in: document, at: now)
        #expect(active.count == 1)
        #expect(active.first?.endsAt == schedule.onceEnd)
    }

    @Test func daylightSavingDoesNotCreateTwoOccurrences() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let day = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [1], startMinute: 90, endMinute: 150)
        let interval = try #require(SessionEngine.occurrence(of: schedule, startingOn: day, calendar: newYork))
        #expect(interval.duration == 7200)
        let document = ZoneDocument(blockLists: [list], schedules: [schedule])
        let first = SessionEngine.activeSessions(in: document, at: interval.start, calendar: newYork)
        let second = SessionEngine.activeSessions(in: document, at: interval.start.addingTimeInterval(3600), calendar: newYork)
        #expect(first.first?.id == second.first?.id)
    }

    @Test func springGapMovesToNextValidTime() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let day = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let schedule = FocusSchedule(blockListID: list.id, weekdays: [1], startMinute: 150, endMinute: 240)
        let interval = try #require(SessionEngine.occurrence(of: schedule, startingOn: day, calendar: newYork))
        #expect(newYork.component(.hour, from: interval.start) == 3)
        #expect(newYork.component(.hour, from: interval.end) == 4)
    }

    @Test func nextWeekAndDisabledSchedule() throws {
        var schedule = FocusSchedule(blockListID: list.id, weekdays: [2], startMinute: 540, endMinute: 660)
        #expect(SessionEngine.nextInterval(for: schedule, after: date(), calendar: calendar)?.start == date(2026, 10, 26, 9))
        schedule.isEnabled = false
        #expect(SessionEngine.nextInterval(for: schedule, after: date(), calendar: calendar) == nil)
    }

    @Test func persistenceRetainsPauseAndStopState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DocumentStore(url: directory.appendingPathComponent("sessions.json"))
        var session = try SessionEngine.start(list: list, minutes: 25, options: .init(), at: date())
        try SessionEngine.pause(&session, at: date())
        let document = ZoneDocument(blockLists: [list], sessions: [session])
        try store.save(document)
        #expect(try store.load() == document)
        try Data("broken".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "broken")
    }

    @Test func invalidDurationsAndEmptyRules() {
        #expect(throws: ZoneError.invalidDuration) { try SessionEngine.start(list: list, minutes: 0, options: .init(), at: date()) }
        #expect(throws: ZoneError.emptyBlockList) { try SessionEngine.start(list: BlockList(), minutes: 25, options: .init(), at: date()) }
        let invalid = FocusSchedule(blockListID: list.id, startMinute: 540, endMinute: 540)
        #expect(throws: ZoneError.invalidSchedule) { try SessionEngine.validate(invalid) }
    }
}
