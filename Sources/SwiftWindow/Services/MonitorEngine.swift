import Foundation
import SwiftUI

@MainActor
final class MonitorEngine: ObservableObject {
    @Published private(set) var stats: BasicProcessStats?
    @Published private(set) var report: DetailedReport?
    @Published private(set) var samples: [RSSSample] = []
    @Published private(set) var attribution: AttributionSnapshot?
    @Published private(set) var findings: [DiagnosisFinding] = []
    @Published private(set) var surfaceSamples: [SurfaceSample] = []
    @Published private(set) var leaks: LeaksReport?
    @Published var autoRefresh = false
    @Published private(set) var isLoadingDetails = false
    @Published private(set) var isLeakScanning = false
    @Published private(set) var statusMessage = "点击“加载详细分析”以获取 vmmap / footprint / heap 明细"
    @Published var errorMessage: String?

    private var timer: Timer?
    private var detailLoading = false
    private var leakScanning = false
    private var cachedClients: [IOSurfaceClient] = []
    private var cachedStage = StageManagerState()
    private var cacheDate = Date.distantPast

    var pid: Int? { stats?.pid }

    /// True while any administrator-authorized operation is running. All
    /// privileged buttons must be disabled while this is true so the system
    /// password sheet can never be triggered twice at once.
    var isPrivilegedBusy: Bool { isLoadingDetails || isLeakScanning }

    /// Activity Monitor shows a task's *physical footprint*, which includes
    /// GPU/IOSurface backing stores that never appear in `ps` RSS. We reconcile
    /// the two views as: RSS (ps) + WindowServer surface estimate ≈ footprint.
    var estimatedFootprintBytes: UInt64 {
        (stats?.residentBytes ?? 0) + (attribution?.windowServerSurfaceBytes ?? 0)
    }

    /// Ranked per-process growth between the first and last collected sample.
    var ownerTrends: [OwnerTrend] {
        guard surfaceSamples.count >= 2,
              let first = surfaceSamples.first,
              let last = surfaceSamples.last,
              !first.owners.isEmpty else { return [] }
        let baseline = Dictionary(uniqueKeysWithValues: first.owners.map { ($0.pid, $0) })
        var trends: [OwnerTrend] = []
        for owner in last.owners {
            let before = baseline[owner.pid]
            let surfaceGrowth = Int64(owner.estimatedBytes) - Int64(before?.estimatedBytes ?? 0)
            let windowGrowth = owner.windowCount - (before?.windowCount ?? 0)
            if surfaceGrowth > 4 * 1024 * 1024 || windowGrowth > 1 {
                trends.append(OwnerTrend(
                    pid: owner.pid,
                    name: owner.name,
                    windowGrowth: windowGrowth,
                    surfaceGrowthBytes: surfaceGrowth,
                    currentBytes: owner.estimatedBytes,
                    currentWindows: owner.windowCount
                ))
            }
        }
        return trends.sorted { $0.surfaceGrowthBytes > $1.surfaceGrowthBytes }
    }

    func start() {
        refreshBasic()
    }

    func refreshBasic() {
        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .utility) {
                WindowServerLocator.locateAndStat()
            }.value

            guard let result else {
                self.errorMessage = "未找到 WindowServer 进程。"
                return
            }
            self.errorMessage = nil
            self.stats = result
            self.samples.append(RSSSample(date: result.sampledAt, bytes: result.residentBytes))
            if self.samples.count > 120 {
                self.samples.removeFirst(self.samples.count - 120)
            }
            self.refreshAttribution()
        }
    }

    /// Scans the compositor window list (fast, no privileges). GPU/IOSurface
    /// client and Stage Manager state are cached and refreshed at most every
    /// 30 seconds unless `force` is set.
    func refreshAttribution(force: Bool = false) {
        let needsFullScan = force || cacheDate == .distantPast || Date().timeIntervalSince(cacheDate) > 30
        let previousClients = cachedClients
        let previousStage = cachedStage
        let rss = stats?.residentBytes ?? 0

        Task { [weak self] in
            guard let self else { return }
            let scan = await Task.detached(priority: .utility) { () -> (AttributionSnapshot, [IOSurfaceClient], StageManagerState) in
                let scale = WindowAttributionService.displayScale()
                let surface = WindowAttributionService.scanSurfaceReport()
                let windows = surface.windows
                let owners = WindowAttributionService.attribute(windows)
                let clients = needsFullScan ? WindowAttributionService.scanSurfaceClients() : previousClients
                let stage = needsFullScan ? StageManagerService.state() : previousStage
                let windowServerWindows = windows.filter(\.isWindowServer)
                let appRows = WindowAttributionService.appMemory(owners: owners)
                let snapshot = AttributionSnapshot(
                    date: Date(),
                    displayScale: scale,
                    owners: owners,
                    appMemory: appRows,
                    applications: WindowAttributionService.group(appRows),
                    windows: windows,
                    surfaceClients: clients,
                    stageManager: stage,
                    totalSurfaceBytes: windows.reduce(0) { $0 + $1.estimatedBytes },
                    windowServerSurfaceBytes: windowServerWindows.reduce(0) { $0 + $1.estimatedBytes },
                    windowServerFullscreenCount: windowServerWindows.filter(\.isFullscreen).count,
                    surfaceSource: surface.source
                )
                return (snapshot, clients, stage)
            }.value

            self.attribution = scan.0
            self.cachedClients = scan.1
            self.cachedStage = scan.2
            if needsFullScan { self.cacheDate = Date() }

            self.surfaceSamples.append(SurfaceSample(
                date: scan.0.date,
                windowServerResidentBytes: rss,
                totalSurfaceBytes: scan.0.totalSurfaceBytes,
                windowServerSurfaceBytes: scan.0.windowServerSurfaceBytes,
                windowServerFullscreenCount: scan.0.windowServerFullscreenCount,
                totalWindowCount: scan.0.windows.count,
                owners: scan.0.owners
            ))
            if self.surfaceSamples.count > 120 {
                self.surfaceSamples.removeFirst(self.surfaceSamples.count - 120)
            }
            self.recomputeFindings()
        }
    }

    func recomputeFindings() {
        guard let attribution else { return }
        findings = DiagnosisEngine.findings(
            snapshot: attribution,
            report: report,
            samples: surfaceSamples,
            trends: ownerTrends,
            rssBytes: stats?.residentBytes ?? 0
        )
    }

    func loadDetails() {
        guard let pid = stats?.pid else {
            refreshBasic()
            return
        }
        guard !detailLoading, !leakScanning else {
            PrivilegedRunner.log("loadDetails IGNORED (busy)")
            return
        }
        PrivilegedRunner.log("loadDetails entry")
        detailLoading = true
        isLoadingDetails = true
        statusMessage = "正在请求管理员权限并采集 vmmap / footprint / heap（WindowServer 体积大，约需 30–60 秒）…"

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<DetailedReport, Error> in
                do {
                    let outputs = try PrivilegedRunner.runBatch([
                        ["/usr/bin/vmmap", String(pid)],
                        ["/usr/bin/footprint", String(pid)],
                        ["/usr/bin/heap", String(pid)]
                    ])
                    let report = DetailedReport(
                        vmmap: VMMapParser.parse(outputs[safe: 0] ?? "", pid: pid),
                        footprint: FootprintParser.parse(outputs[safe: 1] ?? ""),
                        heap: HeapParser.parse(outputs[safe: 2] ?? ""),
                        generatedAt: Date()
                    )
                    return .success(report)
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self else { return }
            self.detailLoading = false
            self.isLoadingDetails = false
            switch result {
            case .success(let report):
                self.report = report
                let regions = report.vmmap.regions.count
                self.statusMessage = "分析完成 · \(regions) 个内存区域 · \(report.vmmap.zones.count) 个 malloc zone"
                self.errorMessage = nil
                self.recomputeFindings()
            case .failure(let error):
                if let privileged = error as? PrivilegedError, case .cancelled = privileged {
                    self.statusMessage = "已取消授权"
                } else if let privileged = error as? PrivilegedError, case .busy = privileged {
                    self.statusMessage = "已有一次授权正在进行，请稍候"
                } else {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "分析失败"
                }
            }
        }
    }

    /// Runs `leaks` against WindowServer (requires admin). This looks for
    /// leaked malloc blocks *inside* WindowServer and names the responsible
    /// libraries in the stack traces.
    func runLeakScan() {
        guard let pid = stats?.pid else { return }
        guard !leakScanning, !detailLoading else { return }
        leakScanning = true
        isLeakScanning = true
        statusMessage = "正在运行 leaks 深度扫描（可能持续数分钟，期间请勿重复点击）…"

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<LeaksReport, Error> in
                do {
                    let outputs = try PrivilegedRunner.runBatch([
                        ["/usr/bin/leaks", String(pid)]
                    ], timeout: 600)
                    return .success(LeaksParser.parse(outputs.first ?? ""))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self else { return }
            self.leakScanning = false
            self.isLeakScanning = false
            switch result {
            case .success(let report):
                self.leaks = report
                self.statusMessage = "leaks 扫描完成 · 发现 \(report.totalLeaks) 处泄漏 · 共 \(ByteFormat.string(report.totalBytes))"
                self.recomputeFindings()
            case .failure(let error):
                if let privileged = error as? PrivilegedError, case .cancelled = privileged {
                    self.statusMessage = "已取消授权"
                } else if let privileged = error as? PrivilegedError, case .busy = privileged {
                    self.statusMessage = "已有一次授权正在进行，请稍候"
                } else {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "leaks 扫描失败"
                }
            }
        }
    }

    func setAutoRefresh(_ enabled: Bool) {
        autoRefresh = enabled
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBasic() }
        }
    }

    func exportReport() -> String {
        var lines: [String] = []
        lines.append("WindowServer 内存分析报告")
        lines.append("生成时间: \(Date())")
        if let stats {
            lines.append("PID: \(stats.pid)")
            lines.append("路径: \(stats.path)")
            lines.append("Resident (RSS): \(ByteFormat.string(stats.residentBytes))")
            lines.append("Virtual (VSZ): \(ByteFormat.string(stats.virtualBytes))")
            lines.append("CPU: \(String(format: "%.1f", stats.cpuPercent))%  线程: \(stats.threadCount)")
        }
        if !findings.isEmpty {
            lines.append("")
            lines.append("== 诊断结论 ==")
            for finding in findings {
                lines.append("[\(finding.severity.label)] \(finding.title)")
                if let suspect = finding.suspect { lines.append("  嫌疑来源: \(suspect)") }
                for line in finding.detail.split(separator: "\n") {
                    lines.append("  \(line)")
                }
            }
        }
        if let attribution {
            lines.append("")
            lines.append("== Surface 归因（按估算占用排序）==")
            for owner in attribution.owners.prefix(20) {
                lines.append(String(format: "%@\t%@\twindows=%d\tfullscreen=%d",
                                    ByteFormat.string(owner.estimatedBytes) as NSString,
                                    owner.name as NSString,
                                    owner.windowCount,
                                    owner.fullscreenCount))
            }
        }
        if let report {
            lines.append("")
            lines.append("== 虚拟内存摘要 (vmmap) ==")
            lines.append("Physical footprint: \(ByteFormat.string(report.vmmap.physicalFootprint))")
            lines.append("Physical footprint peak: \(ByteFormat.string(report.vmmap.physicalFootprintPeak))")
            lines.append("Virtual size: \(ByteFormat.string(report.vmmap.virtualSize))")
            lines.append("")
            lines.append("-- 区域聚合 (按 dirty 排序) --")
            for item in report.vmmap.aggregates.prefix(40) {
                lines.append(String(format: "%-32@ virtual=%-10@ resident=%-10@ dirty=%-10@ count=%d",
                                    item.type as NSString,
                                    ByteFormat.string(item.virtualBytes) as NSString,
                                    ByteFormat.string(item.residentBytes) as NSString,
                                    ByteFormat.string(item.dirtyBytes) as NSString,
                                    item.regionCount))
            }
            lines.append("")
            lines.append("== malloc zone ==")
            for zone in report.vmmap.zones {
                lines.append("\(zone.name): resident=\(ByteFormat.string(zone.residentBytes)) allocated=\(ByteFormat.string(zone.allocatedBytes)) fragments=\(String(format: "%.0f", zone.fragPercent))%")
            }
            lines.append("")
            lines.append("== 堆分配 (heap, 前 60) ==")
            for alloc in report.heap.allocations.prefix(60) {
                lines.append("\(ByteFormat.string(alloc.bytes))\t\(alloc.count)\t\(alloc.type)\t\(alloc.className)\t\(alloc.binary)")
            }
        }
        if let leaks {
            lines.append("")
            lines.append("== leaks 深度扫描 ==")
            lines.append("泄漏处数: \(leaks.totalLeaks)  泄漏字节: \(ByteFormat.string(leaks.totalBytes))")
            for entry in leaks.entries.prefix(40) {
                lines.append("\(ByteFormat.string(entry.bytes))\t\(entry.description)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
