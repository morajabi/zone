import AppKit
import SwiftUI

@main
struct ZoneApp: App {
    @NSApplicationDelegateAdaptor(ZoneAppDelegate.self) private var delegate
    @State private var model = ZoneModel()

    var body: some Scene {
        Window("Zone", id: "main") {
            MainView(model: model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 800, height: 620)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        .commands {
            ZoneCommands(model: model)
            SidebarCommands()
            CommandGroup(replacing: .appTermination) {
                Button("Quit Zone") { model.quit() }.keyboardShortcut("q")
                    .disabled(model.hasLockedSession)
            }
        }

        Settings {
            SettingsView(model: model)
                .onAppear { delegate.model = model }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView(model: model)
                .onAppear { delegate.model = model }
        } label: {
            Label(model.menuTitle, systemImage: model.activeSessions.isEmpty ? "circle.dotted.circle" : "circle.inset.filled")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct ZoneCommands: Commands {
    let model: ZoneModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Block List…") { openMain(); model.newList() }
                .keyboardShortcut("n")
            Button("New Schedule…") { openMain(); model.newSchedule() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.availableLists.isEmpty)
        }
        CommandMenu("Focus") {
            Button("New Session") { model.page = .focus; openMain() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("Block Lists") { model.page = .lists; openMain() }
                .keyboardShortcut("2", modifiers: .command)
            Button("Schedules") { model.page = .schedules; openMain() }
                .keyboardShortcut("3", modifiers: .command)
        }
        CommandGroup(replacing: .help) {
            Link("Zone Help", destination: URL(string: "https://github.com/morajabi/zone#readme")!)
            Link("Report an Issue", destination: URL(string: "https://github.com/morajabi/zone/issues")!)
        }
    }

    private func openMain() { openWindow(id: "main"); NSApp.activate() }
}

@MainActor
final class ZoneAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ZoneModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.hasLockedSession == true ? .terminateCancel : .terminateNow
    }
}
