import Foundation
import NetworkExtension
import Observation
import OSLog
import SystemExtensions
import ZoneCore

@MainActor @Observable
final class FilterController: NSObject, @MainActor OSSystemExtensionRequestDelegate {
    enum State: Equatable {
        case unsigned, off, approval, connecting, ready, failed(String)
        var title: String {
            switch self {
            case .unsigned: "Website filter needs a signed build"
            case .off: "Website filter is off"
            case .approval: "Waiting for macOS approval"
            case .connecting: "Connecting to website filter…"
            case .ready: "Website filter is connected"
            case .failed: "Website filter needs attention"
            }
        }
    }

    private(set) var state: State = .unsigned
    private(set) var detail = "Browser control works in this build. The optional network filter needs Apple signing and macOS approval."
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var pending: ZoneDocument?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var latest = ZoneDocument()
    @ObservationIgnored private var lastAcknowledged: Data?
    @ObservationIgnored private var request: OSSystemExtensionRequest?
    @ObservationIgnored private var refreshInFlight = false
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Zone", category: "WebsiteFilter")

    var isReady: Bool { state == .ready }
    var canInstall: Bool { state != .unsigned && state != .approval && state != .connecting }
    var isSignedBuild: Bool {
        FilterIdentity.teamID != nil && FileManager.default.fileExists(atPath: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions/\(FilterIdentity.bundleID).systemextension/Contents/embedded.provisionprofile").path)
    }

    override init() {
        super.init()
        if isSignedBuild { state = .off; detail = "Enable the network filter to block websites across browsers." }
    }

    func update(_ document: ZoneDocument) {
        latest = document
        guard isSignedBuild else { return }
        if state == .ready { state = .connecting }
        pending = document
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            while let next = self.pending {
                self.pending = nil
                do {
                    let data = try JSONEncoder().encode(next)
                    if data == self.lastAcknowledged { self.state = .ready; continue }
                    let manager = NEFilterManager.shared()
                    try await manager.loadFromPreferences()
                    guard manager.isEnabled, let configuration = manager.providerConfiguration else { self.state = .off; continue }
                    configuration.vendorConfiguration = ["policy": data]
                    manager.providerConfiguration = configuration
                    try await manager.saveToPreferences()
                    try await self.send(data)
                    self.lastAcknowledged = data
                    self.state = .ready
                    self.detail = "Network filter connected. Browser coverage is still being validated."
                } catch { self.fail(error) }
            }
            self.syncTask = nil
        }
    }

    func finishPendingUpdates() async -> Bool {
        await syncTask?.value
        return !isSignedBuild || state == .ready || state == .off
    }

    func refresh() async {
        guard isSignedBuild, request == nil, syncTask == nil, !refreshInFlight, state != .approval else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        do {
            let manager = NEFilterManager.shared()
            try await manager.loadFromPreferences()
            guard manager.isEnabled else {
                // Keep an activation failure visible until the user retries it.
                if case .failed = state {} else {
                    state = .off
                    detail = "Enable the network filter to block websites across browsers."
                }
                lastAcknowledged = nil
                return
            }
            let status = try await ping()
            guard syncTask == nil else { return }
            guard status == "ready" else { state = .connecting; return }
            if lastAcknowledged == nil { update(latest) }
            else { state = .ready }
        } catch { fail(error) }
    }

    func enable() {
        guard isSignedBuild else { return }
        state = .connecting
        detail = "Allow Zone’s network extension in System Settings when macOS asks."
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: FilterIdentity.bundleID, queue: .main)
        request.delegate = self
        self.request = request
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    @discardableResult func disable() async -> Bool {
        guard isSignedBuild else { return true }
        do {
            let manager = NEFilterManager.shared()
            try await manager.loadFromPreferences()
            if manager.isEnabled {
                manager.isEnabled = false
                try await manager.saveToPreferences()
            }
            connection?.invalidate()
            connection = nil
            lastAcknowledged = nil
            state = .off
            detail = "Website blocking is off."
            return true
        } catch { fail(error); return false }
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        state = .approval
        detail = "Approve Zone in System Settings → General → Login Items & Extensions → Network Extensions."
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) { self.request = nil; fail(error) }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        self.request = nil
        guard result == .completed else {
            state = .approval
            detail = "Restart your Mac to finish activating the network extension."
            return
        }
        Task {
            do {
                let manager = NEFilterManager.shared()
                try await manager.loadFromPreferences()
                let configuration = NEFilterProviderConfiguration()
                configuration.filterSockets = true
                configuration.filterDataProviderBundleIdentifier = FilterIdentity.bundleID
                configuration.vendorConfiguration = ["policy": try JSONEncoder().encode(latest)]
                manager.providerConfiguration = configuration
                manager.localizedDescription = "Zone website blocking"
                manager.isEnabled = true
                try await manager.saveToPreferences()
                state = .connecting
                lastAcknowledged = nil
                await refresh()
            } catch { fail(error) }
        }
    }

    private func proxy() throws -> ZoneFilterIPC {
        if connection == nil {
            guard let service = FilterIdentity.machService, let team = FilterIdentity.teamID else { throw FilterError.unavailable }
            let connection = NSXPCConnection(machServiceName: service, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: ZoneFilterIPC.self)
            connection.setCodeSigningRequirement(FilterIdentity.requirement(identifier: FilterIdentity.bundleID, team: team))
            connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil; self?.lastAcknowledged = nil } }
            connection.interruptionHandler = { [weak self] in Task { @MainActor in self?.lastAcknowledged = nil; self?.state = .connecting } }
            connection.resume()
            self.connection = connection
        }
        guard let proxy = connection?.remoteObjectProxy as? ZoneFilterIPC else { throw FilterError.unavailable }
        return proxy
    }

    private func ping() async throws -> String {
        let proxy = try proxy()
        return try await withCheckedThrowingContinuation { continuation in
            let reply = XPCReply(continuation)
            proxy.status { reply.finish(.success($0)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { reply.finish(.failure(FilterError.timeout)) }
        }
    }

    private func send(_ data: Data) async throws {
        let proxy = try proxy()
        let _: String = try await withCheckedThrowingContinuation { continuation in
            let reply = XPCReply(continuation)
            proxy.replacePolicy(data) { error in
                if let error { reply.finish(.failure(FilterError.rejected(error))) }
                else { reply.finish(.success("ok")) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) { reply.finish(.failure(FilterError.timeout)) }
        }
    }

    private func fail(_ error: Error) {
        let nsError = error as NSError
        Self.logger.error("Website filter failed: \(nsError.domain, privacy: .public) (\(nsError.code)) — \(nsError.localizedDescription, privacy: .public)")
        state = .failed(error.localizedDescription)
        detail = error.localizedDescription
        lastAcknowledged = nil
    }
}

private enum FilterError: LocalizedError {
    case unavailable, timeout, rejected(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "The website filter is unavailable. Enable it in Settings."
        case .timeout: "The website filter did not respond. Check its permission in System Settings."
        case .rejected(let message): message
        }
    }
}

private final class XPCReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }
    func finish(_ result: Result<String, Error>) {
        let value = lock.withLock { let value = continuation; continuation = nil; return value }
        value?.resume(with: result)
    }
}
