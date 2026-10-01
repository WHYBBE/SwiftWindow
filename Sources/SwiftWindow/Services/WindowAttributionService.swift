import Foundation
import CoreGraphics
import AppKit

struct DisplayInfo: Sendable {
    var frame: CGRect
    var scale: Double
    var name: String
}

enum WindowAttributionService {
    static func displayScale() -> Double {
        Double(NSScreen.main?.backingScaleFactor ?? 2.0)
    }

    /// All displays in the CoreGraphics global coordinate space (origin at the
    /// primary display's top-left, y down) together with their backing scale.
    /// This lets each window be measured at the scale of the display it is on,
    /// instead of assuming the main display everywhere.
    static func displays() -> [DisplayInfo] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return screens.map { screen in
            let f = screen.frame
            let cgFrame = CGRect(
                x: f.origin.x,
                y: primaryHeight - f.origin.y - f.height,
                width: f.width,
                height: f.height
            )
            return DisplayInfo(frame: cgFrame, scale: Double(screen.backingScaleFactor), name: screen.localizedName)
        }
    }

    private static func display(at point: CGPoint, in displays: [DisplayInfo], fallback: DisplayInfo) -> DisplayInfo {
        displays.first { $0.frame.contains(point) } ?? fallback
    }

    // MARK: - Private surface API (best effort)

    struct SurfaceProbeEntry: Sendable {
        var surfaceCount: Int
        var ownerConnection: Int
    }

    private static let probeLock = NSLock()
    private static var probeAttempted = false
    private static var probeEntries: [Int: SurfaceProbeEntry]?

    /// Window → {surface count, owner connection} from the private SkyLight API,
    /// or nil when that API is unavailable. The probe runs in a child process
    /// (see `SurfaceProbe`); it deliberately avoids the surface
    /// Bounds/Resolution/FrontBuffer calls, which reject foreign surfaces and
    /// corrupt memory on macOS 27.
    static func privateSurfaceInfo() -> [Int: SurfaceProbeEntry]? {
        probeLock.lock()
        defer { probeLock.unlock() }
        if probeAttempted { return probeEntries }
        probeAttempted = true
        probeEntries = runPrivateSurfaceProbe()
        return probeEntries
    }

    private static let probeUnavailableKey = "SWIFTWINDOW.surfaceProbeUnavailableOSVersion"

    /// Lets the app try the private surface API again (e.g. after a system
    /// update made it available).
    static func retryPrivateProbe() {
        probeLock.lock()
        probeAttempted = false
        probeEntries = nil
        probeLock.unlock()
        UserDefaults.standard.removeObject(forKey: probeUnavailableKey)
    }

    private static func runPrivateSurfaceProbe() -> [Int: SurfaceProbeEntry]? {
        // Never recurse: the probe child gets this variable and will not itself
        // try to spawn another probe.
        guard ProcessInfo.processInfo.environment["SWIFTWINDOW_SURFACE_PROBE"] == nil else { return nil }

        // Calling the private API aborts the process on some macOS versions, so
        // remember "unavailable" for this OS version and stop retrying (this
        // also avoids generating a crash report on every launch).
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        if UserDefaults.standard.string(forKey: probeUnavailableKey) == osVersion { return nil }

        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        // Relaunch ourselves with the probe flag; a crash just means "unavailable".
        let result = Shell.run(
            executable.path,
            ["--surface-probe"],
            timeout: 15,
            environment: ["SWIFTWINDOW_SURFACE_PROBE": "1"]
        )
        guard result.status == 0 else {
            UserDefaults.standard.set(osVersion, forKey: probeUnavailableKey)
            return nil
        }

        var entries: [Int: SurfaceProbeEntry] = [:]
        for line in result.output.split(separator: "\n") {
            let columns = line.split(separator: "\t").map(String.init)
            guard columns.count >= 3,
                  let windowID = Int(columns[0]),
                  let surfaceCount = Int(columns[1]),
                  let owner = Int(columns[2]) else { continue }
            entries[windowID] = SurfaceProbeEntry(surfaceCount: surfaceCount, ownerConnection: owner)
        }
        return entries.isEmpty ? nil : entries
    }

    /// Enumerates every window known to WindowServer, estimates the backing
    /// store it must keep (`width × height × scale² × 4`, BGRA, using the
    /// backing scale of the display each window sits on — `kCGWindowMemoryUsage`
    /// is unreliable on current macOS), and annotates each window with its
    /// backing-surface count from the private SkyLight API when available.
    static func scanSurfaceReport() -> (windows: [WindowSurface], source: String) {
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return ([], "none")
        }
        let displays = displays()
        let fallback = displays.first ?? DisplayInfo(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scale: displayScale(),
            name: NSScreen.main?.localizedName ?? "Main"
        )
        let surfaceInfo = privateSurfaceInfo()
        let source = surfaceInfo != nil ? "private" : "geometry"

        var result: [WindowSurface] = []
        result.reserveCapacity(infoList.count)

        for info in infoList {
            let bounds = info["kCGWindowBounds"] as? [String: Any] ?? [:]
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            let x = bounds["X"] as? Double ?? 0
            let y = bounds["Y"] as? Double ?? 0
            let center = CGPoint(x: x + width / 2, y: y + height / 2)
            let display = display(at: center, in: displays, fallback: fallback)
            let windowID = info["kCGWindowNumber"] as? Int ?? -1
            let geometryBytes = UInt64(max(0, width * height * display.scale * display.scale * 4.0))

            result.append(WindowSurface(
                id: windowID,
                ownerPID: info["kCGWindowOwnerPID"] as? Int ?? -1,
                ownerName: info["kCGWindowOwnerName"] as? String ?? "?",
                windowName: info["kCGWindowName"] as? String ?? "",
                width: width,
                height: height,
                layer: info["kCGWindowLayer"] as? Int ?? 0,
                storeType: info["kCGWindowStoreType"] as? Int ?? -1,
                sharingState: info["kCGWindowSharingState"] as? Int ?? -1,
                onscreen: info["kCGWindowIsOnscreen"] as? Bool ?? false,
                estimatedBytes: geometryBytes,
                scale: display.scale,
                screenName: display.name,
                exact: false,
                surfaceCount: surfaceInfo?[windowID]?.surfaceCount ?? -1,
                ownerConnection: surfaceInfo?[windowID]?.ownerConnection ?? -1
            ))
        }
        return (result.sorted { $0.estimatedBytes > $1.estimatedBytes }, source)
    }

    static func scanWindows() -> [WindowSurface] {
        scanSurfaceReport().windows
    }

    static func attribute(_ windows: [WindowSurface]) -> [OwnerAttribution] {
        var buckets: [Int: OwnerAttribution] = [:]
        for window in windows {
            var bucket = buckets[window.ownerPID] ?? OwnerAttribution(
                pid: window.ownerPID,
                name: window.ownerName,
                windowCount: 0,
                fullscreenCount: 0,
                estimatedBytes: 0,
                isWindowServer: window.isWindowServer
            )
            bucket.windowCount += 1
            bucket.fullscreenCount += window.isFullscreen ? 1 : 0
            bucket.estimatedBytes += window.estimatedBytes
            bucket.name = window.ownerName
            buckets[window.ownerPID] = bucket
        }
        return buckets.values.sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    /// Lists processes that have created GPU / IOSurface clients. These are the
    /// apps currently holding compositor surfaces.
    static func scanSurfaceClients() -> [IOSurfaceClient] {
        var clients = Set<IOSurfaceClient>()
        let classes: [(String, String)] = [
            ("IOSurface", "/usr/sbin/ioreg -r -c IOSurfaceRootUserClient -l -w 0"),
            ("GPU(MTL)", "/usr/sbin/ioreg -r -c AGXDeviceUserClient -l -w 0")
        ]
        let nameByPID = processNames()

        for (label, command) in classes {
            let result = Shell.run("/bin/sh", ["-c", command], timeout: 20)
            for line in result.output.split(separator: "\n") where line.contains("IOUserClientCreator") {
                let text = String(line)
                guard let pid = firstInt(in: text) else { continue }
                let name = nameByPID[pid] ?? truncatedCreatorName(in: text)
                clients.insert(IOSurfaceClient(kind: label, pid: pid, name: name))
            }
        }
        return clients.sorted { ($0.name, $0.kind) < ($1.name, $1.kind) }
    }

    /// Joins every running process's own RSS with the surface memory
    /// WindowServer holds for that process, giving a real per-application
    /// memory ranking (RSS + surface estimate).
    static func appMemory(owners: [OwnerAttribution]) -> [AppMemoryRow] {
        let surfaceByPID = Dictionary(uniqueKeysWithValues: owners.map { ($0.pid, $0) })
        let result = Shell.run("/bin/ps", ["-Ao", "pid=,rss=,comm="])
        var rows: [AppMemoryRow] = []

        for raw in result.output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let pidPart = line[..<space].trimmingCharacters(in: .whitespaces)
            let rest = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            guard let pid = Int(pidPart) else { continue }
            guard let secondSpace = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let rssPart = rest[..<secondSpace].trimmingCharacters(in: .whitespaces)
            let comm = rest[rest.index(after: secondSpace)...].trimmingCharacters(in: .whitespaces)
            let rss = (UInt64(rssPart) ?? 0) * 1024
            let owner = surfaceByPID[pid]
            let surface = owner?.estimatedBytes ?? 0
            guard rss > 0 || surface > 0 else { continue }
            rows.append(AppMemoryRow(
                pid: pid,
                name: owner?.name ?? (comm as NSString).lastPathComponent,
                groupName: applicationBundleName(from: comm),
                residentBytes: rss,
                surfaceBytes: surface,
                windowCount: owner?.windowCount ?? 0
            ))
        }
        return rows.sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Derives the owning application from an executable path by taking the
    /// outermost `.app` bundle, so a main process and all of its helper
    /// processes collapse to one application name.
    static func applicationBundleName(from path: String) -> String {
        let components = path.split(separator: "/")
        if let app = components.first(where: { $0.hasSuffix(".app") }) {
            return String(app.dropLast(4))
        }
        return (path as NSString).lastPathComponent
    }

    static func group(_ rows: [AppMemoryRow]) -> [ApplicationMemory] {
        var buckets: [String: ApplicationMemory] = [:]
        for row in rows {
            var bucket = buckets[row.groupName] ?? ApplicationMemory(
                name: row.groupName,
                processCount: 0,
                residentBytes: 0,
                surfaceBytes: 0,
                windowCount: 0
            )
            bucket.processCount += 1
            bucket.residentBytes += row.residentBytes
            bucket.surfaceBytes += row.surfaceBytes
            bucket.windowCount += row.windowCount
            buckets[row.groupName] = bucket
        }
        return buckets.values.sorted { $0.totalBytes > $1.totalBytes }
    }

    static func processNames() -> [Int: String] {
        var map: [Int: String] = [:]
        let result = Shell.run("/bin/ps", ["-Ao", "pid=,comm="])
        for raw in result.output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let pidPart = line[..<space].trimmingCharacters(in: .whitespaces)
            let comm = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            if let pid = Int(pidPart) {
                map[pid] = (comm as NSString).lastPathComponent
            }
        }
        return map
    }

    private static func firstInt(in line: String) -> Int? {
        guard let pidRange = line.range(of: "pid ") else { return nil }
        let digits = line[pidRange.upperBound...].prefix { $0.isNumber }
        return Int(String(digits))
    }

    private static func truncatedCreatorName(in line: String) -> String {
        guard let eq = line.range(of: "= \"") else { return "?" }
        let rest = line[eq.upperBound...]
        guard let comma = rest.range(of: ", ") else { return "?" }
        let name = rest[comma.upperBound...]
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }
}
