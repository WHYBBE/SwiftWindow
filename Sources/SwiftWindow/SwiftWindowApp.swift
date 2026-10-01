import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce a single instance. Two copies of the app each run their own
        // privileged engine, which doubles the chance of duplicate password
        // sheets, so quit if another copy is already running.
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.tom.swiftwindow"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct SwiftWindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = MonitorEngine()

    var body: some Scene {
        WindowGroup("WindowServer 内存分析") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear { engine.start() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新实时数据") { engine.refreshBasic() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("加载详细分析") { engine.loadDetails() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(engine.isPrivilegedBusy)
            }
        }
    }
}
