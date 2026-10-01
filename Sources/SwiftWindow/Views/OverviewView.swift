import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject private var engine: MonitorEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                liveChart
                if let report = engine.report {
                    detailSummary(report)
                    aggregatedRegions(report)
                } else {
                    EmptyStateView(
                        systemImage: "lock.shield",
                        title: "尚无详细数据",
                        message: "点击右上角“加载详细分析”并授权管理员权限，将采集 vmmap / footprint / heap 的完整明细。"
                    )
                    .frame(height: 240)
                }
            }
            .padding(16)
        }
    }

    private var liveChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常驻内存实时曲线")
                .font(.headline)
            if engine.samples.count < 2 {
                EmptyStateView(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "正在采样",
                    message: "开启“自动刷新”可积累更多采样点。"
                )
                .frame(height: 160)
            } else {
                Chart(engine.samples) { sample in
                    AreaMark(
                        x: .value("时间", sample.date),
                        y: .value("RSS", Double(sample.bytes))
                    )
                    .foregroundStyle(.blue.opacity(0.18))
                    LineMark(
                        x: .value("时间", sample.date),
                        y: .value("RSS", Double(sample.bytes))
                    )
                    .foregroundStyle(.blue)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let raw = value.as(Double.self) {
                                Text(ByteFormat.string(UInt64(raw)))
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    private func detailSummary(_ report: DetailedReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("vmmap 摘要")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                StatCard(
                    title: "Physical Footprint",
                    value: ByteFormat.string(report.vmmap.physicalFootprint),
                    subtitle: "物理足迹（真实占用）",
                    systemImage: "memorychip.fill",
                    tint: .blue
                )
                StatCard(
                    title: "Footprint 峰值",
                    value: ByteFormat.string(report.vmmap.physicalFootprintPeak),
                    subtitle: "历史最高",
                    systemImage: "arrow.up.right",
                    tint: .indigo
                )
                StatCard(
                    title: "虚拟内存总量",
                    value: ByteFormat.string(report.vmmap.virtualSize),
                    subtitle: "\(report.vmmap.regions.count) 个区域",
                    systemImage: "square.stack.3d.up.fill",
                    tint: .purple
                )
                StatCard(
                    title: "Malloc Zone 分配",
                    value: ByteFormat.string(report.heap.totalBytes),
                    subtitle: "\(report.heap.totalNodes) 个对象 · \(report.heap.zoneCount) zone",
                    systemImage: "shippingbox.fill",
                    tint: .orange
                )
            }
        }
    }

    private func aggregatedRegions(_ report: DetailedReport) -> some View {
        let maxDirty = report.vmmap.aggregates.map(\.dirtyBytes).max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("区域类型聚合（按 dirty 排序）")
                .font(.headline)
            VStack(spacing: 10) {
                ForEach(report.vmmap.aggregates.prefix(15)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.type).font(.callout)
                            Spacer()
                            Text("dirty \(ByteFormat.string(item.dirtyBytes)) · resident \(ByteFormat.string(item.residentBytes)) · virtual \(ByteFormat.string(item.virtualBytes)) · \(item.regionCount) 区")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        RatioBar(fraction: Double(item.dirtyBytes) / Double(max(maxDirty, 1)), tint: .blue)
                    }
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }
}
