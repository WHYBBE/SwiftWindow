import Foundation

enum StageManagerService {
    /// Reads Stage Manager state from `com.apple.WindowManager` and the window
    /// set inventory stored in `com.apple.spaces`. Stage Manager keeps a
    /// "window set" per stage and asks WindowServer to back each one with a
    /// full-screen surface, which is a common source of WindowServer growth.
    static func state() -> StageManagerState {
        var state = StageManagerState()

        let enabledResult = Shell.run("/usr/bin/defaults", ["read", "com.apple.WindowManager", "GloballyEnabled"])
        state.enabled = enabledResult.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"

        guard let data = try? Data(contentsOf: spacesPlistURL()),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let config = plist["SpacesDisplayConfiguration"] as? [String: Any],
              let management = config["Management Data"] as? [String: Any] else {
            return state
        }

        if let mode = management["Management Mode"] as? Int { state.managementMode = mode }
        if let age = management["Age"] as? Double { state.ageSeconds = age }

        var setCount = 0
        var appEntries = 0
        var appCounts: [String: Int] = [:]

        if let monitors = management["Monitors"] as? [[String: Any]] {
            for monitor in monitors {
                guard let current = monitor["Current Space"] as? [String: Any],
                      let info = current["WindowManagerInfo"] as? [String: Any],
                      let sets = info["windowSets"] as? [String: [String]] else { continue }
                setCount += sets.count
                for apps in sets.values {
                    appEntries += apps.count
                    for entry in apps {
                        let bundle = entry.replacingOccurrences(
                            of: #"-[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"#,
                            with: "",
                            options: .regularExpression
                        )
                        appCounts[bundle, default: 0] += 1
                    }
                }
            }
        }

        state.windowSetCount = setCount
        state.appEntryCount = appEntries
        state.distinctApps = appCounts.count
        state.topApps = appCounts
            .sorted { $0.value > $1.value }
            .prefix(20)
            .map { (app: $0.key, sets: $0.value) }
        return state
    }

    private static func spacesPlistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")
    }
}
