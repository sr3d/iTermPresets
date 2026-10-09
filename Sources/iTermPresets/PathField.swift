import AppKit
import SwiftUI

/// A directory field that suggests matching folders below it as you type.
/// ↑/↓ move through the list, Return or click sets the folder and closes the list, Esc closes it,
/// and Tab completes like a shell — continuing into the folder's subfolders.
/// A Browse… button opens a folder picker. Callers should give the row containing this field a raised `zIndex` so the list
/// draws over the views below it.
struct PathField: View {
    var placeholder: String
    @Binding var text: String
    @StateObject private var completer = PathCompleter()
    @State private var fieldHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: 6) {
            field
            Button("Browse…") { browse() }
                .help("Choose a folder")
        }
        .zIndex(1)
    }

    private var field: some View {
        PathTextField(placeholder: placeholder, text: $text, completer: completer)
            .background(GeometryReader { geo in
                Color.clear.preference(key: FieldHeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(FieldHeightKey.self) { fieldHeight = $0 }
            .overlay(alignment: .topLeading) {
                if completer.isVisible {
                    suggestionList
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(y: fieldHeight + 3)
                }
            }
    }

    private func browse() {
        completer.hide()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        let current = (text as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if !text.isEmpty, FileManager.default.fileExists(atPath: current, isDirectory: &isDir), isDir.boolValue {
            panel.directoryURL = URL(fileURLWithPath: current)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        text = (url.path as NSString).abbreviatingWithTildeInPath
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(completer.visibleSuggestions.enumerated()), id: \.element) { i, name in
                let highlighted = i == completer.highlighted
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(highlighted ? Color.white : Color.accentColor)
                    Text(name + "/")
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(highlighted ? Color.white : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(highlighted ? Color.accentColor : .clear))
                .contentShape(Rectangle())
                .onHover { if $0 { completer.highlighted = i } }
                .onTapGesture { completer.accept(name, drill: false) }
            }
            if completer.hiddenCount > 0 {
                Text("\(completer.hiddenCount) more — keep typing to narrow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.3)))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

private struct FieldHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 22
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Folder matching and the dropdown's state for one field.
@MainActor
final class PathCompleter: ObservableObject {
    static let maxVisible = 8

    @Published private(set) var suggestions: [String] = []
    @Published var highlighted = 0
    @Published private(set) var isVisible = false

    /// Typed text up to and including the last "/" — what a picked folder name is appended to.
    private var base = ""
    private var prefix = ""
    /// Writes a new value into the field editor and the binding.
    var apply: ((String) -> Void)?

    var visibleSuggestions: [String] { Array(suggestions.prefix(Self.maxVisible)) }
    var hiddenCount: Int { max(suggestions.count - Self.maxVisible, 0) }

    func update(for typed: String) {
        guard !typed.isEmpty else { return hide() }
        if typed == "~" {
            base = "~/"; prefix = ""
        } else if typed.hasSuffix("/") {
            base = typed; prefix = ""
        } else {
            let parent = (typed as NSString).deletingLastPathComponent
            base = parent.isEmpty ? "" : (parent.hasSuffix("/") ? parent : parent + "/")
            prefix = String(typed.dropFirst(base.count))
        }
        let listDir = base.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : (base as NSString).expandingTildeInPath
        suggestions = Self.folders(in: listDir, matching: prefix)
        // Nothing to suggest once the only match is exactly what's typed.
        if suggestions.count == 1, suggestions[0] == prefix { suggestions = [] }
        highlighted = 0
        isVisible = !suggestions.isEmpty
    }

    func hide() {
        isVisible = false
        suggestions = []
    }

    func moveHighlight(_ delta: Int) {
        let count = visibleSuggestions.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    func acceptHighlighted(drill: Bool) {
        guard visibleSuggestions.indices.contains(highlighted) else { return }
        accept(visibleSuggestions[highlighted], drill: drill)
    }

    /// `drill: false` sets the folder and closes the list (Return, click).
    /// `drill: true` appends "/" and lists its subfolders (Tab).
    func accept(_ name: String, drill: Bool) {
        if drill {
            let value = base + name + "/"
            apply?(value)
            update(for: value)
        } else {
            apply?(base + name)
            hide()
        }
    }

    /// Shell-style Tab. Returns false when there was nothing to complete.
    func tabComplete(_ typed: String) -> Bool {
        // A complete folder path without the trailing "/": add it and list what's inside, like a shell.
        var isDir: ObjCBool = false
        if !typed.hasSuffix("/"),
           FileManager.default.fileExists(atPath: (typed as NSString).expandingTildeInPath, isDirectory: &isDir),
           isDir.boolValue, Self.commonPrefix(suggestions).count <= prefix.count || suggestions.isEmpty {
            apply?(typed + "/")
            update(for: typed + "/")
            return true
        }
        if suggestions.isEmpty { update(for: typed) }
        guard !suggestions.isEmpty else { return false }
        if suggestions.count == 1 { accept(suggestions[0], drill: true); return true }
        let common = Self.commonPrefix(suggestions)
        if common.count > prefix.count {
            let value = base + common
            apply?(value)
            update(for: value)
        } else {
            acceptHighlighted(drill: true)
        }
        return true
    }

    static func folders(in dir: String, matching prefix: String) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let showHidden = prefix.hasPrefix(".")
        let lowered = prefix.lowercased()
        return names.filter { name in
            guard showHidden || !name.hasPrefix("."), name.lowercased().hasPrefix(lowered) else { return false }
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: (dir as NSString).appendingPathComponent(name), isDirectory: &isDir)
                && isDir.boolValue
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Case-insensitive common prefix, keeping the casing of the first match.
    static func commonPrefix(_ names: [String]) -> String {
        guard var result = names.first else { return "" }
        for name in names.dropFirst() {
            let shared = zip(result.lowercased(), name.lowercased()).prefix { $0 == $1 }.count
            result = String(result.prefix(shared))
        }
        return result
    }
}

/// The AppKit text field underneath, which forwards typing and arrow/Return/Esc/Tab keys.
private struct PathTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    let completer: PathCompleter

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.bezelStyle = .roundedBezel
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.stringValue = text
        context.coordinator.field = field
        completer.apply = { [weak coordinator = context.coordinator] in coordinator?.set($0) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PathTextField
        weak var field: NSTextField?

        init(_ parent: PathTextField) { self.parent = parent }

        var completer: PathCompleter { parent.completer }

        func set(_ value: String) {
            guard let field else { return }
            field.stringValue = value
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (value as NSString).length, length: 0)
            }
            parent.text = value
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
            completer.update(for: field.stringValue)
        }

        func controlTextDidEndEditing(_ note: Notification) {
            // Delay so a click on a suggestion still lands before the list disappears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.field?.currentEditor() == nil else { return }
                self.completer.hide()
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                // Empty field: let Tab move focus as usual.
                return !textView.string.isEmpty && completer.tabComplete(textView.string)
            case #selector(NSResponder.moveDown(_:)) where completer.isVisible:
                completer.moveHighlight(1); return true
            case #selector(NSResponder.moveUp(_:)) where completer.isVisible:
                completer.moveHighlight(-1); return true
            case #selector(NSResponder.insertNewline(_:)) where completer.isVisible:
                completer.acceptHighlighted(drill: false); return true
            case #selector(NSResponder.cancelOperation(_:)) where completer.isVisible:
                completer.hide(); return true
            default:
                return false
            }
        }
    }
}
