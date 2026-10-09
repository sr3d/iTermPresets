import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider()
            if let index = store.presets.firstIndex(where: { $0.id == selection }) {
                PresetEditor(preset: $store.presets[index])
                    .id(store.presets[index].id)
            } else {
                Text("Select or add a preset")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = store.presets.first?.id } }
        .onChange(of: store.presets) { _ in store.scheduleSave() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Presets") {
                    ForEach(store.presets) { preset in
                        Label(preset.name.isEmpty ? "Untitled" : preset.name,
                              systemImage: preset.runAtLaunch ? "bolt.fill" : "rectangle.split.3x1")
                            .tag(preset.id)
                            .contextMenu {
                                Button("Duplicate") { selection = store.duplicate(preset.id)?.id }
                                Button("Delete", role: .destructive) { delete(preset.id) }
                            }
                    }
                    .onMove { store.presets.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack(spacing: 4) {
                Button { selection = store.add().id } label: { Image(systemName: "plus") }
                    .help("Add preset")
                Button { if let selection { delete(selection) } } label: { Image(systemName: "minus") }
                    .help("Delete preset")
                    .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func delete(_ id: UUID) {
        let index = store.presets.firstIndex { $0.id == id } ?? 0
        store.delete(id)
        if selection == id {
            selection = store.presets.indices.contains(index) ? store.presets[index].id : store.presets.last?.id
        }
    }
}

// MARK: - Preset

struct PresetEditor: View {
    @EnvironmentObject private var store: Store
    @Binding var preset: Preset
    @State private var status: String?
    @State private var showScript = false
    @State private var selectedWindow: UUID?
    @State private var selectedTab: UUID?

    private var windowIndex: Int? { preset.windows.firstIndex { $0.id == selectedWindow } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let w = windowIndex {
                WindowBar(preset: $preset, selection: $selectedWindow, arrange: arrange)
                Divider()
                TabStrip(tabs: $preset.windows[w].tabs, selection: $selectedTab)
                VStack(spacing: 0) {
                    if let t = preset.windows[w].tabs.firstIndex(where: { $0.id == selectedTab }) {
                        TabDesigner(tab: $preset.windows[w].tabs[t])
                            .id(preset.windows[w].tabs[t].id)
                    }
                    Spacer(minLength: 0)
                }
                // Same color as the selected tab, so the tab flows into its content.
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onAppear { if windowIndex == nil { selectedWindow = preset.windows.first?.id } }
        .onChange(of: selectedWindow) { _ in selectFirstTabIfNeeded() }
        .onChange(of: preset.windows) { _ in
            if windowIndex == nil { selectedWindow = preset.windows.first?.id }
            selectFirstTabIfNeeded()
        }
        .onAppear { selectFirstTabIfNeeded() }
        .sheet(isPresented: $showScript) { ScriptSheet(source: ScriptGenerator.python(for: preset)) }
    }

    private func selectFirstTabIfNeeded() {
        guard let w = windowIndex else { return }
        if !preset.windows[w].tabs.contains(where: { $0.id == selectedTab }) {
            selectedTab = preset.windows[w].tabs.first?.id
        }
    }

    /// Opens ghosts for every window this preset creates (not a reused current window).
    private func arrange(focus: UUID?) {
        let presetID = preset.id
        let items = preset.windows.enumerated()
            .filter { !preset.reusesCurrentWindow($0.offset) }
            .map { i, window in
                GhostArranger.Item(id: window.id,
                                   title: window.name.isEmpty ? "Window \(i + 1)" : window.name,
                                   tabs: window.tabs, frame: window.frame)
            }
        GhostArranger.shared.begin(items, focus: focus) { [store] frames in
            guard let p = store.presets.firstIndex(where: { $0.id == presetID }) else { return }
            for (id, frame) in frames {
                if let w = store.presets[p].windows.firstIndex(where: { $0.id == id }) {
                    store.presets[p].windows[w].frame = frame
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Preset name", text: $preset.name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { launch() } label: { Label("Open in iTerm", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Opens these windows and tabs in iTerm (⌘R). Nothing already open is closed.")
                Menu {
                    Button("Show Script…") { showScript = true }
                    Button("Copy Script") { copyScript() }
                    Button("Export .py…") { exportScript() }
                    Button("Reveal in Finder") { reveal() }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            HStack(spacing: 16) {
                Picker("First window", selection: $preset.target) {
                    ForEach(Preset.Target.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .fixedSize()
                Toggle("Run when iTerm starts", isOn: $preset.runAtLaunch)
                    .help("Copies the script into iTerm's Scripts/AutoLaunch folder, so this preset opens every time iTerm launches.")
                Spacer()
            }
            Text(status ?? store.lastError ?? "Also available in iTerm → Scripts → iTermPresets → \(ITermBridge.scriptURL(for: preset, in: store.presets).lastPathComponent)")
                .font(.caption)
                .foregroundStyle(store.lastError != nil ? .red : .secondary)
                .lineLimit(2)
        }
        .padding(16)
    }

    private func launch() {
        store.saveNow()
        do {
            try ITermBridge.launch(preset, in: store.presets)
            status = "Sent to iTerm. (The first run may ask you to install iTerm's Python runtime.)"
        } catch {
            status = "Couldn't launch: \(error.localizedDescription) — try iTerm → Scripts → iTermPresets."
        }
    }

    private func copyScript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ScriptGenerator.python(for: preset), forType: .string)
        status = "Script copied to the clipboard."
    }

    private func exportScript() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ScriptGenerator.fileName(for: preset)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ScriptGenerator.python(for: preset).write(to: url, atomically: true, encoding: .utf8)
            status = "Exported to \(url.path)"
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func reveal() {
        store.saveNow()
        NSWorkspace.shared.activateFileViewerSelecting([ITermBridge.scriptURL(for: preset, in: store.presets)])
    }
}

struct ScriptSheet: View {
    let source: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Zoom.storageKey) private var zoom = 1.0

    var body: some View {
        ZoomedContainer(scale: zoom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Generated Python script").font(.headline)
                ScrollView([.horizontal, .vertical]) {
                    Text(source)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 720 * zoom, height: 560 * zoom)
    }
}

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
