import AppKit
import Carbon
import Observation
import OSLog
import ZoneCore

struct SupportedBrowser: Identifiable, Sendable {
    let id: String
    let name: String
    var windowClass = "cwin"
    var tabClass = "CrTb"
    var urlProperty = "URL "

    static let all: [SupportedBrowser] = [
        .init(id: "com.apple.Safari", name: "Safari", tabClass: "bTab", urlProperty: "pURL"),
        .init(id: "com.google.Chrome", name: "Google Chrome"),
        .init(id: "company.thebrowser.dia", name: "Dia", tabClass: "DiaT"),
        .init(id: "company.thebrowser.Browser", name: "Arc", windowClass: "WiND", tabClass: "tAbB"),
        .init(id: "com.brave.Browser", name: "Brave"),
        .init(id: "com.microsoft.edgemac", name: "Microsoft Edge"),
        .init(id: "com.operasoftware.Opera", name: "Opera"),
    ]
}

enum BrowserAccess: Equatable, Sendable {
    case ready, closed, notRunning, needsPermission, denied, checking, failed(Int)

    var description: String {
        switch self {
        case .ready: "Connected"
        case .closed: "Ready when opened"
        case .notRunning: "Connect to block websites here"
        case .needsPermission: "Automation permission needed"
        case .denied: "Allow Zone in Privacy & Security → Automation"
        case .checking: "Checking…"
        case .failed(let code): "Browser did not respond (\(code)). Try again."
        }
    }
}

@MainActor @Observable
final class BrowserBlocker {
    private(set) var installed: [SupportedBrowser] = []
    private(set) var access: [String: BrowserAccess] = [:]
    @ObservationIgnored private let policy = BrowserPolicy()
    @ObservationIgnored private let workers = Dictionary(uniqueKeysWithValues: SupportedBrowser.all.map { ($0.id, BrowserWorker()) })
    // A system consent dialog can wait indefinitely. Keep it away from the
    // worker enforcing rules in browsers that are already connected.
    @ObservationIgnored private let connectionWorker = BrowserWorker()
    @ObservationIgnored private var scans: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var checking: Set<String> = []
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var authorized = Set(UserDefaults.standard.stringArray(forKey: "connectedBrowsers") ?? [])

    var hasConnectedBrowser: Bool { access.values.contains(.ready) || access.values.contains(.closed) }
    var attention: String? {
        let names = installed.filter { browser in
            let status = access[browser.id] ?? .notRunning
            return status != .ready && status != .closed && status != .notRunning
        }.map(\.name)
        return names.isEmpty ? nil : "Allow access to \(names.formatted(.list(type: .and))) to block websites there."
    }

    init() { refreshInstalled() }

    func refreshInstalled() {
        installed = SupportedBrowser.all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
        let ids = Set(installed.map(\.id))
        access = access.filter { ids.contains($0.key) }
        for browser in installed where access[browser.id] == nil {
            access[browser.id] = authorized.contains(browser.id) ? .closed : .notRunning
        }
    }

    func connect(_ browser: SupportedBrowser) {
        guard checking.insert(browser.id).inserted else { return }
        access[browser.id] = .checking
        Task {
            defer { checking.remove(browser.id) }
            do {
                let app: NSRunningApplication
                if let running = NSRunningApplication.runningApplications(withBundleIdentifier: browser.id).first {
                    app = running
                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                } else { access[browser.id] = .notRunning; return }
                record(await connectionWorker.check(browser, pid: app.processIdentifier, requestPermission: true), for: browser.id)
            } catch { access[browser.id] = .failed((error as NSError).code) }
        }
    }

    private func record(_ result: BrowserAccess, for id: String) {
        access[id] = result
        var next = authorized
        if result == .ready { next.insert(id) }
        if result == .denied || result == .needsPermission { next.remove(id) }
        if next != authorized {
            authorized = next
            UserDefaults.standard.set(Array(next).sorted(), forKey: "connectedBrowsers")
        }
    }

    func update(_ document: ZoneDocument, enabled: Bool) {
        policy.update(document, enabled: enabled)
        ticks += 1
        guard enabled else { return }
        let enforce = !EffectiveRules(document: document, at: Date()).domains.isEmpty
        guard enforce || ticks % 5 == 1 else { return }
        let page = Bundle.main.url(forResource: "Blocked", withExtension: "html")?.absoluteString
        for browser in installed {
            guard scans[browser.id] == nil, !checking.contains(browser.id), let worker = workers[browser.id] else { continue }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.id).first else {
                access[browser.id] = authorized.contains(browser.id) ? .closed : .notRunning; continue
            }
            let pid = app.processIdentifier
            scans[browser.id] = Task {
                defer { scans[browser.id] = nil }
                let result = await worker.check(browser, pid: pid, requestPermission: false)
                guard !checking.contains(browser.id) else { return }
                if result == .ready, enforce {
                    if let page {
                        record(await worker.enforce(browser, pid: pid, policy: policy, blockedPage: page), for: browser.id)
                    } else { access[browser.id] = .failed(-43) }
                } else { record(result, for: browser.id) }
            }
        }
    }
}

/// Apple-event descriptors stay on this actor. Browser calls have bounded
/// timeouts and never block the app's main actor or launch a closed browser.
private actor BrowserWorker {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Zone", category: "BrowserControl")
    private var lastFailure: [String: String] = [:]
    func check(_ browser: SupportedBrowser, pid: pid_t, requestPermission: Bool) -> BrowserAccess {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, requestPermission)
        switch status {
        case noErr:
            if requestPermission {
                do { _ = try get(all(browser.windowClass), target: target) }
                catch { return .failed((error as NSError).code) }
            }
            return .ready
        case OSStatus(errAEEventWouldRequireUserConsent): return .needsPermission
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        default: return .failed(Int(status))
        }
    }

    func enforce(_ browser: SupportedBrowser, pid: pid_t, policy: BrowserPolicy, blockedPage: String) -> BrowserAccess {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        var operation = "Read windows"
        do {
            let windows = try get(all(browser.windowClass), target: target)
            for window in elements(windows) {
                operation = "Read tabs"
                let tabs = all(browser.tabClass, in: window)
                let references = elements(try get(tabs, target: target))
                for tab in references {
                    operation = "Read tab address"
                    let urlProperty = property(browser.urlProperty, of: tab)
                    guard let url = try get(urlProperty, target: target).stringValue, policy.blocks(url) else { continue }
                    // Recheck both the tab and current policy immediately before changing it.
                    // Safari uses positional tab references, which can move when tabs close.
                    let current = try get(urlProperty, target: target).stringValue
                    guard current == url, policy.blocks(url) else { continue }
                    operation = "Redirect tab"
                    // The fragment stays in the browser; the local page uses it to name the site.
                    let host = URLComponents(string: url)?.host.map { "#" + $0 } ?? ""
                    _ = try send("setd", object: urlProperty, target: target, value: NSAppleEventDescriptor(string: blockedPage + host))
                }
            }
            lastFailure[browser.id] = nil
            return .ready
        } catch {
            let code = (error as NSError).code
            let failure = "\(operation): \(code)"
            if lastFailure[browser.id] != failure {
                logger.error("\(browser.name, privacy: .public) — \(failure, privacy: .public)")
                lastFailure[browser.id] = failure
            }
            // A tab/window closing during the scan is ordinary; retry next tick.
            if code == -1728 { return .ready }
            if code == -1743 { return .denied }
            if code == -600 { return .notRunning }
            return .failed(code)
        }
    }

    private func elements(_ value: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard value.descriptorType == typeAEList else { return [value] }
        return (0..<value.numberOfItems).compactMap { value.atIndex($0 + 1) }
    }

    private func get(_ object: NSAppleEventDescriptor, target: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send("getd", object: object, target: target)
    }

    private func send(_ command: String, object: NSAppleEventDescriptor, target: NSAppleEventDescriptor,
                      value: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: code("core"), eventID: code(command), targetDescriptor: target,
                                          returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(object, forKeyword: keyDirectObject)
        if let value { event.setParam(value, forKeyword: keyAEData) }
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1)
        if let error = reply.paramDescriptor(forKeyword: keyErrorNumber), error.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        return reply.paramDescriptor(forKeyword: keyDirectObject) ?? .null()
    }

    private func all(_ type: String, in container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        // Ordinals use 'abso', not the generic 'enum' descriptor. Browsers reject
        // an enumerated "all" with errAECoercionFail (-1700).
        let ordinal = NSAppleEventDescriptor(descriptorType: typeAbsoluteOrdinal,
                                            data: NSAppleEventDescriptor(enumCode: OSType(kAEAll)).data)!
        return specifier(want: code(type), container: container, form: OSType(formAbsolutePosition), key: ordinal)
    }

    private func property(_ name: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: typeProperty, container: container, form: OSType(formPropertyID), key: NSAppleEventDescriptor(typeCode: code(name)))
    }

    private func specifier(want: OSType, container: NSAppleEventDescriptor, form: OSType,
                           key: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
        return record.coerce(toDescriptorType: typeObjectSpecifier)!
    }

    private func code(_ value: String) -> OSType { value.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
}
