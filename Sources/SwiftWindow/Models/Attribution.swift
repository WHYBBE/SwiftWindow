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
    var scale: Double = 1
    var screenName: String = ""
    /// True when the byte count came from the private surface API instead of a
    /// geometry estimate.
    var exact: Bool = false
    /// Number of backing surfaces reported by the private SkyLight API, or -1
    /// when unknown.
    var surfaceCount: Int = -1
    /// Owning SkyLight connection reported by the private API, or -1 when
    /// unknown. 0 means the window is server-owned (no client connection).
    var ownerConnection: Int = -1

    var isServerOwned: Bool { ownerConnection == 0 }

    var isFullscreen: Bool { width >= 1800 && height >= 1000 }
    var isWindowServer: Bool { ownerName == "Window Server" || ownerName == "WindowServer" }

    var kind: String {
        if isFullscreen { return isWindowServer ? "系统全屏图面" : "全屏窗口" }
        if width <= 1 || height <= 1 { return "占位/隐藏" }
        return "普通窗口"
    }

    /// Human-readable window level. The values near the 32-bit extremes are
    /// private WindowServer levels used for system compositor/transition
    /// surfaces (they are exactly what the OS reports, not a parsing error).
    var layerLabel: String {
        switch layer {
        case 0: return "普通 (0)"
        case 3: return "浮动 (3)"
        case 8: return "模态 (8)"
        case 24: return "菜单栏 (24)"
        case 25: return "状态栏 (25)"
        case 1000: return "屏保 (1000)"
        case -2147483623: return "桌面 (0x80000019)"
        case 2147483646: return "系统过渡 (0x7FFFFFFE)"
        case -2147483626: return "系统过渡 (0x80000016)"
        default:
            return (layer > 2_000_000_000 || layer < -2_000_000_000)
                ? String(format: "系统私有 (0x%08X)", UInt32(bitPattern: Int32(truncatingIfNeeded: layer)))
                : "\(layer)"
        }
    }
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
    /// "private" when the private SkyLight surface API worked, otherwise
    /// "geometry" for the fallback estimate.
    var surfaceSource: String = "geometry"
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
