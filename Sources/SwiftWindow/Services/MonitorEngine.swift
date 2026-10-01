import Foundation
import SwiftUI

@MainActor
final class MonitorEngine: ObservableObject {
    @Published private(set) var stats: BasicProcessStats?
    @Published private(set) var report: DetailedReport?
    @Published private(set) var samples: [RSSSample] = []
    @Published var autoRefresh = false
    @Published private(set) var isLoadingDetails = false
    @Published private(set) var statusMessage = "点击“加载详细分析”以获取 vmmap / footprint / heap 明细"
    @Published var errorMessage: String?

    private var timer: Timer?
    private var detailLoading = false

    var pid: Int? { stats?.pid }

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
        }
    }

    func loadDetails() {
        guard let pid = stats?.pid else {
            refreshBasic()
            return
        }
        guard !detailLoading else { return }
        detailLoading = true
        isLoadingDetails = true
        statusMessage = "正在请求管理员权限并采集数据…"

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
            case .failure(let error):
                if let privileged = error as? PrivilegedError, case .cancelled = privileged {
                    self.statusMessage = "已取消授权"
                } else {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = "分析失败"
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
            lines.append("")
            lines.append("== 内存足迹分类 (footprint) ==")
            for category in report.footprint.categories {
                lines.append("\(ByteFormat.string(category.dirtyBytes))\t\(category.regionCount)\t\(category.category)")
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
