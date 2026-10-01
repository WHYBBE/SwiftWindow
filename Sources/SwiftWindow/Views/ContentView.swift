import SwiftUI

enum AnalysisSection: String, CaseIterable, Identifiable {
    case diagnosis = "归因诊断"
    case overview = "概览"
    case regions = "内存区域"
    case zones = "Malloc Zone"
    case heap = "堆分配"
    case footprint = "内存足迹"

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var engine: MonitorEngine
    @State private var section: AnalysisSection = .diagnosis

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statCards
            Divider()
            sectionPicker
            Divider()
            content
            Divider()
            footer
        }
        .alert("出错了", isPresented: Binding(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { engine.errorMessage = nil }
        } message: {
            Text(engine.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "window.on.rectangle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("WindowServer 内存分析")
                        .font(.headline)
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

            Toggle("自动刷新", isOn: Binding(
                get: { engine.autoRefresh },
                set: { engine.setAutoRefresh($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Button {
                engine.refreshBasic()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            Button {
                engine.loadDetails()
            } label: {
                if engine.isLoadingDetails {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("分析中…")
                    }
                } else {
                    Label("加载详细分析", systemImage: "lock.shield")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(engine.isLoadingDetails)
        }
        .padding(12)
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

    private var sectionPicker: some View {
        Picker("", selection: $section) {
            ForEach(AnalysisSection.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

    @ViewBuilder
    private var content: some View {
        switch section {
        case .diagnosis: DiagnosisView()
        case .overview: OverviewView()
        case .regions: RegionsView()
        case .zones: ZonesView()
        case .heap: HeapView()
        case .footprint: FootprintView()
        }
    }
}
