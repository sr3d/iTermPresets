import AppKit
import SwiftUI

/// Shows translucent "ghost" windows standing in for a preset's iTerm windows. The user drags
/// and resizes them where the real windows should go; Done saves every ghost's frame.
@MainActor
final class GhostArranger: NSObject, NSWindowDelegate {
    static let shared = GhostArranger()

    struct Item {
        let id: UUID
        let title: String
        let tabs: [TabSpec]
        let frame: WindowFrame?
    }

    private var ghosts: [(id: UUID, window: NSWindow, model: GhostModel)] = []
    private var onDone: (([UUID: WindowFrame]) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func begin(_ items: [Item], focus: UUID?, onDone: @escaping ([UUID: WindowFrame]) -> Void) {
        finish(commit: false)
        self.onDone = onDone
        for (i, item) in items.enumerated() {
            let frame = item.frame?.rect ?? Self.defaultFrame(index: i)
            let window = GhostWindow(contentRect: frame,
                                     styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                     backing: .buffered, defer: false)
            window.setFrame(frame, display: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = item.title
            window.isOpaque = false
            let tint = item.tabs.first?.colorHex.map { NSColor(Color(hex: $0)) } ?? .systemBlue
            window.backgroundColor = tint.withAlphaComponent(0.28)
            window.level = .floating
            window.minSize = NSSize(width: 320, height: 220)
            window.delegate = self

            let model = GhostModel(title: item.title, tabs: item.tabs, frame: frame)
            let id = item.id
            window.contentView = NSHostingView(rootView: GhostView(
                model: model,
                snap: { [weak self] in self?.snap(id, $0) },
                done: { [weak self] in self?.finish(commit: true) },
                cancel: { [weak self] in self?.finish(commit: false) }))
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main) { [weak window, weak model] _ in
                        MainActor.assumeIsolated {
                            if let window, let model { model.frame = window.frame }
                        }
                    })
            }
            ghosts.append((id, window, model))
            window.orderFrontRegardless()
        }
        let key = ghosts.first { $0.id == focus } ?? ghosts.first
        NSApp.activate(ignoringOtherApps: true)
        key?.window.makeKeyAndOrderFront(nil)
    }

    func finish(commit: Bool) {
        if commit {
            onDone?(Dictionary(uniqueKeysWithValues: ghosts.map { ($0.id, WindowFrame($0.window.frame)) }))
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let closing = ghosts
        ghosts = []
        onDone = nil
        for ghost in closing {
            ghost.window.delegate = nil
            ghost.window.close()
        }
    }

    /// The red close button cancels the whole arrangement.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(commit: false)
        return false
    }

    enum Snap: CaseIterable {
        case leftHalf, rightHalf, topHalf, bottomHalf, fill, center
        var label: String {
            switch self {
            case .leftHalf: return "Left"
            case .rightHalf: return "Right"
            case .topHalf: return "Top"
            case .bottomHalf: return "Bottom"
            case .fill: return "Fill"
            case .center: return "Center"
            }
        }
        var icon: String {
            switch self {
            case .leftHalf: return "rectangle.lefthalf.filled"
            case .rightHalf: return "rectangle.righthalf.filled"
            case .topHalf: return "rectangle.tophalf.filled"
            case .bottomHalf: return "rectangle.bottomhalf.filled"
            case .fill: return "rectangle.fill"
            case .center: return "rectangle.center.inset.filled"
            }
        }
    }

    private func snap(_ id: UUID, _ snap: Snap) {
        guard let window = ghosts.first(where: { $0.id == id })?.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let frame: CGRect
        switch snap {
        case .leftHalf: frame = CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        case .rightHalf: frame = CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        case .topHalf: frame = CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        case .bottomHalf: frame = CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        case .fill: frame = v
        case .center:
            let size = CGSize(width: v.width * 0.6, height: v.height * 0.7)
            frame = CGRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height)
        }
        window.setFrame(frame.integral, display: true, animate: true)
    }

    nonisolated static func defaultFrame(index: Int) -> CGRect {
        let v = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: v.width * 0.55, height: v.height * 0.65)
        let offset = CGFloat(index) * 40
        return CGRect(x: v.midX - size.width / 2 + offset, y: v.midY - size.height / 2 - offset,
                      width: size.width, height: size.height).integral
    }

    /// e.g. "1440 × 900 on Built-in Retina Display".
    nonisolated static func describe(_ frame: WindowFrame) -> String {
        let rect = frame.rect
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
        let size = "\(Int(rect.width)) × \(Int(rect.height))"
        return screen.map { "\(size) on \($0.localizedName)" } ?? "\(size), currently off-screen"
    }
}

private final class GhostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class GhostModel: ObservableObject {
    let title: String
    let tabs: [TabSpec]
    @Published var frame: CGRect

    init(title: String, tabs: [TabSpec], frame: CGRect) {
        self.title = title
        self.tabs = tabs
        self.frame = frame
    }
}

struct GhostView: View {
    @ObservedObject var model: GhostModel
    let snap: (GhostArranger.Snap) -> Void
    let done: () -> Void
    let cancel: () -> Void
    @AppStorage(Zoom.storageKey) private var zoom = 1.0

    var body: some View {
        ZStack {
            WindowDragArea()
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .padding(3)
                .allowsHitTesting(false)
            ZoomedContainer(scale: zoom) {
                content.padding(.top, 22)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            Text(model.title).font(.title2.weight(.bold))
            Text(GhostArranger.describe(WindowFrame(model.frame)))
                .font(.system(.callout, design: .monospaced))
            tabChips
            if let first = model.tabs.first {
                MiniLayout(tab: first)
                    .frame(maxWidth: 360, maxHeight: 160)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 4) {
                ForEach(GhostArranger.Snap.allCases, id: \.self) { s in
                    Button { snap(s) } label: { Image(systemName: s.icon).frame(width: 22) }
                        .help("Snap: \(s.label)")
                }
            }
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            Text("Drag to move · drag the edges to resize · Done saves every window")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(20)
        // A dark card keeps the text readable over any wallpaper behind the translucent ghost.
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.6)))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabChips: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.tabs.prefix(6).enumerated()), id: \.element.id) { i, tab in
                Text(tab.title.isEmpty ? "Tab \(i + 1)" : tab.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((tab.colorHex.map(Color.init(hex:)) ?? .gray).opacity(0.85)))
            }
            if model.tabs.count > 6 { Text("+\(model.tabs.count - 6)").font(.caption) }
        }
    }
}

/// The first tab's split layout, drawn small.
struct MiniLayout: View {
    let tab: TabSpec

    var body: some View {
        GeometryReader { geo in
            let rects = tab.layout.rects(in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(rects, id: \.pane.id) { item in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.45))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.5)))
                        .frame(width: max(item.rect.width - 3, 1), height: max(item.rect.height - 3, 1))
                        .offset(x: item.rect.minX + 1.5, y: item.rect.minY + 1.5)
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
    }
}

/// Dragging anywhere on this background moves the window (SwiftUI content otherwise eats the drag).
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
