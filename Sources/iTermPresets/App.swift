import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run as a bare SwiftPM binary; harmless inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ITermPresetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()
    @AppStorage(Zoom.storageKey) private var zoom = 1.0

    var body: some Scene {
        WindowGroup("iTerm Presets") {
            ZoomedContainer(scale: zoom) {
                ContentView().environmentObject(store)
            }
            .frame(minWidth: 760, minHeight: 480)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                store.saveNow()
            }
        }
        .commands {
            CommandGroup(before: .toolbar) {
                Button("Zoom In") { zoom = Zoom.step(zoom, by: 1) }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { zoom = Zoom.step(zoom, by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { zoom = 1 }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }
    }
}
