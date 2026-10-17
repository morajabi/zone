import SwiftUI
import ZoneCore

struct FocusView: View {
    let model: ZoneModel
    @State private var showNewSession = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                        QuickSessionEditor(model: model).padding(.top, 8)
                    } else {
                        DisclosureGroup("Start Another Session", isExpanded: $showNewSession) {
                            QuickSessionEditor(model: model).padding(.top, 8)
                        }
                    }
                    UpcomingSessionView(model: model)
                }
            }
            .padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity)
        }
        .navigationTitle("Focus")
        .safeAreaInset(edge: .bottom) {
            Text("Always here in your menu bar.")
                .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 16)
        }
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

    var body: some View {
        VStack(spacing: 18) {
            if model.availableLists.isEmpty {
                FirstListPrompt(model: model, compact: compact).padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    TextField("25", text: $model.quickMinutesText)
                        .font(.system(size: compact ? 68 : 80, weight: .thin, design: .rounded))
                        .monospacedDigit().multilineTextAlignment(.center).textFieldStyle(.plain)
                        .frame(width: compact ? 220 : 270)
                        .accessibilityLabel("Session duration in minutes")
                        .help("Enter a duration from 1 to 1,440 minutes")
                    Text("minutes of focus").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 4)

                if !(1...1440).contains(model.quickMinutes) {
                    Text("Enter 1–1,440 minutes.").font(.caption).foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Block").foregroundStyle(.secondary)
                        Spacer()
                        Picker("Block list", selection: $model.selectedListID) {
                            ForEach(model.availableLists) { list in
                                Text(list.name).tag(Optional(list.id))
                            }
                        }.labelsHidden().frame(maxWidth: compact ? 210 : 280, alignment: .trailing)
                    }
                    if let list = model.selectedList {
                        RuleSummary(list: list)
                    }
                    DisclosureGroup(isExpanded: $showOptions) {
                        SessionOptionsEditor(options: $model.quickOptions).padding(.top, 12)
                    } label: {
                        Text(SessionOptionsSummary.text(for: model.quickOptions))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                if model.selectedList?.domains.isEmpty == false && !model.websiteBlockingReady {
                    BrowserSetupPrompt(model: model)
                }
                Button {
                    if model.quickOptions.mode == .locked || model.selectedList?.apps.isEmpty == false { confirmStart = true }
                    else { model.startQuickSession() }
                } label: {
                    Text(model.quickOptions.mode == .locked ? "Start Locked Session" : "Start Focus")
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
            VStack(spacing: 16) {
                Divider()
                Button { model.page = .schedules } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(next.name).font(.callout.weight(.medium))
                            Text("Starts \(next.start, format: .dateTime.weekday().month(.abbreviated).day().hour().minute())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("View schedules")
            }
        }
    }
}
