import SwiftUI

/// Chooses which of the preset's iTerm windows is being edited, and where it goes on screen.
struct WindowBar: View {
    @Binding var preset: Preset
    @Binding var selection: UUID?
    let arrange: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(preset.windows.enumerated()), id: \.element.id) { i, window in
                    chip(window, number: i + 1)
                        .onTapGesture { selection = window.id }
                        .contextMenu {
                            Button("Duplicate Window") { duplicate(i) }
                            Button("Move Earlier") { preset.windows.swapAt(i, i - 1) }.disabled(i == 0)
                            Button("Move Later") { preset.windows.swapAt(i, i + 1) }
                                .disabled(i == preset.windows.count - 1)
                            Divider()
                            Button("Delete Window", role: .destructive) { delete(i) }
                                .disabled(preset.windows.count == 1)
                        }
                }
                Button { add() } label: { Label("New Window", systemImage: "plus") }
                    .buttonStyle(.borderless)
                Spacer()
                if preset.windows.count > 1 {
                    Button { arrange(selection) } label: {
                        Label("Arrange All on Screen…", systemImage: "rectangle.3.group")
                    }
                    .help("Shows a ghost for every window so you can lay them out together")
                }
            }
            if let i = preset.windows.firstIndex(where: { $0.id == selection }) {
                placementRow(i)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func chip(_ window: WindowSpec, number: Int) -> some View {
        let selected = window.id == selection
        return HStack(spacing: 6) {
            Image(systemName: "macwindow")
            Text(window.name.isEmpty ? "Window \(number)" : window.name).lineLimit(1)
            Text("\(window.tabs.count) tab\(window.tabs.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
        .overlay(Capsule().stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Capsule())
    }

    private func placementRow(_ i: Int) -> some View {
        HStack(spacing: 10) {
            TextField("Window name (optional)", text: $preset.windows[i].name)
                .frame(width: 190)
            Image(systemName: "rectangle.dashed").foregroundStyle(.secondary)
            if preset.reusesCurrentWindow(i) {
                Text("Uses your current iTerm window — it is never moved or resized.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text(preset.windows[i].frame.map(GhostArranger.describe) ?? "Default position (iTerm decides)")
                    .foregroundStyle(preset.windows[i].frame == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Button("Place on Screen…") { arrange(preset.windows[i].id) }
                    .help("Shows a ghost window you can drag and resize to where this window should open")
                if preset.windows[i].frame != nil {
                    Button("Reset") { preset.windows[i].frame = nil }
                        .help("Let iTerm choose the position")
                }
            }
        }
        .font(.callout)
    }

    private func add() {
        let directory = preset.windows.first { $0.id == selection }?.tabs.first?.directory ?? "~"
        let window = WindowSpec(tabs: [TabSpec(title: "", colorHex: nil, directory: directory)])
        preset.windows.append(window)
        selection = window.id
    }

    private func duplicate(_ i: Int) {
        let copy = preset.windows[i].duplicated()
        preset.windows.insert(copy, at: i + 1)
        selection = copy.id
    }

    private func delete(_ i: Int) {
        let removed = preset.windows.remove(at: i)
        if selection == removed.id { selection = preset.windows[min(i, preset.windows.count - 1)].id }
    }
}
