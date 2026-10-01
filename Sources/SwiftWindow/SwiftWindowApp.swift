import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
            }
        }
    }
}
