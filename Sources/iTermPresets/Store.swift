import AppKit
import Combine
import Foundation

/// Holds the presets, persists them, and keeps iTerm's Scripts folder in sync.
@MainActor
final class Store: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var lastError: String?

    private var saveTask: Task<Void, Never>?

    static let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/iTermPresets", isDirectory: true)
    static let presetsFile = supportDir.appendingPathComponent("presets.json")

    init() {
        if let data = try? Data(contentsOf: Self.presetsFile),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = decoded
        }
        if presets.isEmpty { presets = [.sample()] }
    }

    /// Debounced: writes presets.json and regenerates every script in iTerm's Scripts folder.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            try FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(presets).write(to: Self.presetsFile, options: .atomic)
            try ITermBridge.sync(presets)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func add() -> Preset {
        var preset = Preset.sample()
        preset.name = uniqueName("New Preset")
        presets.append(preset)
        return preset
    }

    func duplicate(_ id: UUID) -> Preset? {
        guard let original = presets.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name = uniqueName(original.name + " copy")
        copy.runAtLaunch = false
        presets.append(copy)
        return copy
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
    }

    private func uniqueName(_ base: String) -> String {
        var name = base, n = 2
        while presets.contains(where: { $0.name == name }) { name = "\(base) \(n)"; n += 1 }
        return name
    }
}
