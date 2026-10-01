import SwiftUI
import Charts

struct FootprintView: View {
    @EnvironmentObject private var engine: MonitorEngine

    private var categories: [FootprintCategory] { engine.report?.footprint.categories ?? [] }
    private var maxDirty: UInt64 { categories.map(\.dirtyBytes).max() ?? 1 }

    var body: some View {
        if engine.report == nil {
            EmptyStateView(
                systemImage: "chart.bar.doc.horizontal",
                title: "尚无内存足迹数据",
                message: "加载详细分析后，这里将按 footprint 类别（Malloc、__DATA、page table 等）展示 Dirty / Clean 内存构成。"
            )
        } else if let footprint = engine.report?.footprint {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        StatCard(
                            title: "物理足迹",
                            value: ByteFormat.string(footprint.footprintBytes),
                            subtitle: "footprint 报告值",
                            systemImage: "memorychip.fill",
                            tint: .blue
                        )
                        StatCard(
                            title: "峰值",
                            value: ByteFormat.string(footprint.peakBytes),
                            subtitle: "phys_footprint_peak",
                            systemImage: "arrow.up.right",
                            tint: .indigo
                        )
                        StatCard(
                            title: "类别数",
                            value: "\(categories.count)",
                            subtitle: "footprint 分类",
                            systemImage: "square.grid.3x3.fill",
                            tint: .teal
                        )
                    }

                    if !categories.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dirty 内存 Top 类别").font(.headline)
                            Chart(categories.prefix(12)) { item in
                                BarMark(
                                    x: .value("Dirty", Double(item.dirtyBytes)),
                                    y: .value("类别", item.category)
                                )
                                .foregroundStyle(.blue.gradient)
                            }
                            .chartXAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let raw = value.as(Double.self) {
                                            Text(ByteFormat.string(UInt64(raw)))
                                        }
                                    }
                                }
                            }
                            .frame(height: max(160, CGFloat(min(categories.count, 12)) * 28))
                        }
                        .padding(14)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("全部类别").font(.headline)
                            VStack(spacing: 8) {
                                ForEach(categories) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.category).font(.callout)
                                            Spacer()
                                            Text("dirty \(ByteFormat.string(item.dirtyBytes)) · clean \(ByteFormat.string(item.cleanBytes)) · reclaimable \(ByteFormat.string(item.reclaimableBytes)) · \(item.regionCount) 区")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        RatioBar(fraction: Double(item.dirtyBytes) / Double(max(maxDirty, 1)))
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
                    }
                }
                .padding(16)
            }
        }
    }
}
