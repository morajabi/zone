import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZoneCore

struct BlockListsView: View {
    let model: ZoneModel
    @State private var deleting: BlockList?

    var body: some View {
        VStack(spacing: 0) {
                if model.document.blockLists.isEmpty {
                    ContentUnavailableView {
                        Label("No Block Lists", systemImage: "hand.raised")
                    } description: {
                        Text("Choose websites and apps to block during a session.")
                    } actions: {
                        Button("Create a Block List…", action: model.newList).buttonStyle(.borderedProminent)
                    }
                }
                List(model.document.blockLists) { list in
                    HStack(spacing: 16) {
                        Image(systemName: "hand.raised").font(.title2).foregroundStyle(.secondary)
                            .frame(width: 30).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(list.name).font(.headline)
                            RuleSummary(list: list)
                            if !list.isEmpty {
                                Text((list.domains + list.apps.map(\.name)).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        Button("Edit…") { model.editingList = list }.accessibilityLabel("Edit \(list.name)")
                        Menu {
                            Button("Duplicate") {
                                model.saveList(BlockList(name: list.name + " Copy", domains: list.domains, apps: list.apps))
                            }
                            Button("Delete", role: .destructive) { deleting = list }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22).accessibilityLabel("Actions for \(list.name)")
                    }.padding(.vertical, 12).accessibilityElement(children: .contain)
                }.listStyle(.inset)
                Text("Edits apply to future sessions. Running sessions keep their original block list.")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
        }
        .navigationTitle("Block Lists")
        .toolbar { Button("New Block List", systemImage: "plus", action: model.newList).help("New Block List (⌘N)") }
        .confirmationDialog("Delete this block list?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete List", role: .destructive) { if let deleting { model.deleteList(deleting) }; deleting = nil }
        }
    }
}

struct BlockListEditor: View {
    let model: ZoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var list: BlockList
    @State private var websiteInput = ""
    @State private var error: String?
    @State private var editingApps = false

    init(model: ZoneModel, list: BlockList) {
        self.model = model
        _list = State(initialValue: list)
    }

    private var isNew: Bool { !model.document.blockLists.contains { $0.id == list.id && !$0.isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isNew ? "New Block List" : "Edit Block List").font(.title2.weight(.semibold))
            LabeledContent("Name") {
                TextField("List name", text: $list.name).textFieldStyle(.roundedBorder)
            }
            Picker("Rules", selection: $editingApps) {
                Text("Websites").tag(false)
                Text("Apps").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            Group {
                if !editingApps {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("youtube.com, reddit.com…", text: $websiteInput).textFieldStyle(.roundedBorder).onSubmit(addWebsites)
                            Button("Add", action: addWebsites).disabled(websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("Domains include all subdomains. Paste multiple domains separated by commas or spaces.")
                            .font(.caption).foregroundStyle(.secondary)
                        List {
                            ForEach(list.domains, id: \.self) { domain in
                                HStack {
                                    Label(domain, systemImage: "globe")
                                    Spacer()
                                    Button { list.domains.removeAll { $0 == domain } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).accessibilityLabel("Remove \(domain)")
                                }
                            }
                        }.overlay { if list.domains.isEmpty { Text("No websites added").foregroundStyle(.secondary) } }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Apps close when a session starts or you open them.").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Add Apps…", systemImage: "plus", action: addApps)
                        }
                        List {
                            ForEach(list.apps) { app in
                                HStack {
                                    AppIcon(app: app)
                                    Text(app.name).help(app.bundleID)
                                    Spacer()
                                    Button { list.apps.removeAll { $0.id == app.id } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).accessibilityLabel("Remove \(app.name)")
                                }
                            }
                        }.overlay { if list.apps.isEmpty { Text("No apps added").foregroundStyle(.secondary) } }
                        Text("Save work before starting. Zone may force quit selected apps, discarding unsaved changes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(height: 280)
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("Changes apply to future sessions.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if !websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addWebsites(); if error != nil { return } }
                    list.name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if model.saveList(list) { dismiss() }
                    else { error = model.errorMessage; model.errorMessage = nil }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(list.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (list.isEmpty && websiteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(24).frame(width: 560)
    }

    private func addWebsites() {
        do {
            list.domains = Array(Set(list.domains).union(try DomainRule.parseList(websiteInput))).sorted()
            websiteInput = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add Apps"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            guard !AppBlocker.protectedIDs.contains(id) else { error = "Zone keeps essential system apps available."; continue }
            guard !list.apps.contains(where: { $0.bundleID == id }) else { continue }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
            list.apps.append(BlockedApp(bundleID: id, name: name, path: url.path))
        }
        list.apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
