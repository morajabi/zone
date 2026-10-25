import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: ZoneModel
    @State private var confirmDisable = false

    var body: some View {
        TabView(selection: $model.settingsPane) {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }.tag(ZoneModel.SettingsPane.general)
            Form {
                Section {
                    Picker("Block websites using", selection: Binding(get: { model.websiteMode }, set: { model.setWebsiteMode($0) })) {
                        ForEach(ZoneModel.WebsiteMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }.disabled(model.hasWebsiteSession || model.changingWebsiteMode)
                    if model.hasWebsiteSession {
                        Text("The blocking method stays fixed until your website sessions end.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.websiteMode == .browser {
                    BrowserSettings(model: model)
                } else {
                    Section("Network Filter") { NetworkFilterSettings(model: model, confirmDisable: $confirmDisable) }
                }
            }.formStyle(.grouped)
                .tabItem { Label("Websites", systemImage: "globe") }.tag(ZoneModel.SettingsPane.websites)
        }
        .frame(width: 560, height: 540)
        .modifier(ErrorPresenter(model: model))
        .confirmationDialog("Disable website blocking?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Disable Filter", role: .destructive) { Task { await model.filter.disable() } }
        } message: { Text("Website schedules cannot block sites until you enable the filter again.") }
    }
}

private struct GeneralSettings: View {
    let model: ZoneModel
    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLogin($0) }))
                Text("Keep Zone in the menu bar so scheduled sessions start on time, including after a restart.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sessions") {
                LabeledContent("Flexible", value: "End whenever you need")
                LabeledContent("Locked", value: "Runs until its end")
                LabeledContent("Scheduled", value: "Always runs until its end")
                Text("Set pause length and allowance before each session. Pauses resume automatically and don’t extend the session.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Zone must stay running to control browsers and close blocked apps. It’s a personal focus tool, and can be bypassed by force quitting it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Your lists and sessions stay on this Mac. No account, analytics, subscription, or cloud service.")
                    .foregroundStyle(.secondary)
                Link("Zone on GitHub", destination: URL(string: "https://github.com/morajabi/zone")!)
            }
        }.formStyle(.grouped)
    }
}

private struct BrowserSettings: View {
    let model: ZoneModel
    var body: some View {
        Section {
            Text("Zone redirects blocked tabs to a local focus page. Connect each browser you use.")
                .foregroundStyle(.secondary)
            ForEach(model.browsers.installed) { browser in
                BrowserPermissionRow(browser: browser, blocker: model.browsers)
            }
            if model.browsers.installed.isEmpty {
                Text("No supported browsers found.").foregroundStyle(.secondary)
            }
            Button("Refresh Browsers") { model.browsers.refreshInstalled() }
        } header: { Text("Browsers") } footer: {
            Text("Supports Safari, Chrome, Dia, Arc, Brave, Edge, Opera, and Helium. You can block other browsers as apps.")
        }
        Section {
            Text("A page may appear briefly before it redirects. During a pause or after a session, use Back to return to the page.")
            Text("Zone reads tab addresses during website sessions. It doesn’t read page contents, save browsing history, or change your network settings.")
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private struct BrowserPermissionRow: View {
    let browser: SupportedBrowser
    let blocker: BrowserBlocker
    private var access: BrowserAccess { blocker.access[browser.id] ?? .notRunning }

    var body: some View {
        HStack(spacing: 12) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(browser.name)
                Text(access.description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if access == .checking {
                ProgressView().controlSize(.small).accessibilityLabel("Connecting \(browser.name)")
            } else if access == .ready || access == .closed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("\(browser.name) connected")
            } else if access == .denied {
                Button("Open Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }.accessibilityLabel("Open Automation settings for \(browser.name)")
            } else {
                Button("Connect…") { blocker.connect(browser) }.accessibilityLabel("Connect \(browser.name)")
            }
        }
    }
}

private struct NetworkFilterSettings: View {
    let model: ZoneModel
    @Binding var confirmDisable: Bool

    var body: some View {
        Text("Optional advanced mode. Requires a signed network extension and macOS approval.")
            .foregroundStyle(.secondary)
        FilterStatus(model: model)
        HStack {
            if model.filter.isReady {
                Button("Disable Website Filter", role: .destructive) { confirmDisable = true }
                    .disabled(model.hasWebsiteSession)
            } else {
                Button("Enable Website Filter") { model.filter.enable() }
                    .disabled(!model.filter.canInstall).buttonStyle(.borderedProminent)
            }
            Button("Check Status") { Task { await model.filter.refresh() } }.disabled(!model.filter.isSignedBuild)
        }
        DisclosureGroup("Coverage and limitations") {
            VStack(alignment: .leading, spacing: 10) {
                Text("The filter checks connection hostnames and HTTP/TLS handshake metadata. It never decrypts HTTPS or saves browsing history.")
                Text("During website sessions, unknown-host UDP port 443 is blocked to encourage browsers to retry over TCP.")
                Text("Encrypted ClientHello, VPN/proxy tunnels, cached pages, and connections the filter cannot identify can bypass domain rules. Browser coverage has not yet been qualified.")
            }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
        }
    }
}
