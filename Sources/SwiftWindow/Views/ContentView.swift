import SwiftUI

enum AnalysisSection: String, CaseIterable, Identifiable {
    case status = "实时状态"
    case diagnosis = "归因诊断"
    case overview = "概览"
    case regions = "内存区域"
    case zones = "Malloc Zone"
    case heap = "堆分配"
    case footprint = "内存足迹"

    var id: String { rawValue }

    /// Sections whose data only comes from the privileged 详细分析 collection.
    var requiresDetail: Bool {
        switch self {
        case .status, .diagnosis: return false
        case .overview, .regions, .zones, .heap, .footprint: return true
        }
    }

    var displayName: String {
        requiresDetail ? "\(rawValue) *" : rawValue
    }

    var systemImage: String {
        switch self {
        case .status: return "speedometer"
        case .diagnosis: return "stethoscope"
        case .overview: return "gauge"
        case .regions: return "square.stack.3d.up"
        case .zones: return "shippingbox"
        case .heap: return "square.grid.3x3"
        case .footprint: return "chart.bar.doc.horizontal"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var engine: MonitorEngine
    @State private var section: AnalysisSection = .status

    var body: some View {
        NavigationSplitView {
            List(AnalysisSection.allCases, selection: $section) { item in
                Label(item.displayName, systemImage: item.systemImage)
                    .tag(item)
                    .help(item.requiresDetail ? "需要“详细分析（需授权）”才能获取数据" : item.rawValue)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                Label("* 需要“详细分析（需授权）”", systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        } detail: {
            VStack(spacing: 0) {
                if showsHeader {
                    header
                    Divider()
                }
                content
                Divider()
                footer
            }
        }
        .navigationTitle("WindowServer 内存分析")
        .alert("出错了", isPresented: Binding(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { engine.errorMessage = nil }
        } message: {
            Text(engine.errorMessage ?? "")
        }
    }

    /// Only shown for sections that need it: live controls on 实时状态,
    /// the authorized detail collection on the vmmap-backed sections, and
    /// nothing on 归因诊断 (it has its own action bar).
    private var showsHeader: Bool {
        section != .diagnosis
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer()
            switch section {
            case .status:
                autoRefreshToggle
                refreshButton
            case .overview, .regions, .zones, .heap, .footprint:
                detailsButton
            case .diagnosis:
                EmptyView()
            }
        }
        .padding(12)
    }

    private var autoRefreshToggle: some View {
        Toggle("自动刷新", isOn: Binding(
            get: { engine.autoRefresh },
            set: { engine.setAutoRefresh($0) }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var refreshButton: some View {
        Button {
            engine.refreshBasic()
        } label: {
            Label("刷新", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
    }

    private var detailsButton: some View {
        Button {
            engine.loadDetails()
        } label: {
            if engine.isLoadingDetails {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("分析中…")
                }
            } else {
                Label(engine.report == nil ? "详细分析（需授权）" : "重新采集（需授权）", systemImage: "lock.shield")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(engine.isPrivilegedBusy)
    }

    private var statCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            StatCard(
                title: "常驻内存 RSS",
                value: engine.stats.map { ByteFormat.string($0.residentBytes) } ?? "—",
                subtitle: engine.stats.map { String(format: "%.1f%% 物理内存", $0.memPercent) },
                systemImage: "memorychip",
                tint: .blue
            )
            StatCard(
                title: "虚拟内存 VSZ",
                value: engine.stats.map { ByteFormat.string($0.virtualBytes) } ?? "—",
                subtitle: "进程虚拟地址空间",
                systemImage: "square.stack.3d.up",
                tint: .purple
            )
            StatCard(
                title: "CPU 占用",
                value: engine.stats.map { String(format: "%.1f%%", $0.cpuPercent) } ?? "—",
                subtitle: "实时采样",
                systemImage: "cpu",
                tint: .orange
            )
            StatCard(
                title: "线程数",
                value: engine.stats.map { "\($0.threadCount)" } ?? "—",
                subtitle: "ps -M 统计",
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: .green
            )
            StatCard(
                title: "运行时长",
                value: engine.stats?.elapsed ?? "—",
                subtitle: "自进程启动",
                systemImage: "clock",
                tint: .pink
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if engine.isLoadingDetails {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: engine.report == nil ? "info.circle" : "checkmark.seal")
                    .foregroundStyle(engine.report == nil ? Color.secondary : Color.green)
            }
            Text(engine.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let report = engine.report {
                Text("采集于 \(report.generatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background.secondary)
    }

    private var statusContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                processInfoCard
                statCards
            }
            .padding(16)
        }
    }

    private var processInfoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "window.on.rectangle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("WindowServer").font(.headline)
                    if let pid = engine.pid {
                        Text("PID \(pid)")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if let path = engine.stats?.path {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .status: statusContent
        case .diagnosis: DiagnosisView()
        case .overview: OverviewView()
        case .regions: RegionsView()
        case .zones: ZonesView()
        case .heap: HeapView()
        case .footprint: FootprintView()
        }
    }
}
