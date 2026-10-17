import AppKit
import SwiftUI
import ZoneCore

struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.5), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
    }
}

struct RuleSummary: View {
    let list: BlockList
    var body: some View {
        Text(Self.text(for: list)).font(.caption).foregroundStyle(.secondary)
    }

    static func text(for list: BlockList) -> String {
        let websites = list.domains.count == 1 ? "1 website" : "\(list.domains.count) websites"
        let apps = list.apps.count == 1 ? "1 app" : "\(list.apps.count) apps"
        if list.isEmpty { return "No websites or apps" }
        if list.domains.isEmpty { return apps }
        if list.apps.isEmpty { return websites }
        return "\(websites) · \(apps)"
    }
}

struct BrowserSetupPrompt: View {
    let model: ZoneModel
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.websiteBlockingTitle, systemImage: "globe.badge.chevron.backward")
                .font(.callout.weight(.medium))
            Text(model.websiteBlockingDetail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set Up Website Blocking…") {
                model.settingsPane = .websites
                openSettings()
                NSApp.activate()
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).modifier(PanelStyle())
    }
}

struct BlockingNotice: View {
    let model: ZoneModel
    var body: some View {
        if model.blockingIsDegraded {
            BrowserSetupPrompt(model: model)
        }
        if let failure = model.appBlockFailure {
            Label(failure, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        }
    }
}

struct SessionOptionsEditor: View {
    @Binding var options: SessionOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Session mode", selection: $options.mode) {
                ForEach(SessionMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented)
            Text(options.mode == .locked
                 ? "Runs until the end. Only the pauses you set here are available."
                 : "End early if you need. Pauses follow the limits below.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Pauses allowed")
                Spacer()
                Stepper(value: $options.pause.allowance, in: 0...20) {
                    Text(options.pause.allowance == 0 ? "None" : "\(options.pause.allowance)").monospacedDigit()
                        .frame(minWidth: 42, alignment: .trailing)
                }.fixedSize()
            }
            if options.pause.allowance > 0 {
                HStack {
                    Text("Each pause")
                    Spacer()
                    Stepper(value: $options.pause.minutes, in: 1...60) {
                        Text("\(options.pause.minutes) min").monospacedDigit().frame(minWidth: 58, alignment: .trailing)
                    }.fixedSize()
                }
            }
        }
    }
}

struct SessionCard: View {
    let session: FocusSession
    let model: ZoneModel
    var compact = false
    @State private var confirmEnd = false

    private var paused: Bool { session.isPaused(at: model.now) }
    private var remaining: String {
        let seconds = max(0, Int(ceil(session.endsAt.timeIntervalSince(model.now))))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.name).font(.headline)
                    Label(paused ? "Paused" : session.options.mode == .locked ? "Locked session" : "Focusing",
                          systemImage: paused ? "pause.circle" : session.options.mode == .locked ? "lock" : "circle.inset.filled")
                        .font(.caption).foregroundStyle(paused ? .orange : .secondary)
                }
                Spacer(minLength: 12)
                Text(remaining).font(.system(size: compact ? 27 : 38, weight: .light, design: .rounded)).monospacedDigit()
                    .accessibilityLabel("\(remaining) remaining")
            }
            if paused, let until = session.pausedUntil {
                Text("Blocking resumes at \(until, format: .dateTime.hour().minute().second()). The session still ends at \(session.endsAt, format: .dateTime.hour().minute()).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    RuleSummary(list: session.blockList)
                    Spacer()
                    Text("Until \(session.endsAt, format: .dateTime.hour().minute())")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if paused {
                    Button("Resume Now", systemImage: "play.fill") { model.resume(session) }
                } else {
                    Button("Pause \(session.options.pause.minutes) min", systemImage: "pause.fill") { model.pause(session) }
                        .disabled(session.pausesRemaining == 0)
                        .help("\(session.pausesRemaining) pauses remaining")
                }
                if session.options.pause.allowance > 0 {
                    Text("\(session.pausesRemaining) left").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if session.options.mode == .flexible {
                    Button("End", role: .destructive) { confirmEnd = true }
                } else {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary).accessibilityLabel("Locked until the end")
                }
            }.controlSize(.small)
        }
        .padding(compact ? 14 : 20)
        .modifier(PanelStyle())
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Session", role: .destructive) { model.stop(session) }
        } message: {
            Text(model.activeSessions.count > 1 ? "Other active sessions will keep their restrictions." : "Websites and apps in this session will be available again.")
        }
    }
}

struct FilterStatus: View {
    let model: ZoneModel
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.websiteBlockingReady ? "checkmark.shield" : "exclamationmark.shield")
                .foregroundStyle(model.websiteBlockingReady ? Color.accentColor : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.websiteBlockingTitle).font(.callout.weight(.medium))
                Text(model.websiteBlockingDetail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ErrorPresenter: ViewModifier {
    @Bindable var model: ZoneModel
    @Environment(\.appearsActive) private var appearsActive
    func body(content: Content) -> some View {
        content.alert("Zone", isPresented: Binding(get: { appearsActive && model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct AppIcon: View {
    let app: BlockedApp
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 26, height: 26)
            .accessibilityHidden(true)
    }
}
