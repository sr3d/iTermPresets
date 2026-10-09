import AppKit
import Foundation

/// Everything that touches iTerm: its Scripts folder and the AppleScript "launch API script" hook.
/// Nothing here quits iTerm or closes its windows.
enum ITermBridge {
    static let scriptsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/iTerm2/Scripts", isDirectory: true)
    /// Shows up as a "iTermPresets" submenu of iTerm's Scripts menu.
    static let presetsDir = scriptsDir.appendingPathComponent("iTermPresets", isDirectory: true)
    /// iTerm runs everything in here each time it starts.
    static let autoLaunchDir = scriptsDir.appendingPathComponent("AutoLaunch", isDirectory: true)
    static let autoLaunchPrefix = "iTermPresets - "

    /// Script file name for each preset, unique even when two presets sanitize to the same name.
    static func fileNames(for presets: [Preset]) -> [UUID: String] {
        var used = Set<String>(), result: [UUID: String] = [:]
        for preset in presets {
            var name = ScriptGenerator.fileName(for: preset)
            if used.contains(name.lowercased()) {
                name = name.replacingOccurrences(of: ".py", with: "-\(preset.id.uuidString.prefix(4)).py")
            }
            used.insert(name.lowercased())
            result[preset.id] = name
        }
        return result
    }

    static func scriptURL(for preset: Preset, in presets: [Preset]) -> URL {
        presetsDir.appendingPathComponent(fileNames(for: presets)[preset.id] ?? ScriptGenerator.fileName(for: preset))
    }

    /// Writes one script per preset (plus AutoLaunch copies) and removes stale ones we generated.
    static func sync(_ presets: [Preset]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        let names = fileNames(for: presets)

        var wantedMenu = Set<String>(), wantedAuto = Set<String>()
        for preset in presets {
            let name = names[preset.id]!
            let source = ScriptGenerator.python(for: preset)
            try writeIfChanged(source, to: presetsDir.appendingPathComponent(name))
            wantedMenu.insert(name)
            if preset.runAtLaunch {
                try fm.createDirectory(at: autoLaunchDir, withIntermediateDirectories: true)
                let autoName = autoLaunchPrefix + name
                try writeIfChanged(source, to: autoLaunchDir.appendingPathComponent(autoName))
                wantedAuto.insert(autoName)
            }
        }
        removeGeneratedScripts(in: presetsDir, keeping: wantedMenu)
        removeGeneratedScripts(in: autoLaunchDir, keeping: wantedAuto)
    }

    /// Asks iTerm to run the preset's script. iTerm is launched if needed; existing windows are untouched.
    static func launch(_ preset: Preset, in presets: [Preset]) throws {
        try sync(presets)
        let relative = "iTermPresets/" + scriptURL(for: preset, in: presets).lastPathComponent
        let escaped = relative.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"iTerm2\" to launch API script named \"\(escaped)\""
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "\(errorInfo)"
            throw NSError(domain: "iTermPresets", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private static func writeIfChanged(_ text: String, to url: URL) throws {
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == text { return }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Only deletes files carrying our generated-by marker, so hand-written scripts are never touched.
    private static func removeGeneratedScripts(in dir: URL, keeping wanted: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "py" && !wanted.contains(file.lastPathComponent) {
            if let text = try? String(contentsOf: file, encoding: .utf8),
               text.contains(ScriptGenerator.presetIDMarker) {
                try? fm.removeItem(at: file)
            }
        }
    }
}
