import SwiftUI
import ZoneCore

struct SchedulesView: View {
    let model: ZoneModel
    @State private var deleting: FocusSchedule?
    @State private var enabling: FocusSchedule?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            if model.document.schedules.isEmpty {
                ContentUnavailableView {
                    Label("No Schedules", systemImage: "calendar")
                } description: {
                    Text(model.availableLists.isEmpty
                         ? "Create a block list, then schedule a session."
                         : "Plan a one-time session or repeat on the days you choose.")
                } actions: {
                    Button(model.availableLists.isEmpty ? "Create a Block List…" : "New Schedule…") {
                        model.newSchedule()
                    }.buttonStyle(.borderedProminent)
                }
            } else {
                List(model.document.schedules) { schedule in
                    ScheduleRow(schedule: schedule, model: model, setEnabled: { enabled in
                        var next = schedule
                        next.isEnabled = enabled
                        if enabled && SessionEngine.activeInterval(for: next, at: Date()) != nil {
                            enabling = next
                        } else { _ = model.saveSchedule(next) }
                    }, delete: { deleting = schedule })
                }.listStyle(.inset)
            }
            VStack(spacing: 6) {
                Text("Times follow this Mac’s time zone. Zone must be running for sessions to start.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.launchAtLogin {
                    Button("Set Up Open at Login…") {
                        model.settingsPane = .general
                        openSettings()
                    }.buttonStyle(.link).font(.caption)
                }
            }.padding(16)
        }
        .navigationTitle("Schedules")
        .toolbar { Button("New Schedule", systemImage: "plus") { model.newSchedule() }.disabled(model.availableLists.isEmpty) }
        .confirmationDialog("Delete this schedule?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Schedule", role: .destructive) { if let deleting { model.deleteSchedule(deleting) }; deleting = nil }
        } message: { Text("A session already running will finish as planned.") }
        .confirmationDialog("This session will start now", isPresented: Binding(get: { enabling != nil }, set: { if !$0 { enabling = nil } }), titleVisibility: .visible) {
            Button("Enable and Start") { if let enabling { _ = model.saveSchedule(enabling) }; enabling = nil }
        } message: {
            Text("The current time falls inside this schedule. Selected apps will close. Scheduled sessions can’t be ended early.")
        }
    }
}

private struct ScheduleRow: View {
    let schedule: FocusSchedule
    let model: ZoneModel
    let setEnabled: @MainActor @Sendable (Bool) -> Void
    let delete: () -> Void

    private var running: Bool { model.isRunning(schedule) }
    private var status: String {
        if running { return "Running" }
        if !schedule.isEnabled { return "Off" }
        if schedule.kind == .once && schedule.onceEnd <= model.now { return "Completed" }
        return "On"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { model.editingSchedule = schedule } label: {
                HStack(spacing: 14) {
                    Image(systemName: schedule.kind == .weekly ? "calendar.badge.clock" : "calendar")
                        .font(.title2).foregroundStyle(.secondary).frame(width: 30).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(schedule.name).font(.headline)
                        Text(summary).font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if let list = model.document.blockLists.first(where: { $0.id == schedule.blockListID }) {
                                Text(list.name)
                                Text("·")
                            }
                            Text(pauses)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right").font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary).accessibilityHidden(true)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(schedule.name)")
            .accessibilityValue(summary)
            .contextMenu {
                Button("Delete", role: .destructive) { delete() }.disabled(running)
            }
            // A closure avoids a Swift 6.2 IRGen crash converting the isolated callback directly.
            Toggle(status, isOn: Binding(get: { schedule.isEnabled || running }, set: { enabled in setEnabled(enabled) }))
                .toggleStyle(.switch).controlSize(.small).fixedSize()
                .disabled(running)
                .help(running ? "Scheduled sessions stay on until they end." : "")
                .accessibilityLabel("Enable \(schedule.name)")
            Menu {
                Button("Delete", role: .destructive) { delete() }.disabled(running)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            .accessibilityLabel("Actions for \(schedule.name)").help("More actions")
        }.padding(.vertical, 12).accessibilityElement(children: .contain)
    }

    private var summary: String {
        ScheduleFormat.summary(schedule)
            + (schedule.kind == .weekly && schedule.endMinute < schedule.startMinute ? " (next day)" : "")
    }

    private var pauses: String {
        let pause = schedule.options.pause
        return pause.allowance == 0 ? "No pauses" : "\(pause.allowance) \(pause.allowance == 1 ? "pause" : "pauses"), \(pause.minutes) min"
    }
}

struct ScheduleEditor: View {
    let model: ZoneModel
    @State private var schedule: FocusSchedule
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSave = false
    @State private var saveError: String?

    init(model: ZoneModel, schedule: FocusSchedule) {
        self.model = model
        _schedule = State(initialValue: schedule)
    }

    private var isRunning: Bool { model.isRunning(schedule) }

    private var validationMessage: String? {
        if isRunning, let session = model.runningSession(for: schedule) {
            return "This schedule is running. You can change it after it ends at \(session.endsAt.formatted(date: .omitted, time: .shortened))."
        }
        if schedule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a name for this schedule." }
        if schedule.kind == .weekly {
            if schedule.weekdays.isEmpty { return "Choose at least one day." }
            if schedule.startMinute == schedule.endMinute { return "Choose different start and end times." }
        } else {
            if schedule.onceEnd <= schedule.onceStart { return "The end must be after the start." }
            if schedule.onceEnd.timeIntervalSince(schedule.onceStart) > 86400 { return "A session can last up to 24 hours." }
            if schedule.isEnabled && schedule.onceEnd <= model.now { return "Choose a future end time, or turn this schedule off." }
        }
        if schedule.isEnabled && model.document.blockLists.first(where: { $0.id == schedule.blockListID })?.domains.isEmpty == false
            && !model.websiteBlockingReady { return "Connect a browser in Settings, or save this schedule with Enabled turned off." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.document.schedules.contains { $0.id == schedule.id } ? "Edit Schedule" : "New Schedule")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $schedule.name)
                Picker("Block list", selection: $schedule.blockListID) {
                    ForEach(model.availableLists) { Text($0.name).tag($0.id) }
                }
                Picker("Repeat", selection: $schedule.kind) {
                    Text("Weekly").tag(ScheduleKind.weekly)
                    Text("Just Once").tag(ScheduleKind.once)
                }.pickerStyle(.segmented)
                if schedule.kind == .weekly {
                    LabeledContent("Days") {
                        HStack(spacing: 4) {
                            ForEach(ScheduleFormat.orderedWeekdays, id: \.self) { day in
                                Toggle(isOn: Binding(get: { schedule.weekdays.contains(day) }, set: { selected in
                                    if selected { schedule.weekdays.insert(day) } else { schedule.weekdays.remove(day) }
                                })) {
                                    Text(Calendar.autoupdatingCurrent.shortWeekdaySymbols[day - 1])
                                }.toggleStyle(.button).controlSize(.small)
                                    .accessibilityLabel(Calendar.autoupdatingCurrent.weekdaySymbols[day - 1])
                            }
                        }
                    }
                    DatePicker("From", selection: timeBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: timeBinding(\.endMinute), displayedComponents: .hourAndMinute)
                    if schedule.endMinute < schedule.startMinute {
                        Text("Finishes the next day.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    DatePicker("From", selection: $schedule.onceStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Until", selection: $schedule.onceEnd, displayedComponents: [.date, .hourAndMinute])
                }
                Toggle("Enabled", isOn: $schedule.isEnabled)
            }.formStyle(.columns).disabled(isRunning)
            Divider()
            ScheduleOptionsDisclosure(options: $schedule.options).disabled(isRunning)
            Text("Changes apply to future sessions. Scheduled app blocks may close unsaved work.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = validationMessage ?? saveError {
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Schedule") {
                    if schedule.isEnabled, SessionEngine.activeInterval(for: schedule, at: Date()) != nil { confirmSave = true }
                    else { save() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
        }.padding(24).frame(width: 530)
            .confirmationDialog("This session will start now", isPresented: $confirmSave, titleVisibility: .visible) {
                Button("Save and Start") { save() }
            } message: { Text("The current time falls inside this schedule. Selected apps will close. Scheduled sessions can’t be ended early.") }
    }

    private func save() {
        schedule.name = schedule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.saveSchedule(schedule) { dismiss() }
        else { saveError = model.errorMessage; model.errorMessage = nil }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<FocusSchedule, Int>) -> Binding<Date> {
        Binding(get: {
            let minutes = schedule[keyPath: keyPath]
            return Calendar.autoupdatingCurrent.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
            schedule[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
}

private struct ScheduleOptionsDisclosure: View {
    @Binding var options: SessionOptions
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            SessionOptionsEditor(options: $options, scheduled: true).padding(.top, 12)
        } label: {
            Text(SessionOptionsSummary.text(for: options, scheduled: true))
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
