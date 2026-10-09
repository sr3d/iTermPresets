import CoreGraphics
import Foundation

/// A named set of windows (each a set of tabs) that can be opened in iTerm in one go.
struct Preset: Codable, Identifiable, Hashable {
    enum Target: String, Codable, CaseIterable {
        case newWindow, currentWindow
        var label: String { self == .newWindow ? "New window" : "Current window" }
    }

    var id = UUID()
    var name: String
    /// Where the *first* window's tabs go. Later windows are always new.
    var target: Target = .newWindow
    var runAtLaunch = false
    var windows: [WindowSpec]

    init(name: String, target: Target = .newWindow, runAtLaunch: Bool = false, windows: [WindowSpec]) {
        self.name = name
        self.target = target
        self.runAtLaunch = runAtLaunch
        self.windows = windows
    }

    static func sample() -> Preset {
        Preset(name: "New Preset",
               windows: [WindowSpec(tabs: [TabSpec(title: "Project", colorHex: "#3B82F6", directory: "~")])])
    }

    /// Whether window `index` is the user's existing window, which is never moved or resized.
    func reusesCurrentWindow(_ index: Int) -> Bool { index == 0 && target == .currentWindow }
}

struct WindowSpec: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    /// Saved placement; `nil` lets iTerm choose.
    var frame: WindowFrame?
    var tabs: [TabSpec]

    func duplicated() -> WindowSpec {
        var copy = self
        copy.id = UUID()
        copy.tabs = tabs.map { $0.duplicated() }
        return copy
    }
}

/// A window frame in global screen coordinates, origin at the bottom-left of the main
/// screen, title bar included — the same convention as `NSWindow.frame` and iTerm's API.
struct WindowFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x.rounded()
        y = rect.origin.y.rounded()
        width = rect.width.rounded()
        height = rect.height.rounded()
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct TabSpec: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    /// `nil` means "use the profile's default tab color".
    var colorHex: String?
    var directory: String
    var layout: PaneNode = .pane(PaneSpec())

    init(title: String, colorHex: String?, directory: String, layout: PaneNode = .pane(PaneSpec())) {
        self.title = title
        self.colorHex = colorHex
        self.directory = directory
        self.layout = layout
    }

    /// A copy with fresh ids for the tab and every pane.
    func duplicated() -> TabSpec {
        var copy = self
        copy.id = UUID()
        copy.layout = layout.withNewIDs()
        return copy
    }
}

struct PaneSpec: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    /// Empty means "same as the tab".
    var directory = ""
    var command = ""
}

enum SplitDirection: String, Codable, CaseIterable {
    /// Vertical divider; the new pane goes to the right (iTerm's ⌘D).
    case right
    /// Horizontal divider; the new pane goes below (iTerm's ⇧⌘D).
    case below
}

/// A tab's layout as a binary split tree. Each split halves its region, like iTerm does.
indirect enum PaneNode: Codable, Hashable {
    case pane(PaneSpec)
    case split(direction: SplitDirection, first: PaneNode, second: PaneNode)

    var panes: [PaneSpec] {
        switch self {
        case .pane(let pane): return [pane]
        case .split(_, let first, let second): return first.panes + second.panes
        }
    }

    func pane(_ id: UUID) -> PaneSpec? { panes.first { $0.id == id } }

    /// Replaces the pane with `id` by whatever `transform` returns.
    @discardableResult
    mutating func replacePane(_ id: UUID, with transform: (PaneSpec) -> PaneNode) -> Bool {
        switch self {
        case .pane(let pane):
            guard pane.id == id else { return false }
            self = transform(pane)
            return true
        case .split(let direction, var first, var second):
            if first.replacePane(id, with: transform) || second.replacePane(id, with: transform) {
                self = .split(direction: direction, first: first, second: second)
                return true
            }
            return false
        }
    }

    mutating func update(_ id: UUID, _ change: (inout PaneSpec) -> Void) {
        replacePane(id) { pane in
            var pane = pane
            change(&pane)
            return .pane(pane)
        }
    }

    /// Splits pane `id`, putting `newPane` to its right or below it.
    mutating func split(_ id: UUID, _ direction: SplitDirection, adding newPane: PaneSpec) {
        replacePane(id) { .split(direction: direction, first: .pane($0), second: .pane(newPane)) }
    }

    /// Removes a pane; its sibling takes over the space. The last pane can't be removed.
    @discardableResult
    mutating func remove(_ id: UUID) -> Bool {
        guard case .split(let direction, var first, var second) = self else { return false }
        if case .pane(let pane) = first, pane.id == id { self = second; return true }
        if case .pane(let pane) = second, pane.id == id { self = first; return true }
        if first.remove(id) || second.remove(id) {
            self = .split(direction: direction, first: first, second: second)
            return true
        }
        return false
    }

    func withNewIDs() -> PaneNode {
        switch self {
        case .pane(var pane):
            pane.id = UUID()
            return .pane(pane)
        case .split(let direction, let first, let second):
            return .split(direction: direction, first: first.withNewIDs(), second: second.withNewIDs())
        }
    }

    /// Each pane's rectangle when the tab fills `bounds`.
    func rects(in bounds: CGRect) -> [(pane: PaneSpec, rect: CGRect)] {
        switch self {
        case .pane(let pane):
            return [(pane, bounds)]
        case .split(let direction, let first, let second):
            let (a, b) = direction == .right
                ? bounds.divided(atDistance: bounds.width / 2, from: .minXEdge)
                : bounds.divided(atDistance: bounds.height / 2, from: .minYEdge)
            return first.rects(in: a) + second.rects(in: b)
        }
    }
}

// MARK: - Decoding presets saved by earlier versions

extension Preset {
    private enum CodingKeys: String, CodingKey { case id, name, target, runAtLaunch, windows }
    private enum LegacyKeys: String, CodingKey { case tabs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        target = try c.decodeIfPresent(Target.self, forKey: .target) ?? .newWindow
        runAtLaunch = try c.decodeIfPresent(Bool.self, forKey: .runAtLaunch) ?? false
        if let windows = try c.decodeIfPresent([WindowSpec].self, forKey: .windows) {
            self.windows = windows
        } else {
            // Before multi-window support a preset was a single window's tabs.
            let tabs = try decoder.container(keyedBy: LegacyKeys.self).decode([TabSpec].self, forKey: .tabs)
            windows = [WindowSpec(tabs: tabs)]
        }
    }
}

// Before split trees, a tab was a flat pane list.

extension TabSpec {
    private enum CodingKeys: String, CodingKey { case id, title, colorHex, directory, layout }
    private enum LegacyKeys: String, CodingKey { case panes }

    private struct LegacyPane: Decodable {
        var id: UUID
        var name: String
        var directory: String
        var command: String
        var splitFrom: UUID?
        var direction: SplitDirection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        directory = try c.decode(String.self, forKey: .directory)
        if let layout = try c.decodeIfPresent(PaneNode.self, forKey: .layout) {
            self.layout = layout
            return
        }
        // Old format: every pane after the first split an earlier one in half — the same tree.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            .decode([LegacyPane].self, forKey: .panes)
        func spec(_ p: LegacyPane) -> PaneSpec {
            PaneSpec(id: p.id, name: p.name, directory: p.directory, command: p.command)
        }
        guard let first = legacy.first else { return }
        var tree = PaneNode.pane(spec(first))
        for (i, pane) in legacy.enumerated().dropFirst() {
            let parent = legacy[..<i].first { $0.id == pane.splitFrom }?.id ?? legacy[i - 1].id
            tree.split(parent, pane.direction, adding: spec(pane))
        }
        layout = tree
    }
}
