import AppKit
import ZoneCore

@MainActor
final class AppBlocker {
    static let protectedIDs: Set<String> = [Bundle.main.bundleIdentifier ?? FilterIdentity.appBundleID, "com.apple.finder", "com.apple.loginwindow",
                                            "com.apple.systempreferences", "com.apple.SecurityAgent"]
    private var blockedIDs: Set<String> = []
    private var observers: [NSObjectProtocol] = []
    private var pending: Set<pid_t> = []
    var onBlocked: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    init() {
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor [weak self] in self?.enforce(app) }
            })
        }
    }

    func update(_ ids: Set<String>) {
        blockedIDs = ids.subtracting(Self.protectedIDs)
        guard !blockedIDs.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications { enforce(app) }
    }

    private func enforce(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, blockedIDs.contains(id), !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              pending.insert(app.processIdentifier).inserted else { return }
        app.terminate()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self else { return }
            defer { self.pending.remove(app.processIdentifier) }
            // Recheck after waiting: a pause/end may have lifted this restriction.
            guard self.blockedIDs.contains(id) else { return }
            if !app.isTerminated { app.forceTerminate() }
            try? await Task.sleep(for: .milliseconds(200))
            if app.isTerminated { self.onBlocked?(app.localizedName ?? id) }
            else { self.onFailure?(app.localizedName ?? id) }
        }
    }
}
