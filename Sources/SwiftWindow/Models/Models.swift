import Foundation

struct BasicProcessStats: Sendable {
    var pid: Int
    var path: String
    var residentBytes: UInt64
    var virtualBytes: UInt64
    var cpuPercent: Double
    var memPercent: Double
    var threadCount: Int
    var elapsed: String
    var sampledAt: Date
}

struct RSSSample: Sendable, Identifiable {
    var id = UUID()
    var date: Date
    var bytes: UInt64
}

struct MemoryRegion: Sendable, Identifiable {
    var id = UUID()
    var type: String
    var start: String
    var end: String
    var virtualBytes: UInt64
    var residentBytes: UInt64
    var dirtyBytes: UInt64
    var swappedBytes: UInt64
    var protection: String
    var sharing: String
    var detail: String
}

struct RegionAggregate: Sendable, Identifiable {
    var id: String { type }
    var type: String
    var virtualBytes: UInt64
    var residentBytes: UInt64
    var dirtyBytes: UInt64
    var regionCount: Int
}

struct MallocZone: Sendable, Identifiable {
    var id: String { name }
    var name: String
    var virtualBytes: UInt64
    var residentBytes: UInt64
    var dirtyBytes: UInt64
    var allocatedBytes: UInt64
    var allocationCount: Int
    var fragBytes: UInt64
    var fragPercent: Double
    var regionCount: Int
}

struct VMMapReport: Sendable {
    var processName: String = ""
    var pid: Int = 0
    var codeType: String = ""
    var osVersion: String = ""
    var pageSize: UInt64 = 0
    var physicalFootprint: UInt64 = 0
    var physicalFootprintPeak: UInt64 = 0
    var virtualSize: UInt64 = 0
    var regions: [MemoryRegion] = []
    var aggregates: [RegionAggregate] = []
    var zones: [MallocZone] = []
}

struct FootprintCategory: Sendable, Identifiable {
    var id: String { category }
    var category: String
    var dirtyBytes: UInt64
    var cleanBytes: UInt64
    var reclaimableBytes: UInt64
    var regionCount: Int
}

struct FootprintReport: Sendable {
    var processName: String = ""
    var pid: Int = 0
    var footprintBytes: UInt64 = 0
    var peakBytes: UInt64 = 0
    var pageSize: UInt64 = 0
    var categories: [FootprintCategory] = []
}

struct HeapAllocation: Sendable, Identifiable {
    var id = UUID()
    var className: String
    var type: String
    var binary: String
    var count: Int
    var bytes: UInt64
}

struct HeapReport: Sendable {
    var zoneCount: Int = 0
    var totalNodes: Int = 0
    var totalBytes: UInt64 = 0
    var allocations: [HeapAllocation] = []
}

struct DetailedReport: Sendable {
    var vmmap: VMMapReport
    var footprint: FootprintReport
    var heap: HeapReport
    var generatedAt: Date
}
