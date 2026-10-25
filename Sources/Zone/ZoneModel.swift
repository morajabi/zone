import AppKit
import Observation
import ServiceManagement
import ZoneCore

@MainActor @Observable
final class ZoneModel {
    enum WebsiteMode: String, CaseIterable, Identifiable {
        case browser = "Browser control", network = "Network filter"
        var id: Self { self }
    }
    enum Page: String, CaseIterable, Identifiable {
        case focus = "Focus", lists = "Block Lists", schedules = "Schedules"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .focus: "circle.dotted.circle"
            case .lists: "hand.raised"
            case .schedules: "calendar"
            }
        }
    }

    private(set) var document: ZoneDocument
    private(set) var activeSessions: [FocusSession] = []
    private(set) var now = Date()
    var page: Page = .focus
    var editingList: BlockList?
    var editingSchedule: FocusSchedule?
    enum SettingsPane: Hashable { case general, websites }
    var settingsPane: SettingsPane = .general
    var selectedListID: UUID? {
        didSet { UserDefaults.standard.set(selectedListID?.uuidString, forKey: "selectedListID") }
    }
    var quickMinutesText = "25"
    var quickMinutes: Int {
        get { Int(quickMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
        set { quickMinutesText = String(newValue) }
    }
    var quickOptions = SessionOptions()
    var errorMessage: String?
    var lastBlockedApp: String?
    var appBlockFailure: String?
    let filter = FilterController()
    let browsers = BrowserBlocker()
    private(set) var websiteMode: WebsiteMode = .browser
    private(set) var changingWebsiteMode = false
    private(set) var launchAtLogin = false
    private(set) var storageFailed = false
    @ObservationIgnored private let store: DocumentStore
    @ObservationIgnored private let blocker = AppBlocker()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var ticks = 0

    init() {
        websiteMode = UserDefaults.standard.string(forKey: "websiteMode").flatMap(WebsiteMode.init(rawValue:)) ?? .browser
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zone")
        store = DocumentStore(url: directory.appendingPathComponent("sessions.json"))
        do { document = try store.load() }
        catch {
            document = ZoneDocument()
            storageFailed = true
            errorMessage = "Zone could not read its saved sessions. The existing file has been preserved. \(error.localizedDescription)"
        }
        quickMinutes = document.defaultMinutes
        quickOptions = document.defaultOptions
        let previousList = UserDefaults.standard.string(forKey: "selectedListID").flatMap(UUID.init(uuidString:))
        selectedListID = document.blockLists.first(where: { $0.id == previousList && !$0.isEmpty })?.id
            ?? document.blockLists.first(where: { !$0.isEmpty })?.id ?? document.blockLists.first?.id
        launchAtLogin = SMAppService.mainApp.status == .enabled
        blocker.onBlocked = { [weak self] name in self?.lastBlockedApp = name; self?.appBlockFailure = nil }
        blocker.onFailure = { [weak self] name in self?.appBlockFailure = "Could not close \(name). It may still be available." }
        tick()
        if websiteMode == .network { filter.update(document) }
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        clock.tolerance = 0.15
        // Keep enforcing and advancing sessions while a menu or picker is open.
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task {
            if websiteMode == .network { await filter.refresh() }
            else if filter.isSignedBuild { _ = await filter.disable() }
        }
    }

    var selectedList: BlockList? { document.blockLists.first { $0.id == selectedListID } }
    var availableLists: [BlockList] { document.blockLists.filter { !$0.isEmpty } }
    var nextScheduledSession: (name: String, start: Date)? {
        document.schedules.compactMap { schedule -> (name: String, start: Date)? in
            guard let interval = SessionEngine.nextInterval(for: schedule, after: now) else { return nil }
            return (schedule.name, interval.start)
        }.min { $0.start < $1.start }
    }
    var hasStrictSession: Bool { activeSessions.contains(where: \.isStrict) }
    var hasWebsiteSession: Bool { activeSessions.contains { !$0.blockList.domains.isEmpty } }

    enum MenuState { case idle, focusing, paused }
    var menuState: MenuState {
        if activeSessions.isEmpty { return .idle }
        return activeSessions.contains { !$0.isPaused(at: now) } ? .focusing : .paused
    }
    /// Time until blocking fully ends, or until the earliest pause ends when every session is paused.
    var menuTitle: String {
        let focusing = activeSessions.filter { !$0.isPaused(at: now) }
        let until = focusing.isEmpty
            ? activeSessions.map { min($0.pausedUntil ?? $0.endsAt, $0.endsAt) }.min()
            : focusing.map(\.endsAt).max()
        return until.map { Self.shortDuration($0.timeIntervalSince(now)) } ?? ""
    }

    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(interval / 60)))
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    static let durationPresets = [15, 25, 30, 45, 60, 90, 120]
    var durationChoices: [Int] {
        let presets = Self.durationPresets
        return (1...1440).contains(quickMinutes) && !presets.contains(quickMinutes) ? (presets + [quickMinutes]).sorted() : presets
    }

    func isRunning(_ schedule: FocusSchedule) -> Bool { activeSessions.contains { $0.scheduleID == schedule.id } }
    func runningSession(for schedule: FocusSchedule) -> FocusSession? { activeSessions.first { $0.scheduleID == schedule.id } }

    /// Running schedules first, then by their next start; schedules that are off come last.
    var schedulesByNextStart: [FocusSchedule] {
        func rank(_ schedule: FocusSchedule) -> (Int, Date) {
            if let session = runningSession(for: schedule) { return (0, session.endsAt) }
            if let next = SessionEngine.nextInterval(for: schedule, after: now) { return (1, next.start) }
            return (schedule.isEnabled ? 2 : 3, .distantFuture)
        }
        return document.schedules.sorted { lhs, rhs in
            let (a, b) = (rank(lhs), rank(rhs))
            return a.0 != b.0 ? a.0 < b.0 : a.1 != b.1 ? a.1 < b.1
                : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    var websiteBlockingReady: Bool { websiteMode == .browser ? browsers.hasConnectedBrowser : filter.isReady }
    var blockingIsDegraded: Bool {
        hasWebsiteSession && (!websiteBlockingReady || (websiteMode == .browser && browsers.attention != nil))
    }
    var websiteBlockingTitle: String {
        if websiteMode == .network { return filter.state.title }
        if browsers.attention != nil { return "Check browser access" }
        return websiteBlockingReady ? "Browsers are ready" : "Connect a browser"
    }

    func newList() {
        editingList = document.blockLists.count == 1 && document.blockLists[0].isEmpty
            ? document.blockLists[0] : BlockList(name: "")
    }

    func newSchedule() {
        guard let list = availableLists.first(where: { $0.id == selectedListID }) ?? availableLists.first else {
            newList()
            return
        }
        editingSchedule = FocusSchedule(blockListID: list.id, isEnabled: list.domains.isEmpty || websiteBlockingReady,
            onceStart: Date().addingTimeInterval(3600), onceEnd: Date().addingTimeInterval(7200))
    }
    var websiteBlockingDetail: String {
        if websiteMode == .network { return filter.detail }
        return browsers.attention ?? (websiteBlockingReady
            ? "Blocked tabs are redirected while Zone is running."
            : "Connect the browsers you use in Settings. Zone will open them if needed.")
    }

    func setWebsiteMode(_ mode: WebsiteMode) {
        guard mode != websiteMode, !hasWebsiteSession, !changingWebsiteMode else { return }
        changingWebsiteMode = true
        Task {
            defer { changingWebsiteMode = false }
            if mode == .browser {
                _ = await filter.finishPendingUpdates()
                guard await filter.disable() else {
                    errorMessage = "Could not turn off the network filter. Check its status before switching modes."
                    return
                }
            }
            websiteMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: "websiteMode")
            if mode == .network { filter.update(document) }
            tick()
        }
    }

    func tick() {
        now = Date()
        guard !storageFailed else { return }
        var next = document
        SessionEngine.materialize(&next, at: now)
        if next != document { commit(next) }
        activeSessions = SessionEngine.activeSessions(in: document, at: now)
        blocker.update(EffectiveRules(document: document, at: now).applicationIDs)
        browsers.update(document, enabled: websiteMode == .browser)
        ticks += 1
        if ticks % 5 == 0 && websiteMode == .network { Task { await filter.refresh() } }
    }

    func startQuickSession() {
        guard let list = selectedList else { return }
        do {
            if !list.domains.isEmpty && !websiteBlockingReady {
                errorMessage = "Set up website blocking in Settings before starting a session with websites."
                return
            }
            let session = try SessionEngine.start(list: list, minutes: quickMinutes, options: quickOptions, at: Date())
            var next = document
            next.defaultMinutes = quickMinutes
            next.defaultOptions = quickOptions
            next.sessions.append(session)
            commit(next)
            tick()
        } catch { errorMessage = error.localizedDescription }
    }

    func pause(_ session: FocusSession) { changeSession(session) { try SessionEngine.pause(&$0, at: Date()) } }
    func resume(_ session: FocusSession) { changeSession(session) { SessionEngine.resume(&$0) } }
    func stop(_ session: FocusSession) { changeSession(session) { try SessionEngine.stop(&$0, at: Date()) } }

    private func changeSession(_ session: FocusSession, _ update: (inout FocusSession) throws -> Void) {
        var next = document
        guard let index = next.sessions.firstIndex(where: { $0.id == session.id }) else { return }
        do { try update(&next.sessions[index]); commit(next); tick() }
        catch { errorMessage = error.localizedDescription }
    }

    @discardableResult func saveList(_ list: BlockList) -> Bool {
        var next = document
        if let index = next.blockLists.firstIndex(where: { $0.id == list.id }) { next.blockLists[index] = list }
        else { next.blockLists.append(list) }
        if commit(next) {
            selectedListID = list.isEmpty ? availableLists.first?.id : list.id
            return true
        }
        return false
    }

    func deleteList(_ list: BlockList) {
        guard !document.schedules.contains(where: { $0.blockListID == list.id }) else {
            errorMessage = "Remove schedules using this list before deleting it."
            return
        }
        var next = document
        next.blockLists.removeAll { $0.id == list.id }
        if commit(next), selectedListID == list.id { selectedListID = availableLists.first?.id }
    }

    func saveSchedule(_ schedule: FocusSchedule) -> Bool {
        do {
            try SessionEngine.validate(schedule)
            guard let list = document.blockLists.first(where: { $0.id == schedule.blockListID }), !list.isEmpty else { throw ZoneError.emptyBlockList }
            if schedule.isEnabled && !list.domains.isEmpty && !websiteBlockingReady {
                errorMessage = "Save this schedule with Enabled turned off, then connect your browsers or enable the optional network filter in Settings."
                return false
            }
            var next = document
            if let index = next.schedules.firstIndex(where: { $0.id == schedule.id }) { next.schedules[index] = schedule }
            else { next.schedules.append(schedule) }
            let saved = commit(next)
            tick()
            return saved
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func deleteSchedule(_ schedule: FocusSchedule) {
        var next = document
        next.schedules.removeAll { $0.id == schedule.id }
        commit(next)
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { SMAppService.openSystemSettingsLoginItems() }
        } catch { errorMessage = error.localizedDescription }
    }

    func quit() {
        guard !hasStrictSession else { errorMessage = "Zone stays open until your scheduled or locked session ends."; return }
        if !activeSessions.isEmpty {
            let alert = NSAlert()
            alert.messageText = "End sessions and quit Zone?"
            alert.informativeText = websiteMode == .browser
                ? "Current sessions will end. Scheduled sessions need Zone running."
                : "Current sessions will end. App schedules need Zone running. Website schedules can continue in the network filter."
            alert.addButton(withTitle: "End Sessions and Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            var next = document
            for index in next.sessions.indices where next.sessions[index].isActive(at: Date()) {
                try? SessionEngine.stop(&next.sessions[index], at: Date())
            }
            guard commit(next) else { return }
        }
        Task {
            if websiteMode == .network, !(await filter.finishPendingUpdates()) {
                errorMessage = "Zone could not confirm the website filter received the changes. It will stay open so you can check its status."
                return
            }
            NSApplication.shared.terminate(nil)
        }
    }

    @discardableResult private func commit(_ next: ZoneDocument) -> Bool {
        guard !storageFailed else {
            errorMessage = "Saved data could not be read. Fix or restore the sessions file and restart Zone before making changes."
            return false
        }
        do {
            try store.save(next)
            document = next
            if websiteMode == .network { filter.update(next) }
            browsers.update(next, enabled: websiteMode == .browser)
            return true
        } catch { errorMessage = "Could not save changes: \(error.localizedDescription)"; return false }
    }
}
