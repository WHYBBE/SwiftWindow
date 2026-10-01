import Foundation
import CoreGraphics
import AppKit

enum WindowAttributionService {
    static func displayScale() -> Double {
        Double(NSScreen.main?.backingScaleFactor ?? 2.0)
    }

    /// Enumerates every window known to WindowServer and estimates the backing
    /// store it must keep. `kCGWindowMemoryUsage` is unreliable on current
    /// macOS (it returns a constant), so we estimate from the window geometry:
    /// bytes ≈ width × height × scale² × 4 (BGRA).
    static func scanWindows(scale: Double) -> [WindowSurface] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [WindowSurface] = []
        result.reserveCapacity(infoList.count)

        for info in infoList {
            let bounds = info["kCGWindowBounds"] as? [String: Any] ?? [:]
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            let bytes = UInt64(max(0, width * height * scale * scale * 4.0))

            result.append(WindowSurface(
                id: info["kCGWindowNumber"] as? Int ?? -1,
                ownerPID: info["kCGWindowOwnerPID"] as? Int ?? -1,
                ownerName: info["kCGWindowOwnerName"] as? String ?? "?",
                windowName: info["kCGWindowName"] as? String ?? "",
                width: width,
                height: height,
                layer: info["kCGWindowLayer"] as? Int ?? 0,
                storeType: info["kCGWindowStoreType"] as? Int ?? -1,
                sharingState: info["kCGWindowSharingState"] as? Int ?? -1,
                onscreen: info["kCGWindowIsOnscreen"] as? Bool ?? false,
                estimatedBytes: bytes
            ))
        }
        return result.sorted { $0.estimatedBytes > $1.estimatedBytes }
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
