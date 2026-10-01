import SwiftUI
import Charts

struct DiagnosisView: View {
    @EnvironmentObject private var engine: MonitorEngine
    @State private var mergeByApp = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                actionBar
                reconciliationCard
                findingsSection
                if let snapshot = engine.attribution {
                    stageManagerCard(snapshot)
                    trendsSection
                    appMemorySection(snapshot)
                    attributionSection(snapshot)
                    clientsSection(snapshot)
                    timelineSection
                } else {
                    EmptyStateView(
                        systemImage: "stethoscope",
                        title: "正在归因",
                        message: "正在扫描 WindowServer 窗口与 GPU 客户端…"
                    )
                    .frame(height: 200)
                }
                leaksSection
            }
            .padding(16)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                engine.refreshAttribution(force: true)
            } label: {
                Label("重新归因扫描", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                engine.runLeakScan()
            } label: {
                if engine.isLeakScanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("leaks 扫描中…")
                    }
                } else {
                    Label("深度泄漏扫描 (leaks)", systemImage: "ant")
                }
            }
            .disabled(engine.isPrivilegedBusy)
            Spacer()
            if let snapshot = engine.attribution {
                Text("扫描于 \(snapshot.date.formatted(date: .omitted, time: .standard)) · 缩放 \(String(format: "%.0fx", snapshot.displayScale))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var reconciliationCard: some View {
        let rss = engine.stats?.residentBytes ?? 0
        let surfaces = engine.attribution?.windowServerSurfaceBytes ?? 0
        let footprint = engine.estimatedFootprintBytes
        let maxValue = Double(max(footprint, 1))
        return VStack(alignment: .leading, spacing: 10) {
            Text("内存口径对照").font(.headline)
            VStack(spacing: 8) {
                compositionRow(label: "ps RSS（CPU 侧常驻）", value: rss, max: maxValue, tint: .blue)
                compositionRow(label: "WindowServer 全屏 Surface（GPU/IOSurface）", value: surfaces, max: maxValue, tint: .red)
                Divider()
                compositionRow(label: "≈ 活动监视器口径（物理足迹）", value: footprint, max: maxValue, tint: .purple)
            }
            Text("ps 只统计 CPU 侧常驻内存，活动监视器统计的是物理足迹，额外包含 WindowServer 代表窗口持有的 GPU/IOSurface 图面，因此两者天然存在数量级差距。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    private func compositionRow(label: String, value: UInt64, max: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(ByteFormat.string(value)).font(.callout.monospacedDigit())
            }
            RatioBar(fraction: Double(value) / max, tint: tint)
        }
    }

    private var trendsSection: some View {
        let trends = engine.ownerTrends
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("泄漏 / 增长追踪").font(.headline)
                Spacer()
                Text(engine.surfaceSamples.count >= 2 ? "基于 \(engine.surfaceSamples.count) 个采样点" : "采样不足")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if engine.surfaceSamples.count < 2 {
                Text("开启“自动刷新”，让应用持续采样各进程的窗口数与 surface 占用，即可自动排出增长最快的进程。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if trends.isEmpty {
                Text("采样窗口内没有进程的窗口数或 surface 占用明显增长。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Table(trends) {
                    TableColumn("进程") { trend in
                        Text(trend.name).font(.callout).lineLimit(1)
                    }
                    .width(min: 120, ideal: 180)
                    TableColumn("Surface 增长") { trend in
                        Text((trend.surfaceGrowthBytes >= 0 ? "+" : "-") + ByteFormat.string(UInt64(abs(trend.surfaceGrowthBytes))))
                            .monospacedDigit()
                            .foregroundStyle(trend.surfaceGrowthBytes > 0 ? .red : .secondary)
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn("窗口增长") { trend in
                        Text((trend.windowGrowth >= 0 ? "+" : "") + "\(trend.windowGrowth)")
                            .monospacedDigit()
                            .foregroundStyle(trend.windowGrowth > 0 ? .orange : .secondary)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("当前窗口") { trend in Text("\(trend.currentWindows)").monospacedDigit() }
                        .width(min: 70, ideal: 90)
                    TableColumn("当前占用") { trend in Text(ByteFormat.string(trend.currentBytes)).monospacedDigit() }
                        .width(min: 90, ideal: 110)
                }
                .frame(height: min(240, CGFloat(trends.count) * 28 + 28))
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("归因结论")
                .font(.headline)
            if engine.findings.isEmpty {
                Text("暂无结论，点击“重新归因扫描”。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(engine.findings) { finding in
                    FindingCard(finding: finding)
                }
            }
        }
    }

    private func stageManagerCard(_ snapshot: AttributionSnapshot) -> some View {
        let stage = snapshot.stageManager
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stage Manager 状态").font(.headline)
                Spacer()
                Text(stage.enabled ? "已开启" : "已关闭")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background((stage.enabled ? Color.orange : Color.green).opacity(0.18), in: Capsule())
                    .foregroundStyle(stage.enabled ? .orange : .green)
            }
            HStack(spacing: 10) {
                StatCard(title: "窗口集", value: "\(stage.windowSetCount)", subtitle: "Stage Manager 管理", systemImage: "square.on.square", tint: .orange)
                StatCard(title: "应用条目", value: "\(stage.appEntryCount)", subtitle: "\(stage.distinctApps) 个不同应用", systemImage: "app.dashed", tint: .pink)
                StatCard(title: "管理时长", value: formatAge(stage.ageSeconds), subtitle: "Management Mode \(stage.managementMode)", systemImage: "clock.arrow.circlepath", tint: .purple)
                StatCard(title: "WS 全屏 Surface", value: "\(snapshot.windowServerFullscreenCount)", subtitle: ByteFormat.string(snapshot.windowServerSurfaceBytes), systemImage: "rectangle.inset.filled", tint: .red)
            }
            if !stage.topApps.isEmpty {
                Text("窗口集最多的应用：" + stage.topApps.map { "\($0.app)（\($0.sets)）" }.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    private func appMemorySection(_ snapshot: AttributionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("应用内存排行（自身 RSS + 其窗口 Surface）").font(.headline)
                Spacer()
                Toggle("合并同一应用", isOn: $mergeByApp)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text(mergeByApp ? "\(snapshot.applications.count) 个应用 · \(snapshot.appMemory.count) 个进程"
                                : "\(snapshot.appMemory.count) 个进程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if mergeByApp {
                Table(Array(snapshot.applications.prefix(40))) {
                    TableColumn("应用") { app in
                        HStack(spacing: 6) {
                            if app.surfaceBytes > 0 {
                                Image(systemName: "rectangle.inset.filled")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            Text(app.name).font(.callout).lineLimit(1)
                        }
                    }
                    .width(min: 140, ideal: 200)
                    TableColumn("进程数") { app in Text("\(app.processCount)").monospacedDigit() }
                        .width(min: 60, ideal: 70)
                    TableColumn("自身 RSS") { app in Text(ByteFormat.string(app.residentBytes)).monospacedDigit() }
                        .width(min: 90, ideal: 110)
                    TableColumn("窗口 Surface") { app in
                        Text(ByteFormat.string(app.surfaceBytes))
                            .monospacedDigit()
                            .foregroundStyle(app.surfaceBytes > 0 ? .orange : .secondary)
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn("窗口数") { app in Text("\(app.windowCount)").monospacedDigit() }
                        .width(min: 60, ideal: 80)
                    TableColumn("合计") { app in
                        Text(ByteFormat.string(app.totalBytes))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .width(min: 90, ideal: 110)
                }
                .frame(height: min(420, CGFloat(min(snapshot.applications.count, 40)) * 28 + 28))
            } else {
                Table(Array(snapshot.appMemory.prefix(40))) {
                    TableColumn("进程") { row in
                        HStack(spacing: 6) {
                            if row.surfaceBytes > 0 {
                                Image(systemName: "rectangle.inset.filled")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(row.name).font(.callout).lineLimit(1)
                                if row.groupName != row.name {
                                    Text(row.groupName).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                        }
                    }
                    .width(min: 160, ideal: 220)
                    TableColumn("自身 RSS") { row in Text(ByteFormat.string(row.residentBytes)).monospacedDigit() }
                        .width(min: 90, ideal: 110)
                    TableColumn("窗口 Surface") { row in
                        Text(ByteFormat.string(row.surfaceBytes))
                            .monospacedDigit()
                            .foregroundStyle(row.surfaceBytes > 0 ? .orange : .secondary)
                    }
                    .width(min: 100, ideal: 120)
                    TableColumn("窗口数") { row in Text("\(row.windowCount)").monospacedDigit() }
                        .width(min: 60, ideal: 80)
                    TableColumn("合计") { row in
                        Text(ByteFormat.string(row.totalBytes))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .width(min: 90, ideal: 110)
                }
                .frame(height: min(420, CGFloat(min(snapshot.appMemory.count, 40)) * 28 + 28))
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    private func attributionSection(_ snapshot: AttributionSnapshot) -> some View {
        let maxBytes = snapshot.owners.map(\.estimatedBytes).max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Surface 内存归因（估算）").font(.headline)
                Spacer()
                Text("合计 \(ByteFormat.string(snapshot.totalSurfaceBytes)) · \(snapshot.windows.count) 个窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(snapshot.owners.prefix(15)) { owner in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if owner.isWindowServer {
                                Image(systemName: "gearshape.2.fill").foregroundStyle(.red)
                            }
                            Text(owner.name).font(.callout).fontWeight(owner.isWindowServer ? .semibold : .regular)
                            Text("PID \(owner.pid)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            Spacer()
                            Text("\(owner.windowCount) 窗口 · \(owner.fullscreenCount) 全屏")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(ByteFormat.string(owner.estimatedBytes))
                                .font(.callout.monospacedDigit())
                                .frame(width: 80, alignment: .trailing)
                        }
                        RatioBar(fraction: Double(owner.estimatedBytes) / Double(max(maxBytes, 1)),
                                 tint: owner.isWindowServer ? .red : .blue)
                    }
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    private func clientsSection(_ snapshot: AttributionSnapshot) -> some View {
        let grouped = Dictionary(grouping: snapshot.surfaceClients, by: \.name)
            .map { (name: $0.key, items: $0.value) }
            .sorted { $0.items.count > $1.items.count }
        return VStack(alignment: .leading, spacing: 8) {
            Text("GPU / IOSurface 客户端（\(snapshot.surfaceClients.count) 个）").font(.headline)
            if grouped.isEmpty {
                Text("未检测到。").font(.callout).foregroundStyle(.secondary)
            } else {
                FlowGrid(items: grouped.prefix(24).map { item in
                    "\(item.name) · \(item.items.count)"
                })
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WindowServer 全屏 Surface 趋势").font(.headline)
            if engine.surfaceSamples.count < 2 {
                Text("开启“自动刷新”以积累趋势数据。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(engine.surfaceSamples) { sample in
                        LineMark(
                            x: .value("时间", sample.date),
                            y: .value("Surface 字节", Double(sample.windowServerSurfaceBytes))
                        )
                        .foregroundStyle(by: .value("指标", "全屏 Surface 估算"))
                        LineMark(
                            x: .value("时间", sample.date),
                            y: .value("Surface 字节", Double(sample.windowServerResidentBytes))
                        )
                        .foregroundStyle(by: .value("指标", "WindowServer RSS"))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let raw = value.as(Double.self) { Text(ByteFormat.string(UInt64(raw))) }
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

    @ViewBuilder
    private var leaksSection: some View {
        if let leaks = engine.leaks {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("leaks 深度扫描").font(.headline)
                    Spacer()
                    Text("\(leaks.totalLeaks) 处 · \(ByteFormat.string(leaks.totalBytes))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if leaks.entries.isEmpty {
                    ForEach(leaks.rawSummary, id: \.self) { line in
                        Text(line).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                } else {
                    Table(leaks.entries) {
                        TableColumn("字节") { entry in Text(ByteFormat.string(entry.bytes)).monospacedDigit() }
                            .width(min: 80, ideal: 100)
                        TableColumn("泄漏对象 / 调用栈摘要") { entry in
                            Text(entry.description).font(.caption).lineLimit(2)
                        }
                    }
                    .frame(height: 240)
                }
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
        }
    }

    private func formatAge(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let hours = Int(seconds) / 3600
        if hours >= 24 { return "\(hours / 24) 天 \(hours % 24) 小时" }
        if hours >= 1 { return "\(hours) 小时" }
        return "\(Int(seconds) / 60) 分钟"
    }
}

private struct FindingCard: View {
    let finding: DiagnosisFinding

    private var tint: Color {
        switch finding.severity {
        case .critical: return .red
        case .warning: return .orange
        case .notice: return .yellow
        case .info: return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(finding.severity.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.18), in: Capsule())
                        .foregroundStyle(tint)
                    Text(finding.title).font(.callout.bold())
                }
                Text(finding.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let suspect = finding.suspect {
                    Label(suspect, systemImage: "target")
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35), lineWidth: 0.8))
    }
}

private struct FlowGrid: View {
    let items: [String]
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
