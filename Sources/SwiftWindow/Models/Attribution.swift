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

/// A process-level memory row: its own CPU-side resident memory plus the
/// compositor surface memory WindowServer holds for its windows.
struct AppMemoryRow: Sendable, Identifiable {
    var id: Int { pid }
    var pid: Int
    var name: String
    var groupName: String
    var residentBytes: UInt64
    var surfaceBytes: UInt64
    var windowCount: Int
    var totalBytes: UInt64 { residentBytes + surfaceBytes }
}

/// Several processes that belong to the same application bundle (for example
/// the main Edge process plus all of its helper/renderer processes) merged into
/// one row.
struct ApplicationMemory: Sendable, Identifiable {
    var id: String { name }
    var name: String
    var processCount: Int
    var residentBytes: UInt64
    var surfaceBytes: UInt64
    var windowCount: Int
    var totalBytes: UInt64 { residentBytes + surfaceBytes }
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
    var owners: [OwnerAttribution]
}

/// Growth of one process between the first and last surface sample.
/// Positive growth of window count / surface bytes is the practical signal of
/// a window or surface leak.
struct OwnerTrend: Sendable, Identifiable {
    var id: Int { pid }
    var pid: Int
    var name: String
    var windowGrowth: Int
    var surfaceGrowthBytes: Int64
    var currentBytes: UInt64
    var currentWindows: Int
}

struct AttributionSnapshot: Sendable {
    var date: Date
    var displayScale: Double
    var owners: [OwnerAttribution]
    var appMemory: [AppMemoryRow]
    var applications: [ApplicationMemory]
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
