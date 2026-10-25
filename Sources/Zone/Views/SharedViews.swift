import AppKit
import SwiftUI
import ZoneCore

extension OpenWindowAction {
    /// Opens Zone's main window and brings the app forward.
    func openMain() {
        self(id: "main")
        NSApp.activate()
    }
}

extension OpenSettingsAction {
    func showWebsites(_ model: ZoneModel) {
        model.settingsPane = .websites
        self()
        NSApp.activate()
    }
}

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
            Button("Set Up Website Blocking…") { openSettings.showWebsites(model) }
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

enum SessionOptionsSummary {
    /// Scheduled sessions are always strict, so their summary leaves out the mode.
    static func text(for options: SessionOptions, scheduled: Bool = false) -> String {
        "\(scheduled ? "Stays on until the end" : options.mode.title) · \(pauses(options.pause))"
    }

    /// "No pauses", "1 pause, 5 min", or "3 pauses, 10 min".
    static func pauses(_ pause: PausePolicy) -> String {
        if pause.allowance == 0 { return "No pauses" }
        return "\(pause.allowance == 1 ? "1 pause" : "\(pause.allowance) pauses"), \(pause.minutes) min"
    }
}

struct SessionOptionsEditor: View {
    @Binding var options: SessionOptions
    var scheduled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if scheduled {
                Text("Scheduled sessions can’t be ended early. Choose how many short breaks you get.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Session mode", selection: $options.mode) {
                    ForEach(SessionMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented)
                Text(options.mode == .locked
                     ? "Runs until the end. Only the pauses you set here are available."
                     : "End early if you need. Pauses follow the limits below.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
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
        let until = paused ? session.pausedUntil ?? session.endsAt : session.endsAt
        return Countdown.text(until: min(until, session.endsAt), now: model.now)
    }

    var body: some View {
        VStack(spacing: compact ? 18 : 24) {
            HStack {
                Text(session.name).font(.headline).lineLimit(2)
                Spacer()
                if session.isStrict {
                    Label(session.scheduleID != nil ? "Scheduled" : "Locked", systemImage: "lock.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .help("Stays on until the end. Only its pauses are available.")
                }
            }
            VStack(spacing: 4) {
                Text(remaining)
                    .font(.system(size: compact ? 52 : 72, weight: .thin, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    .accessibilityLabel("\(remaining) \(paused ? "of pause remaining" : "remaining")")
                Text(paused ? "Pause remaining" : "Time remaining")
                    .font(.callout).foregroundStyle(paused ? .orange : .secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 8)

            VStack(spacing: 6) {
                RuleSummary(list: session.blockList)
                Text("Session ends at \(session.endsAt, format: .dateTime.hour().minute())")
                    .font(.caption).foregroundStyle(.secondary)
                if paused {
                    Text((session.pausedUntil ?? session.endsAt) < session.endsAt
                         ? "Blocking resumes automatically." : "This session ends with the pause.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 12) {
                if paused {
                    Button { model.resume(session) } label: {
                        Label("Resume Focus", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                } else if session.pausesRemaining > 0 {
                    Button { model.pause(session) } label: {
                        Label("Pause for \(session.options.pause.minutes) min", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large)
                }
                HStack {
                    Text(session.pausesRemaining == 0 ? "No pauses left" : "\(session.pausesRemaining) \(session.pausesRemaining == 1 ? "pause" : "pauses") left")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !session.isStrict {
                        Button("End Session") { confirmEnd = true }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
        .padding(compact ? 4 : 20)
        .accessibilityElement(children: .contain)
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

/// Zone's dawn palette, shared with the app icon and the focus page.
enum Dawn {
    static let progress = [Color(red: 0.56, green: 0.62, blue: 0.98), Color(red: 0.85, green: 0.64, blue: 0.84),
                           Color(red: 1.0, green: 0.62, blue: 0.48)]
    static var sun: EllipticalGradient {
        EllipticalGradient(colors: [Color(red: 1.0, green: 0.99, blue: 0.96), Color(red: 1.0, green: 0.87, blue: 0.58),
                                    Color(red: 1.0, green: 0.72, blue: 0.4)],
                           center: UnitPoint(x: 0.4, y: 0.34), startRadiusFraction: 0, endRadiusFraction: 0.8)
    }
}

/// Zone's open ring around a warm sun, drawn to match the app icon.
struct ZoneMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let line = size * 0.11
            ZStack {
                Circle().trim(from: 0, to: 310.0 / 360)
                    .stroke(LinearGradient(colors: Dawn.progress, startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-20))
                    .padding(line / 2)
                Circle().fill(Dawn.sun)
                    .frame(width: size * 0.44, height: size * 0.44)
                    .shadow(color: .orange.opacity(0.35), radius: size * 0.08)
            }.frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

enum ScheduleFormat {
    /// "Weekdays · 9:00 AM – 11:00 AM" or "Oct 28 · 9:00 AM – 11:00 AM".
    static func summary(_ schedule: FocusSchedule) -> String {
        if schedule.kind == .once {
            let calendar = Calendar.autoupdatingCurrent
            let day = schedule.onceStart.formatted(.dateTime.month(.abbreviated).day())
            let end = calendar.isDate(schedule.onceStart, inSameDayAs: schedule.onceEnd)
                ? schedule.onceEnd.formatted(date: .omitted, time: .shortened)
                : schedule.onceEnd.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            return "\(day) · \(schedule.onceStart.formatted(date: .omitted, time: .shortened)) – \(end)"
        }
        return "\(days(schedule.weekdays)) · \(time(schedule.startMinute)) – \(time(schedule.endMinute))"
    }

    static func days(_ weekdays: Set<Int>) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if weekdays.count == 7 { return "Every day" }
        if weekdays == [2, 3, 4, 5, 6] { return "Weekdays" }
        if weekdays == [1, 7] { return "Weekends" }
        return orderedWeekdays.filter(weekdays.contains).map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }

    static func time(_ minute: Int) -> String {
        let date = Calendar.autoupdatingCurrent.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static var orderedWeekdays: [Int] {
        let first = Calendar.autoupdatingCurrent.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}
