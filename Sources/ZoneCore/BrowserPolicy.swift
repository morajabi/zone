import Foundation

/// Shared with the background browser worker so pauses and edits are visible
/// before it redirects a tab, even while a browser is slow to answer.
public final class BrowserPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var document = ZoneDocument(blockLists: [])
    private var enabled = false

    public init() {}

    public func update(_ document: ZoneDocument, enabled: Bool) {
        lock.withLock { self.document = document; self.enabled = enabled }
    }

    public func blocks(_ address: String, at date: Date = Date()) -> Bool {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host else { return false }
        return lock.withLock {
            guard enabled else { return false }
            var current = document
            SessionEngine.materialize(&current, at: date)
            return EffectiveRules(document: current, at: date).blocks(host: host)
        }
    }
}
