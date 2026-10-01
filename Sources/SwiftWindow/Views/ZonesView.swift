import SwiftUI

struct ZonesView: View {
    @EnvironmentObject private var engine: MonitorEngine

    private var zones: [MallocZone] { engine.report?.vmmap.zones ?? [] }

    var body: some View {
        if engine.report == nil {
            EmptyStateView(
                systemImage: "shippingbox",
                title: "尚无 Malloc Zone 数据",
                message: "加载详细分析后，这里将展示 vmmap 的 MALLOC ZONE 表，用于定位内存碎片与分配热点。"
            )
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Malloc Zone 明细（虚拟 / 常驻 / Dirty / 已分配 / 碎片率）")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(zones.count) 个 zone").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                Table(zones) {
                    TableColumn("Zone 名称") { zone in
                        Text(zone.name).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                    .width(min: 160, ideal: 240)
                    TableColumn("虚拟") { zone in Text(ByteFormat.string(zone.virtualBytes)).monospacedDigit() }
                        .width(min: 80, ideal: 100)
                    TableColumn("常驻") { zone in Text(ByteFormat.string(zone.residentBytes)).monospacedDigit() }
                        .width(min: 80, ideal: 100)
                    TableColumn("Dirty") { zone in Text(ByteFormat.string(zone.dirtyBytes)).monospacedDigit() }
                        .width(min: 80, ideal: 100)
                    TableColumn("已分配字节") { zone in Text(ByteFormat.string(zone.allocatedBytes)).monospacedDigit() }
                        .width(min: 90, ideal: 120)
                    TableColumn("分配次数") { zone in Text("\(zone.allocationCount)").monospacedDigit() }
                        .width(min: 70, ideal: 90)
                    TableColumn("碎片大小") { zone in Text(ByteFormat.string(zone.fragBytes)).monospacedDigit() }
                        .width(min: 80, ideal: 100)
                    TableColumn("碎片率") { zone in
                        HStack(spacing: 6) {
                            RatioBar(fraction: zone.fragPercent / 100, tint: zone.fragPercent > 50 ? .red : .green)
                                .frame(width: 60)
                            Text(String(format: "%.0f%%", zone.fragPercent)).monospacedDigit()
                        }
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("区域数") { zone in Text("\(zone.regionCount)").monospacedDigit() }
                        .width(min: 60, ideal: 80)
                }
            }
        }
    }
}
