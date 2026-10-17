import Foundation
import Network
import NetworkExtension
import ZoneCore

final class FilterDataProvider: NEFilterDataProvider, NSXPCListenerDelegate, ZoneFilterIPC, @unchecked Sendable {
    // NE and XPC invoke callbacks on different queues; all policy/flow state is guarded by this lock.
    private let lock = NSLock()
    private var document = ZoneDocument(blockLists: [])
    private var ready = false
    private var listener: NSXPCListener?
    private var timer: DispatchSourceTimer?
    private var flows: [UUID: (NEFilterSocketFlow, String)] = [:]
    private var lastRules: EffectiveRules?

    override func startFilter(completionHandler: @escaping @Sendable (Error?) -> Void) {
        if let data = filterConfiguration.vendorConfiguration?["policy"] as? Data,
           let policy = try? JSONDecoder().decode(ZoneDocument.self, from: data), policy.version == 1 {
            lock.withLock { document = policy }
        }
        guard let service = FilterIdentity.machService else {
            completionHandler(NSError(domain: "Zone", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing signing team."]))
            return
        }
        let listener = NSXPCListener(machServiceName: service)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        apply(NEFilterSettings(rules: [], defaultAction: .filterData)) { [weak self] error in
            guard let self else { completionHandler(error); return }
            self.lock.withLock { self.ready = error == nil }
            if error == nil { self.startTimer() }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        timer?.cancel()
        timer = nil
        listener?.invalidate()
        listener = nil
        lock.withLock { ready = false; flows.removeAll() }
        completionHandler()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let team = FilterIdentity.teamID else { return false }
        connection.setCodeSigningRequirement(FilterIdentity.requirement(identifier: FilterIdentity.appBundleID, team: team))
        connection.exportedInterface = NSXPCInterface(with: ZoneFilterIPC.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func status(reply: @escaping (String) -> Void) {
        reply(lock.withLock { ready ? "ready" : "starting" })
    }

    func replacePolicy(_ data: Data, reply: @escaping (String?) -> Void) {
        do {
            guard lock.withLock({ ready }) else { reply("The website filter is still starting."); return }
            guard data.count <= 1_048_576 else { throw ZoneError.unsupportedVersion }
            let policy = try JSONDecoder().decode(ZoneDocument.self, from: data)
            guard policy.version == 1 else { throw ZoneError.unsupportedVersion }
            lock.withLock { document = policy }
            reevaluate()
            reply(nil)
        } catch { reply(error.localizedDescription) }
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        let rules = currentRules()
        if let host = flow.url?.host, rules.blocks(host: host) { return .drop() }
        guard let socket = flow as? NEFilterSocketFlow else { return .allow() }
        if let host = socket.remoteHostname, !host.isEmpty {
            track(socket, host: host)
            return report(rules.blocks(host: host) ? .drop() : .allow())
        }
        // QUIC cannot be inspected as TLS records. During website sessions, UDP/443
        // is dropped so browsers retry over inspectable TCP. This is disclosed in setup.
        if socket.socketProtocol == IPPROTO_UDP, remotePort(socket) == "443", !rules.domains.isEmpty { return .drop() }
        guard socket.socketProtocol == IPPROTO_TCP,
              ["80", "443", "8080", "8443"].contains(remotePort(socket)) else { return .allow() }
        return report(.filterDataVerdict(withFilterInbound: false, peekInboundBytes: 0,
                                        filterOutbound: true, peekOutboundBytes: 4096))
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        guard offset == 0 else { return .allow() }
        switch HostInspection.inspect(readBytes) {
        case .host(let host):
            if let socket = flow as? NEFilterSocketFlow { track(socket, host: host) }
            return currentRules().blocks(host: host) ? .drop() : .allow()
        case .needsMore:
            guard readBytes.count < HostInspection.maximumBytes else { return .allow() }
            return NEFilterDataVerdict(passBytes: 0, peekBytes: min(HostInspection.maximumBytes, max(4096, readBytes.count * 2)))
        case .unknown:
            // ECH / opaque tunnels are a known coverage gap, not grounds to block unrelated traffic.
            return .allow()
        }
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict { .allow() }
    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict { .allow() }
    override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict { .allow() }

    override func handle(_ report: NEFilterReport) {
        if report.event == .flowClosed, let flow = report.flow {
            _ = lock.withLock { flows.removeValue(forKey: flow.identifier) }
        }
    }

    private func report(_ verdict: NEFilterNewFlowVerdict) -> NEFilterNewFlowVerdict {
        verdict.shouldReport = true
        return verdict
    }

    private func track(_ flow: NEFilterSocketFlow, host: String) {
        lock.withLock {
            // Bound in-memory metadata. No URLs, packets, or browsing history are persisted.
            if flows.count < 8192 { flows[flow.identifier] = (flow, host) }
        }
    }

    private func remotePort(_ flow: NEFilterSocketFlow) -> String {
        if case .hostPort(_, let port) = flow.remoteFlowEndpoint { return String(port.rawValue) }
        return ""
    }

    private func currentRules() -> EffectiveRules {
        lock.withLock {
            SessionEngine.materialize(&document, at: Date())
            return EffectiveRules(document: document, at: Date())
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: FilterIdentity.bundleID + ".schedule"))
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.reevaluate() }
        timer.resume()
        self.timer = timer
    }

    private func reevaluate() {
        let rules = currentRules()
        let blocked: [NEFilterSocketFlow] = lock.withLock {
            guard rules != lastRules else { return [] }
            lastRules = rules
            return flows.values.compactMap { rules.blocks(host: $0.1) ? $0.0 : nil }
        }
        for flow in blocked { update(flow, using: .drop(), for: .any) }
    }
}
