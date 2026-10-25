import AppKit
import SwiftUI
import ZoneCore

/// The menu bar panel: what's running now, a one-line start, and a compact list of schedules.
struct MenuBarView: View {
    @Bindable var model: ZoneModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if model.activeSessions.isEmpty {
                    MenuGreeting(model: model)
                } else if model.activeSessions.count <= 2 {
                    sessionCards
                } else {
                    // A fixed height keeps the panel on screen; a bare ScrollView collapses in menu bar windows.
                    ScrollView { sessionCards }.frame(height: 300)
                }
            }.padding(10)
            MenuNotices(model: model)
            MenuDivider()
            MenuQuickStart(model: model)
            MenuDivider()
            MenuSchedules(model: model)
            MenuDivider()
            HStack(spacing: 2) {
                MenuRow(action: { openWindow.openMain() }) {
                    Text("Open Zone")
                }
                Button { openSettings(); NSApp.activate() } label: {
                    Image(systemName: "gearshape").frame(width: 26, height: 22)
                }
                .buttonStyle(.borderless).help("Settings").accessibilityLabel("Settings")
                Button { model.quit() } label: {
                    Image(systemName: "power").frame(width: 26, height: 22)
                }
                .buttonStyle(.borderless).disabled(model.hasStrictSession)
                .help(model.hasStrictSession ? "Zone stays open until this session ends" : "Quit Zone")
                .accessibilityLabel("Quit Zone")
            }.padding(6)
        }
        .frame(width: 300)
        .modifier(ErrorPresenter(model: model))
    }

    private var sessionCards: some View {
        VStack(spacing: 8) {
            ForEach(model.activeSessions) { session in
                MenuSessionCard(session: session, model: model)
            }
        }
    }
}

private struct MenuGreeting: View {
    let model: ZoneModel

    var body: some View {
        HStack(spacing: 12) {
            ZoneMark().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 4).padding(.vertical, 2)
    }

    private var greeting: String {
        switch Calendar.autoupdatingCurrent.component(.hour, from: model.now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello, night owl"
        }
    }

    private var subtitle: String {
        if model.availableLists.isEmpty { return "Choose what to block, then focus in one click." }
        guard let next = model.nextScheduledSession else { return "Ready when you are." }
        return "Next up: \(next.name), \(MenuFormat.when(next.start, now: model.now))"
    }
}

private struct MenuSessionCard: View {
    let session: FocusSession
    let model: ZoneModel
    @State private var confirmEnd = false

    private var paused: Bool { session.isPaused(at: model.now) }
    private var pauseEnd: Date { min(session.pausedUntil ?? session.endsAt, session.endsAt) }
    private var endTime: String { session.endsAt.formatted(date: .omitted, time: .shortened) }
    private var progress: Double {
        let total = session.endsAt.timeIntervalSince(session.startsAt)
        return total > 0 ? min(1, max(0, model.now.timeIntervalSince(session.startsAt) / total)) : 1
    }

    private var caption: String {
        if paused {
            return pauseEnd < session.endsAt
                ? "Paused · focus resumes at \(pauseEnd.formatted(date: .omitted, time: .shortened))"
                : "Paused · ends at \(endTime)"
        }
        let pauses = session.pausesRemaining == 0 ? "no pauses left"
            : session.pausesRemaining == 1 ? "1 pause left" : "\(session.pausesRemaining) pauses left"
        return "Until \(endTime) · \(pauses)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(session.name).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if session.isStrict {
                    Label(session.scheduleID != nil ? "Scheduled" : "Locked", systemImage: "lock.fill")
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .help("Stays on until \(endTime). Only its pauses are available.")
                }
            }
            HStack(alignment: .center) {
                Text(Countdown.text(until: paused ? pauseEnd : session.endsAt, now: model.now))
                    .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
                    .foregroundStyle(paused ? Color.secondary : Color.primary)
                    .accessibilityLabel(paused ? "Pause remaining" : "Focus remaining")
                    .accessibilityValue(Countdown.text(until: paused ? pauseEnd : session.endsAt, now: model.now))
                Spacer()
                if paused {
                    Button { model.resume(session) } label: {
                        Label("Resume", systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent)
                } else if session.pausesRemaining > 0 {
                    Button { model.pause(session) } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }.buttonStyle(.bordered)
                        .help("Take a \(session.options.pause.minutes)-minute break. Blocking resumes automatically.")
                }
            }
            ProgressCapsule(value: progress, dimmed: paused)
            HStack {
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                if !session.isStrict {
                    Button("End") { confirmEnd = true }.buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Session", role: .destructive) { model.stop(session) }
        } message: {
            Text(model.activeSessions.count > 1 ? "Other active sessions will keep their restrictions." : "Websites and apps in this session will be available again.")
        }
    }
}

private struct MenuNotices: View {
    let model: ZoneModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if model.blockingIsDegraded {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(model.websiteBlockingTitle).font(.caption)
                Spacer(minLength: 8)
                Button("Fix…") { openSettings.showWebsites(model) }.buttonStyle(.link).font(.caption)
            }.padding(.horizontal, 14).padding(.bottom, 10)
        }
        if let failure = model.appBlockFailure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
                .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }
}

private struct MenuQuickStart: View {
    @Bindable var model: ZoneModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var confirmStart = false

    private var needsBrowser: Bool { model.selectedList?.domains.isEmpty == false && !model.websiteBlockingReady }
    private var closesApps: Bool { model.selectedList?.apps.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuSectionHeader(title: model.activeSessions.isEmpty ? "Focus now" : "Add a session")
            if model.availableLists.isEmpty {
                Button("Choose What to Block…") {
                    openWindow.openMain()
                    if !model.isEditing { model.newList() }
                }.buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 6) {
                    Picker("Duration", selection: $model.quickMinutes) {
                        ForEach(model.durationChoices, id: \.self) { minutes in
                            Text(MenuFormat.duration(minutes)).tag(minutes)
                        }
                    }.labelsHidden().fixedSize()
                    Picker("Block list", selection: $model.selectedListID) {
                        ForEach(model.availableLists) { list in
                            Text(list.name).tag(Optional(list.id))
                        }
                    }.labelsHidden().frame(maxWidth: .infinity)
                    Button("Start") {
                        if model.quickOptions.mode == .locked || closesApps { confirmStart = true }
                        else { model.startQuickSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedList?.isEmpty != false || needsBrowser || model.storageFailed
                              || !(1...1440).contains(model.quickMinutes))
                }
                if needsBrowser {
                    HStack(spacing: 6) {
                        Text("Connect a browser to block websites.").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button("Set Up…") { openSettings.showWebsites(model) }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .confirmationDialog(model.quickOptions.mode == .locked ? "Start a locked session?" : "Close the selected apps and start?",
                            isPresented: $confirmStart, titleVisibility: .visible) {
            Button("Start \(MenuFormat.duration(model.quickMinutes)) Session") { model.startQuickSession() }
        } message: {
            Text((model.quickOptions.mode == .locked ? "You can’t end this session early. Only the pauses you’ve set will be available. " : "")
                 + (closesApps ? "Save your work first. Selected apps will close and unsaved changes may be lost." : ""))
        }
    }
}

private struct MenuSchedules: View {
    let model: ZoneModel
    @Environment(\.openWindow) private var openWindow
    private let limit = 5

    var body: some View {
        let schedules = model.schedulesByNextStart
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                MenuSectionHeader(title: "Schedules")
                Spacer()
                Button {
                    openWindow.openMain()
                    // Leave an editor that's already open, and its unsaved changes, as it is.
                    guard !model.isEditing else { return }
                    model.page = .schedules
                    model.newSchedule()
                } label: {
                    Image(systemName: "plus").frame(width: 22, height: 18)
                }
                .buttonStyle(.borderless).help("New Schedule").accessibilityLabel("New Schedule")
            }.padding(.horizontal, 8).padding(.bottom, 3)
            if schedules.isEmpty {
                Text("Plan focus time for the days you choose. Scheduled sessions stay on until they end.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8).padding(.bottom, 4)
            } else {
                ForEach(Array(schedules.prefix(limit))) { schedule in
                    MenuScheduleRow(schedule: schedule, model: model)
                }
                if schedules.count > limit {
                    MenuRow(action: {
                        model.page = .schedules
                        openWindow.openMain()
                    }) {
                        Text("Show All \(schedules.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(.horizontal, 6).padding(.vertical, 8)
    }
}

private struct MenuScheduleRow: View {
    let schedule: FocusSchedule
    let model: ZoneModel
    @Environment(\.openWindow) private var openWindow

    private var running: Bool { model.isRunning(schedule) }

    private var trailing: String {
        if running { return "Now" }
        if let next = SessionEngine.nextInterval(for: schedule, after: model.now) {
            return MenuFormat.day(next.start, now: model.now)
        }
        if !schedule.isEnabled { return "Off" }
        return schedule.kind == .once ? "Done" : ""
    }

    var body: some View {
        MenuRow(action: {
            // Leave an editor that's already open, and its unsaved changes, as it is.
            if !model.isEditing {
                model.page = .schedules
                model.editingSchedule = schedule
            }
            openWindow.openMain()
        }) {
            HStack(spacing: 10) {
                ScheduleDot(running: running, enabled: schedule.isEnabled)
                VStack(alignment: .leading, spacing: 1) {
                    Text(schedule.name).font(.callout).lineLimit(1)
                    Text(ScheduleFormat.summary(schedule)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(trailing)
                    .font(.caption.weight(running ? .semibold : .regular))
                    .foregroundStyle(running ? Color.primary : Color.secondary)
            }
        }
        .opacity(schedule.isEnabled || running ? 1 : 0.6)
        .help(running ? "Running until it ends. Scheduled sessions can’t be ended early." : "Edit \(schedule.name)")
        .accessibilityLabel("\(schedule.name), \(ScheduleFormat.summary(schedule)), \(trailing)")
    }
}

private struct ScheduleDot: View {
    let running: Bool
    let enabled: Bool
    var body: some View {
        Group {
            if running {
                Circle().fill(LinearGradient(colors: Dawn.progress, startPoint: .topLeading, endPoint: .bottomTrailing))
            } else if enabled {
                Circle().strokeBorder(.secondary, lineWidth: 1.5)
            } else {
                Circle().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            }
        }.frame(width: 9, height: 9).accessibilityHidden(true)
    }
}

private struct ProgressCapsule: View {
    let value: Double
    let dimmed: Bool
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: Dawn.progress, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, proxy.size.width * value))
                    .opacity(dimmed ? 0.4 : 1)
            }
        }.frame(height: 4).accessibilityHidden(true)
    }
}

private struct MenuSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }
}

private struct MenuDivider: View {
    var body: some View { Divider().padding(.horizontal, 10) }
}

/// A full-width row that highlights on hover, like a menu item.
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    let content: Content
    @State private var hovering = false

    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button { action() } label: {
            content
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(hovering ? Color.primary.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

enum Countdown {
    static func text(until end: Date, now: Date) -> String {
        let seconds = max(0, Int(ceil(end.timeIntervalSince(now))))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum MenuFormat {
    /// Short enough to keep the duration popup narrow: "25 min", "90 min", "2 hr".
    static func duration(_ minutes: Int) -> String {
        if minutes < 120 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    /// "in 20 min", "at 9:00 AM", "tomorrow at 9:00 AM", or "Tue at 9:00 AM".
    static func when(_ date: Date, now: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let time = date.formatted(date: .omitted, time: .shortened)
        let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
        if minutes <= 60 { return "in \(max(1, minutes)) min" }
        if calendar.isDate(date, inSameDayAs: now) { return "at \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) at \(time)"
    }

    /// A short day label for a list: "in 20 min", "Today", "Tomorrow", "Tue", or "Oct 28".
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
        if minutes <= 60 { return "in \(max(1, minutes)) min" }
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if date.timeIntervalSince(now) < 6 * 86400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Template glyphs for the menu bar: Zone's open ring around a small point,
/// a fuller sun while focusing, and pause bars during a break.
@MainActor
enum MenuBarIcon {
    private static let idle = draw(.idle)
    private static let focusing = draw(.focusing)
    private static let paused = draw(.paused)

    static func image(for state: ZoneModel.MenuState) -> NSImage {
        switch state {
        case .idle: idle
        case .focusing: focusing
        case .paused: paused
        }
    }

    private static func draw(_ state: ZoneModel.MenuState) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side))
        for scale in [1, 2, 3] as [CGFloat] {
            let pixels = Int(side * scale)
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { continue }
            bitmap.size = image.size
            context.translateBy(x: 0, y: CGFloat(pixels))
            context.scaleBy(x: scale, y: -scale) // Top-left origin, matching the brand artwork.
            let center = CGPoint(x: side / 2, y: side / 2)
            context.setStrokeColor(.black)
            context.setFillColor(.black)
            context.setLineWidth(1.7)
            context.setLineCap(.round)
            context.addArc(center: center, radius: 7, startAngle: -.pi / 9, endAngle: -7 * .pi / 18, clockwise: false)
            context.strokePath()
            switch state {
            case .idle:
                context.fillEllipse(in: CGRect(x: center.x - 2.2, y: center.y - 2.2, width: 4.4, height: 4.4))
            case .focusing:
                context.fillEllipse(in: CGRect(x: center.x - 3.8, y: center.y - 3.8, width: 7.6, height: 7.6))
            case .paused:
                for x in [center.x - 2.6, center.x + 0.8] {
                    context.addPath(CGPath(roundedRect: CGRect(x: x, y: center.y - 3.3, width: 1.8, height: 6.6),
                                           cornerWidth: 0.9, cornerHeight: 0.9, transform: nil))
                }
                context.fillPath()
            }
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        image.accessibilityDescription = switch state {
        case .idle: "Zone"
        case .focusing: "Zone, focusing"
        case .paused: "Zone, paused"
        }
        return image
    }
}
