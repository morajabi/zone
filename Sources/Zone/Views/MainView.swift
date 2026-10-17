import SwiftUI

struct MainView: View {
    @Bindable var model: ZoneModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.page) {
                ForEach(ZoneModel.Page.allCases) { page in
                    Label(page.rawValue, systemImage: page.symbol).tag(page)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } detail: {
            switch model.page {
            case .focus: FocusView(model: model)
            case .lists: BlockListsView(model: model)
            case .schedules: SchedulesView(model: model)
            }
        }
        .frame(minWidth: 660, minHeight: 500)
        .sheet(item: $model.editingList) { BlockListEditor(model: model, list: $0) }
        .sheet(item: $model.editingSchedule) { ScheduleEditor(model: model, schedule: $0) }
        .modifier(ErrorPresenter(model: model))
    }
}

struct MenuBarView: View {
    @Bindable var model: ZoneModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showNewSession = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Zone").font(.headline)
                Spacer()
                Text(model.activeSessions.isEmpty ? "Ready" : "\(model.activeSessions.count) active")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BlockingNotice(model: model)
                    ForEach(model.activeSessions) { session in
                        SessionCard(session: session, model: model, compact: true)
                    }
                    if model.activeSessions.isEmpty {
                        QuickSessionEditor(model: model, compact: true)
                    } else {
                        DisclosureGroup("Another Session", isExpanded: $showNewSession) {
                            QuickSessionEditor(model: model, compact: true).padding(.top, 12)
                        }
                    }
                }.padding(16)
            }.frame(maxHeight: 500)
            Divider()
            HStack(spacing: 16) {
                Button("Open Zone") { openWindow(id: "main"); NSApp.activate() }
                Spacer()
                Menu {
                    Button("Settings…") { openSettings(); NSApp.activate() }
                    Divider()
                    Button("Quit Zone") { model.quit() }.disabled(model.hasLockedSession)
                } label: {
                    Image(systemName: "ellipsis")
                }.menuStyle(.borderlessButton).frame(width: 24)
                    .accessibilityLabel("More options").help("Settings and Quit")
            }.buttonStyle(.borderless).padding(14)
        }.frame(width: 330)
        .modifier(ErrorPresenter(model: model))
    }
}
