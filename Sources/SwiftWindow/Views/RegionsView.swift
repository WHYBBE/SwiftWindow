import SwiftUI

struct RegionsView: View {
    @EnvironmentObject private var engine: MonitorEngine
    @State private var search = ""
    @State private var sortField: RegionSortField = .resident
    @State private var ascending = false

    enum RegionSortField: String, CaseIterable, Identifiable {
        case resident = "常驻"
        case dirty = "Dirty"
        case virtual = "虚拟"
        case type = "类型"
        case count = "地址"
        var id: String { rawValue }
    }

    private var rows: [MemoryRegion] {
        guard let regions = engine.report?.vmmap.regions else { return [] }
        let filtered: [MemoryRegion]
        if search.isEmpty {
            filtered = regions
        } else {
            let needle = search.lowercased()
            filtered = regions.filter {
                $0.type.lowercased().contains(needle)
                    || $0.detail.lowercased().contains(needle)
                    || $0.start.lowercased().contains(needle)
            }
        }
        let sorted = filtered.sorted { lhs, rhs in
            switch sortField {
            case .resident: return ascending ? lhs.residentBytes < rhs.residentBytes : lhs.residentBytes > rhs.residentBytes
            case .dirty: return ascending ? lhs.dirtyBytes < rhs.dirtyBytes : lhs.dirtyBytes > rhs.dirtyBytes
            case .virtual: return ascending ? lhs.virtualBytes < rhs.virtualBytes : lhs.virtualBytes > rhs.virtualBytes
            case .type: return ascending ? lhs.type < rhs.type : lhs.type > rhs.type
            case .count: return ascending ? lhs.start < rhs.start : lhs.start > rhs.start
            }
        }
        return sorted
    }

    var body: some View {
        if engine.report == nil {
            emptyState
        } else {
            VStack(spacing: 0) {
                toolbar
                Divider()
                Table(rows) {
                    TableColumn("区域类型") { row in
                        Text(row.type).font(.callout).lineLimit(1)
                    }
                    .width(min: 140, ideal: 200)
                    TableColumn("虚拟大小") { row in
                        Text(ByteFormat.string(row.virtualBytes)).monospacedDigit()
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("常驻") { row in
                        Text(ByteFormat.string(row.residentBytes)).monospacedDigit()
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("Dirty") { row in
                        Text(ByteFormat.string(row.dirtyBytes)).monospacedDigit()
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn("地址范围") { row in
                        Text("\(row.start)-\(row.end)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 180, ideal: 220)
                    TableColumn("权限/共享") { row in
                        Text("\(row.protection) · \(row.sharing)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 130, ideal: 160)
                    TableColumn("详情") { row in
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("按类型 / 路径 / 地址过滤", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Spacer()
            Text("\(rows.count) 个区域")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("排序", selection: $sortField) {
                ForEach(RegionSortField.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 120)
            Button {
                ascending.toggle()
            } label: {
                Image(systemName: ascending ? "arrow.up" : "arrow.down")
            }
            .help("切换升序 / 降序")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "square.stack.3d.up.slash",
            title: "尚无内存区域数据",
            message: "加载详细分析后，这里将展示 vmmap 解析出的每个虚拟内存区域。"
        )
    }
}
