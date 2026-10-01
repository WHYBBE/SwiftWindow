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
