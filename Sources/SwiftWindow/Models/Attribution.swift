import Foundation

/// One CGWindow, with an estimate of the backing-store memory WindowServer
/// must hold for it.
struct WindowSurface: Sendable, Identifiable {
    var id: Int
    var ownerPID: Int
    var ownerName: String
    var windowName: String
    var width: Double
    var height: Double
    var layer: Int
    var storeType: Int
    var sharingState: Int
    var onscreen: Bool
    var estimatedBytes: UInt64

    var isFullscreen: Bool { width >= 1800 && height >= 1000 }
    var isWindowServer: Bool { ownerName == "Window Server" || ownerName == "WindowServer" }
}

/// Aggregated surface attribution for one owning process.
struct OwnerAttribution: Sendable, Identifiable {
    var id: Int { pid }
    var pid: Int
    var name: String
    var windowCount: Int
    var fullscreenCount: Int
    var estimatedBytes: UInt64
    var isWindowServer: Bool
}

/// A process connected to the GPU / IOSurface subsystem
/// (`IOSurfaceRootUserClient`, `AGXDeviceUserClient`).
struct IOSurfaceClient: Sendable, Identifiable, Hashable {
    var id: String { "\(kind)-\(pid)-\(name)" }
    var kind: String
    var pid: Int
    var name: String
}

struct StageManagerState: Sendable {
    var enabled: Bool = false
    var managementMode: Int = 0
    var ageSeconds: Double = 0
    var windowSetCount: Int = 0
    var appEntryCount: Int = 0
    var distinctApps: Int = 0
    var topApps: [(app: String, sets: Int)] = []
}

struct SurfaceSample: Sendable, Identifiable {
    var id = UUID()
    var date: Date
    var windowServerResidentBytes: UInt64
    var totalSurfaceBytes: UInt64
    var windowServerSurfaceBytes: UInt64
    var windowServerFullscreenCount: Int
    var totalWindowCount: Int
}

struct AttributionSnapshot: Sendable {
    var date: Date
    var displayScale: Double
    var owners: [OwnerAttribution]
    var windows: [WindowSurface]
    var surfaceClients: [IOSurfaceClient]
    var stageManager: StageManagerState
    var totalSurfaceBytes: UInt64
    var windowServerSurfaceBytes: UInt64
    var windowServerFullscreenCount: Int
}

enum FindingSeverity: Int, Sendable, Comparable {
    case info = 0
    case notice = 1
    case warning = 2
    case critical = 3

    static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .info: return "信息"
        case .notice: return "提示"
        case .warning: return "警告"
        case .critical: return "严重"
        }
    }
}

struct DiagnosisFinding: Sendable, Identifiable {
    var id = UUID()
    var severity: FindingSeverity
    var title: String
    var detail: String
    var suspect: String?
}
