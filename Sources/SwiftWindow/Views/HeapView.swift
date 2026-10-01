import SwiftUI

struct HeapView: View {
    @EnvironmentObject private var engine: MonitorEngine
    @State private var search = ""

    private var allocations: [HeapAllocation] {
        guard let all = engine.report?.heap.allocations else { return [] }
        guard !search.isEmpty else { return all }
        let needle = search.lowercased()
        return all.filter {
            $0.className.lowercased().contains(needle)
                || $0.binary.lowercased().contains(needle)
                || $0.type.lowercased().contains(needle)
        }
    }

    var body: some View {
        if engine.report == nil {
            EmptyStateView(
                systemImage: "square.grid.3x3",
                title: "尚无堆分配数据",
                message: "加载详细分析后，这里将展示 heap 解析出的对象类、计数与字节数，帮助定位谁占用了 WindowServer 的堆内存。"
            )
        } else if let heap = engine.report?.heap {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text("共 \(heap.totalNodes) 个对象 · \(ByteFormat.string(heap.totalBytes)) · \(heap.zoneCount) 个 zone")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("过滤类名 / 库", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    Text("\(allocations.count) 行").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                Table(allocations) {
                    TableColumn("字节数") { item in
                        Text(ByteFormat.string(item.bytes)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn("对象数") { item in
                        Text("\(item.count)").monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("平均") { item in
                        Text(ByteFormat.string(item.count > 0 ? Int(item.bytes) / item.count : 0)).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("类型") { item in
                        Text(item.type.isEmpty ? "—" : item.type).foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("类名 / 对象") { item in
                        Text(item.className).font(.callout).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("所属二进制") { item in
                        Text(item.binary).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    .width(min: 140, ideal: 200)
                }
            }
        }
    }
}
