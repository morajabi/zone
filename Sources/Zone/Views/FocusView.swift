import SwiftUI
import ZoneCore

struct FocusView: View {
    let model: ZoneModel
    @State private var showNewSession = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BlockingNotice(model: model)
                ForEach(model.activeSessions) { session in
                    SessionCard(session: session, model: model)
                }
                if model.activeSessions.count > 1 {
                    Text("Sessions combine their blocks. Pausing one leaves the others running.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.availableLists.isEmpty {
                    FirstListPrompt(model: model)
                        .frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    if model.activeSessions.isEmpty {
                        QuickSessionSection(model: model)
                    } else {
                        DisclosureGroup("Start Another Session", isExpanded: $showNewSession) {
                            QuickSessionSection(model: model).padding(.top, 12)
                        }
                    }
                    UpcomingSessionView(model: model)
                }
                Label("Zone keeps running in the menu bar when you close this window.", systemImage: "menubar.rectangle")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.navigationTitle("Focus")
    }
}

private struct QuickSessionSection: View {
    let model: ZoneModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Session").font(.title2.weight(.semibold))
            QuickSessionEditor(model: model)
        }.padding(20).modifier(PanelStyle())
    }
}

struct FirstListPrompt: View {
    let model: ZoneModel
    var compact = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised").font(.system(size: compact ? 28 : 40, weight: .light))
                .foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Choose what to block").font(compact ? .headline : .title2.weight(.semibold))
            Text("Add websites and apps to a block list, then start a session whenever you need to focus.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Create a Block List…", systemImage: "plus") {
                openWindow(id: "main")
                NSApp.activate()
                model.newList()
            }.buttonStyle(.borderedProminent).padding(.top, 4)
        }.frame(maxWidth: 380)
    }
}

struct QuickSessionEditor: View {
    @Bindable var model: ZoneModel
    var compact = false
    @State private var showOptions = false
    @State private var confirmStart = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.availableLists.isEmpty {
                FirstListPrompt(model: model, compact: compact).padding(.vertical, 12)
            } else {
                Picker("Block list", selection: $model.selectedListID) {
                    ForEach(model.document.blockLists) { list in
                        Text(list.name).tag(Optional(list.id))
                    }
                }
                if let list = model.selectedList {
                    HStack {
                        RuleSummary(list: list).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit…") {
                            openWindow(id: "main")
                            NSApp.activate()
                            model.editingList = list
                        }
                            .buttonStyle(.link).font(.caption)
                    }
                }
                Divider()
                HStack {
                    Text("Duration")
                    Spacer()
                    TextField("Minutes", text: $model.quickMinutesText)
                        .frame(width: 64).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Session duration in minutes")
                    Text("minutes").foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach([25, 45, 60, 90], id: \.self) { minutes in
                        Button("\(minutes) min") { model.quickMinutes = minutes }
                            .frame(maxWidth: .infinity)
                            .accessibilityAddTraits(model.quickMinutes == minutes ? .isSelected : [])
                    }
                }.buttonStyle(.bordered).controlSize(.small)
                if !(1...1440).contains(model.quickMinutes) {
                    Text("Enter 1–1,440 minutes.").font(.caption).foregroundStyle(.red)
                }
                if compact {
                    DisclosureGroup(isExpanded: $showOptions) {
                        SessionOptionsEditor(options: $model.quickOptions).padding(.top, 10)
                    } label: {
                        Text(model.quickOptions.mode.title)
                        Text("· \(model.quickOptions.pause.allowance == 0 ? "No pauses" : "Pauses allowed")")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SessionOptionsEditor(options: $model.quickOptions)
                }
                if model.selectedList?.domains.isEmpty == false && !model.websiteBlockingReady {
                    BrowserSetupPrompt(model: model)
                }
                if model.selectedList?.isEmpty == true {
                    Text("Add a website or app to this list before starting.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    if model.quickOptions.mode == .locked || model.selectedList?.apps.isEmpty == false { confirmStart = true }
                    else { model.startQuickSession() }
                } label: {
                    Label("Start Session", systemImage: model.quickOptions.mode == .locked ? "lock.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.selectedList?.isEmpty != false || !(1...1440).contains(model.quickMinutes)
                          || (model.selectedList?.domains.isEmpty == false && !model.websiteBlockingReady) || model.storageFailed)
            }
        }
        .confirmationDialog(model.quickOptions.mode == .locked ? "Start a locked session?" : "Close the selected apps and start?",
                            isPresented: $confirmStart, titleVisibility: .visible) {
            Button("Start \(model.quickMinutes)-Minute Session") { model.startQuickSession() }
        } message: {
            Text((model.quickOptions.mode == .locked ? "You can’t end this session early. Only the pauses you’ve set will be available. " : "")
                 + (model.selectedList?.apps.isEmpty == false ? "Save your work first. Selected apps will close and unsaved changes may be lost." : ""))
        }
    }
}

private struct UpcomingSessionView: View {
    let model: ZoneModel
    var body: some View {
        if let next = model.nextScheduledSession {
            HStack(spacing: 12) {
                Image(systemName: "calendar").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(next.name).font(.callout.weight(.medium))
                    Text("Starts \(next.start, format: .dateTime.weekday().month(.abbreviated).day().hour().minute())")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schedules") { model.page = .schedules }.buttonStyle(.link)
            }
        }
    }
}
