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
