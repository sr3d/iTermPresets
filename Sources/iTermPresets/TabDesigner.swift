import SwiftUI

// MARK: - Tab strip

/// An iTerm-style tab bar. The selected tab joins the content below it; each tab's color
/// shows as a strip along its top edge and a light tint. Right-click for more actions.
struct TabStrip: View {
    @Binding var tabs: [TabSpec]
    @Binding var selection: UUID?
    @State private var hovered: UUID?

    static let height: CGFloat = 34

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { i, tab in
                let selected = tab.id == selection
                let nextSelected = i + 1 < tabs.count && tabs[i + 1].id == selection
                tabView(tab, number: i + 1, selected: selected)
                    .overlay(alignment: .trailing) {
                        // Dividers only between two unselected tabs, like macOS tab bars.
                        if !selected && !nextSelected && i < tabs.count - 1 {
                            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 16)
                        }
                    }
                    .zIndex(selected ? 1 : 0)
                    .contextMenu {
                        Button("Duplicate Tab") { duplicate(i) }
                        Button("Move Left") { tabs.swapAt(i, i - 1) }.disabled(i == 0)
                        Button("Move Right") { tabs.swapAt(i, i + 1) }.disabled(i == tabs.count - 1)
                        Divider()
                        Button("Close Tab", role: .destructive) { delete(i) }.disabled(tabs.count == 1)
                    }
            }
            Button { add() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: Self.height - 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New tab")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .frame(height: Self.height + 6, alignment: .bottom)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Color.primary.opacity(0.07)
                Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1)
            }
        }
    }

    private func tabView(_ tab: TabSpec, number: Int, selected: Bool) -> some View {
        let tint = tab.colorHex.map(Color.init(hex:))
        let shape = TabShape(radius: 7)
        let isHovered = hovered == tab.id
        return ZStack {
            // Selected tab uses the content background so it merges with the area below.
            shape.fill(selected ? Color(nsColor: .windowBackgroundColor)
                                : (isHovered ? Color.primary.opacity(0.06) : .clear))
            if let tint {
                if !selected { shape.fill(tint.opacity(0.12)) }
                VStack(spacing: 0) {
                    tint.opacity(selected ? 1 : 0.6).frame(height: 3)
                    Spacer(minLength: 0)
                }
                .clipShape(shape)
            }
            if selected {
                // The path is open at the bottom, so only the sides and top are stroked and
                // the fill covers the bar's bottom line — the tab flows into the content.
                shape.stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }

            HStack(spacing: 6) {
                Button { if let i = tabs.firstIndex(where: { $0.id == tab.id }) { delete(i) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .opacity(isHovered && tabs.count > 1 ? 1 : 0)
                .help("Close tab")

                Spacer(minLength: 0)
                Text(tab.title.isEmpty ? "Tab \(number)" : tab.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)

                Text(tab.layout.panes.count > 1 ? "\(tab.layout.panes.count)" : "")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .help("\(tab.layout.panes.count) panes")
            }
            .padding(.horizontal, 8)
        }
        .frame(minWidth: 110, idealWidth: 180, maxWidth: 200)
        .frame(height: Self.height - (selected ? 0 : 3))
        .contentShape(shape)
        .onTapGesture { selection = tab.id }
        .onHover { hovered = $0 ? tab.id : (hovered == tab.id ? nil : hovered) }
    }

    private func add() {
        let tab = TabSpec(title: "", colorHex: nil, directory: tabs.first { $0.id == selection }?.directory ?? "~")
        tabs.append(tab)
        selection = tab.id
    }

    private func duplicate(_ i: Int) {
        let copy = tabs[i].duplicated()
        tabs.insert(copy, at: i + 1)
        selection = copy.id
    }

    private func delete(_ i: Int) {
        guard tabs.count > 1 else { return }
        let removed = tabs.remove(at: i)
        if selection == removed.id { selection = tabs[min(i, tabs.count - 1)].id }
    }
}

/// A rectangle with rounded top corners and a square bottom, for tabs.
struct TabShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

// MARK: - Tab designer

struct TabDesigner: View {
    @Binding var tab: TabSpec
    @State private var selectedPane: UUID?

    static let palette = ["#EF4444", "#F97316", "#EAB308", "#22C55E", "#14B8A6",
                          "#3B82F6", "#8B5CF6", "#EC4899", "#64748B"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Tab title", text: $tab.title)
                    .frame(width: 180)
                Image(systemName: "folder").foregroundStyle(.secondary)
                PathField(placeholder: "Tab folder, e.g. ~/projects/app", text: $tab.directory)
            }
            .zIndex(2)
            colorRow
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    SplitCanvas(layout: $tab.layout, selection: $selectedPane,
                                tint: tab.colorHex.map(Color.init(hex:)) ?? .secondary,
                                tabDirectory: tab.directory, split: split)
                        .frame(minHeight: 260)
                    Text("Drag a line across a pane to split it · click a pane to edit it · ⌘D split right · ⇧⌘D split below")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                PaneInspector(layout: $tab.layout, selection: $selectedPane,
                              tabDirectory: tab.directory, split: split)
                    .frame(width: 290)
            }
        }
        .padding(16)
        .onAppear { if selectedPane == nil { selectedPane = tab.layout.panes.first?.id } }
    }

    private var colorRow: some View {
        HStack(spacing: 6) {
            Text("Color").foregroundStyle(.secondary)
            swatch(nil)
            ForEach(Self.palette, id: \.self) { swatch($0) }
            ColorPicker("", selection: Binding(get: { Color(hex: tab.colorHex ?? "#3B82F6") },
                                               set: { tab.colorHex = $0.hexString }),
                        supportsOpacity: false)
                .labelsHidden()
                .help("Custom color")
        }
    }

    private func swatch(_ hex: String?) -> some View {
        let selected = tab.colorHex?.uppercased() == hex?.uppercased()
        return Button { tab.colorHex = hex } label: {
            ZStack {
                Circle().fill(hex.map(Color.init(hex:)) ?? Color.clear)
                Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                if hex == nil { Image(systemName: "slash.circle").foregroundStyle(.secondary) }
            }
            .frame(width: 20, height: 20)
            .padding(2)
            .overlay(Circle().stroke(selected ? Color.primary : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(hex == nil ? "No tab color" : hex!)
    }

    /// Splits pane `id`; `copying` duplicates the pane's folder, command and name into the new one.
    private func split(_ id: UUID, _ direction: SplitDirection, copying: Bool) {
        var pane = PaneSpec()
        if copying, let source = tab.layout.pane(id) {
            pane.name = source.name
            pane.directory = source.directory
            pane.command = source.command
        }
        tab.layout.split(id, direction, adding: pane)
        selectedPane = pane.id
    }
}

// MARK: - Canvas

/// The tab drawn at full size. Dragging across a pane splits it; clicking selects it.
struct SplitCanvas: View {
    @Binding var layout: PaneNode
    @Binding var selection: UUID?
    let tint: Color
    let tabDirectory: String
    let split: (UUID, SplitDirection, Bool) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragNow: CGPoint?
    @State private var hovered: UUID?

    var body: some View {
        GeometryReader { geo in
            let rects = layout.rects(in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(rects, id: \.pane.id) { item in
                    tile(item.pane, canClose: rects.count > 1)
                        .frame(width: item.rect.width - 4, height: item.rect.height - 4)
                        .offset(x: item.rect.minX + 2, y: item.rect.minY + 2)
                }
                if let preview = splitPreview(rects) {
                    Path { p in p.move(to: preview.from); p.addLine(to: preview.to) }
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [7, 4]))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragStart = value.startLocation
                        dragNow = value.location
                    }
                    .onEnded { value in
                        defer { dragStart = nil; dragNow = nil }
                        guard let target = rects.first(where: { $0.rect.contains(value.startLocation) }) else { return }
                        if let direction = Self.direction(from: value.startLocation, to: value.location) {
                            split(target.pane.id, direction, false)
                        } else {
                            selection = target.pane.id
                        }
                    }
            )
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// A mostly-vertical stroke draws a vertical divider (new pane to the right), and vice versa.
    static func direction(from start: CGPoint, to end: CGPoint) -> SplitDirection? {
        let dx = abs(end.x - start.x), dy = abs(end.y - start.y)
        guard max(dx, dy) > 24 else { return nil }
        return dy > dx ? .right : .below
    }

    private func splitPreview(_ rects: [(pane: PaneSpec, rect: CGRect)]) -> (from: CGPoint, to: CGPoint)? {
        guard let start = dragStart, let now = dragNow,
              let direction = Self.direction(from: start, to: now),
              let r = rects.first(where: { $0.rect.contains(start) })?.rect else { return nil }
        return direction == .right
            ? (CGPoint(x: r.midX, y: r.minY + 6), CGPoint(x: r.midX, y: r.maxY - 6))
            : (CGPoint(x: r.minX + 6, y: r.midY), CGPoint(x: r.maxX - 6, y: r.midY))
    }

    private func tile(_ pane: PaneSpec, canClose: Bool) -> some View {
        let selected = pane.id == selection
        let folder = pane.directory.isEmpty ? tabDirectory : pane.directory
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 5)
                .fill(tint.opacity(selected ? 0.35 : 0.16))
            RoundedRectangle(cornerRadius: 5)
                .stroke(selected ? Color.accentColor : tint.opacity(0.6), lineWidth: selected ? 2.5 : 1)
            VStack(alignment: .leading, spacing: 3) {
                if !pane.name.isEmpty {
                    Text(pane.name).font(.callout.weight(.semibold))
                }
                Text(folder.isEmpty ? "~" : folder)
                    .font(.system(.caption, design: .monospaced))
                    .opacity(pane.directory.isEmpty ? 0.6 : 1)
                if !pane.command.isEmpty {
                    Text("$ " + pane.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if hovered == pane.id {
                HStack(spacing: 2) {
                    tileButton("rectangle.split.2x1", "Split right") { split(pane.id, .right, false) }
                    tileButton("rectangle.split.1x2", "Split below") { split(pane.id, .below, false) }
                    tileButton("plus.square.on.square", "Duplicate pane") { split(pane.id, .right, true) }
                    if canClose {
                        tileButton("xmark", "Close pane") {
                            layout.remove(pane.id)
                            if selection == pane.id { selection = layout.panes.first?.id }
                        }
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.55)))
                .padding(4)
            }
        }
        .onHover { hovered = $0 ? pane.id : (hovered == pane.id ? nil : hovered) }
    }

    private func tileButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).foregroundStyle(.white).frame(width: 20, height: 18)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Inspector

struct PaneInspector: View {
    @Binding var layout: PaneNode
    @Binding var selection: UUID?
    let tabDirectory: String
    let split: (UUID, SplitDirection, Bool) -> Void

    var body: some View {
        GroupBox {
            if let id = selection, layout.pane(id) != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pane \((layout.panes.firstIndex { $0.id == id } ?? 0) + 1) of \(layout.panes.count)")
                        .font(.headline)
                    field("Folder") {
                        PathField(placeholder: "Same as tab",
                                  text: binding(id, \.directory))
                    }
                    .zIndex(2)
                    field("Command") {
                        TextField("e.g. npm run dev", text: binding(id, \.command))
                            .font(.system(.body, design: .monospaced))
                    }
                    field("Name") {
                        TextField("Optional session name", text: binding(id, \.name))
                    }
                    Divider()
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        GridRow {
                            Button { split(id, .right, false) } label: { Label("Split Right", systemImage: "rectangle.split.2x1") }
                                .keyboardShortcut("d", modifiers: .command)
                            Button { split(id, .below, false) } label: { Label("Split Below", systemImage: "rectangle.split.1x2") }
                                .keyboardShortcut("d", modifiers: [.command, .shift])
                        }
                        GridRow {
                            Button { split(id, .right, true) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                .keyboardShortcut("d", modifiers: [.command, .option])
                                .help("Split right with the same folder and command (⌥⌘D)")
                            Button(role: .destructive) {
                                layout.remove(id)
                                selection = layout.panes.first?.id
                            } label: { Label("Close Pane", systemImage: "xmark") }
                                .keyboardShortcut(.delete, modifiers: .command)
                                .disabled(layout.panes.count == 1)
                        }
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
                .padding(4)
            } else {
                Text("Click a pane to edit it")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func binding(_ id: UUID, _ key: WritableKeyPath<PaneSpec, String>) -> Binding<String> {
        Binding(get: { layout.pane(id)?[keyPath: key] ?? "" },
                set: { value in layout.update(id) { $0[keyPath: key] = value } })
    }
}
