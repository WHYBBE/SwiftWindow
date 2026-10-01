import Foundation

enum DiagnosisEngine {
    /// Builds a no-privilege attribution snapshot: who owns WindowServer's
    /// surface memory, which apps hold GPU/IOSurface clients, and whether
    /// Stage Manager is accumulating window sets.
    static func snapshot() -> AttributionSnapshot {
        let scale = WindowAttributionService.displayScale()
        let windows = WindowAttributionService.scanWindows(scale: scale)
        let owners = WindowAttributionService.attribute(windows)
        let clients = WindowAttributionService.scanSurfaceClients()
        let stageManager = StageManagerService.state()

        let windowServerWindows = windows.filter(\.isWindowServer)
        return AttributionSnapshot(
            date: Date(),
            displayScale: scale,
            owners: owners,
            windows: windows,
            surfaceClients: clients,
            stageManager: stageManager,
            totalSurfaceBytes: windows.reduce(0) { $0 + $1.estimatedBytes },
            windowServerSurfaceBytes: windowServerWindows.reduce(0) { $0 + $1.estimatedBytes },
            windowServerFullscreenCount: windowServerWindows.filter(\.isFullscreen).count
        )
    }

    static func findings(snapshot: AttributionSnapshot,
                         report: DetailedReport?,
                         samples: [SurfaceSample]) -> [DiagnosisFinding] {
        var findings: [DiagnosisFinding] = []
        let fullscreenBytes = snapshot.owners.first(where: { $0.isWindowServer })?.estimatedBytes ?? 0

        if snapshot.windowServerFullscreenCount >= 6 {
            let stageNote = snapshot.stageManager.enabled
                ? "Stage Manager 处于开启状态，共管理 \(snapshot.stageManager.windowSetCount) 个窗口集（\(snapshot.stageManager.distinctApps) 个应用）。"
                : "Stage Manager 未开启，需进一步排查全屏/录屏类应用。"
            findings.append(DiagnosisFinding(
                severity: snapshot.windowServerFullscreenCount >= 12 ? .critical : .warning,
                title: "WindowServer 自身持有 \(snapshot.windowServerFullscreenCount) 个全屏 Surface，约 \(ByteFormat.string(fullscreenBytes))",
                detail: "这些不是普通应用窗口，而是 WindowServer 为系统合成的全屏 backing store（每个约 \(ByteFormat.string(fullscreenBytes / UInt64(max(1, snapshot.windowServerFullscreenCount))))）。它们会计入活动监视器里 WindowServer 的“内存”，但不会出现在 ps 的 RSS 中。\(stageNote)",
                suspect: snapshot.stageManager.enabled ? "Stage Manager (com.apple.WindowManager)" : nil
            ))
        }

        if snapshot.stageManager.enabled, snapshot.stageManager.windowSetCount >= 10 {
            let top = snapshot.stageManager.topApps.prefix(5)
                .map { "\($0.app) (\($0.sets))" }
                .joined(separator: "、")
            findings.append(DiagnosisFinding(
                severity: snapshot.stageManager.windowSetCount >= 40 ? .warning : .notice,
                title: "Stage Manager 累积了 \(snapshot.stageManager.windowSetCount) 个窗口集",
                detail: "窗口集数量远高于同时在用的窗口数，说明历史窗口集未被释放。窗口集最多的应用：\(top)。每个窗口集都会让 WindowServer 保留一份全屏 Surface，是本次 WindowServer 内存偏高的主要原因。",
                suspect: "Stage Manager (com.apple.WindowManager)"
            ))
        }

        let clientOwners = snapshot.owners
            .filter { !$0.isWindowServer && $0.estimatedBytes > 0 }
            .prefix(6)
        if !clientOwners.isEmpty {
            let list = clientOwners
                .map { "\($0.name): \(ByteFormat.string($0.estimatedBytes))（\($0.windowCount) 窗口，含 \($0.fullscreenCount) 全屏）" }
                .joined(separator: "\n")
            findings.append(DiagnosisFinding(
                severity: .info,
                title: "应用侧 Surface 占用（估算）",
                detail: "除 WindowServer 自身外，占用合成 surface 最多的应用：\n\(list)",
                suspect: nil
            ))
        }

        if !snapshot.surfaceClients.isEmpty {
            let grouped = Dictionary(grouping: snapshot.surfaceClients, by: \.name)
            let list = grouped
                .sorted { $0.value.count > $1.value.count }
                .prefix(8)
                .map { "\($0.key): \($0.value.count) 个 GPU/IOSurface 客户端" }
                .joined(separator: "\n")
            findings.append(DiagnosisFinding(
                severity: .info,
                title: "持有 GPU / IOSurface 客户端的进程（\(snapshot.surfaceClients.count) 个）",
                detail: "拥有 IOSurface 客户端说明该进程正在向 WindowServer 提交图面。客户端数量异常偏高的应用值得关注：\n\(list)",
                suspect: nil
            ))
        }

        if snapshot.stageManager.enabled, snapshot.stageManager.windowSetCount >= 10 {
            findings.append(DiagnosisFinding(
                severity: .notice,
                title: "建议：验证并释放累积的 Surface",
                detail: "1) 关闭 Stage Manager（系统设置 → 桌面与程序坞 → Stage Manager）后观察 WindowServer 内存是否回落；\n2) 注销/重新登录或重启可释放 WindowServer 持有的历史 surface；\n3) 若关闭 Stage Manager 后仍增长，再结合“深度泄漏扫描”定位具体框架。",
                suspect: nil
            ))
        }

        if samples.count >= 3, let first = samples.first, let last = samples.last {
            let delta = Int64(last.windowServerResidentBytes) - Int64(first.windowServerResidentBytes)
            let seconds = last.date.timeIntervalSince(first.date)
            let surfaceDelta = Int64(last.windowServerSurfaceBytes) - Int64(first.windowServerSurfaceBytes)
            let windowDelta = last.windowServerFullscreenCount - first.windowServerFullscreenCount
            if delta > 8 * 1024 * 1024 || surfaceDelta > 64 * 1024 * 1024 || windowDelta > 2 {
                findings.append(DiagnosisFinding(
                    severity: .warning,
                    title: "检测到增长趋势",
                    detail: String(format: "在 %.0f 秒采样窗口内：WindowServer RSS 变化 %@，其全屏 surface 估算变化 %@，全屏 surface 数量变化 %+d。持续单向增长即代表真实泄漏。",
                                   seconds,
                                   ByteFormat.string(UInt64(Swift.max(0, delta))),
                                   ByteFormat.string(UInt64(Swift.max(0, surfaceDelta))),
                                   windowDelta),
                    suspect: snapshot.stageManager.enabled ? "Stage Manager (com.apple.WindowManager)" : nil
                ))
            }
        }

        if let report {
            let hotspotTypes = report.vmmap.aggregates
                .filter { ["IOSurface", "CG image", "CG raster data", "CGSWindow", "Images", "VM_ALLOCATE"].contains($0.type) }
                .prefix(6)
            if !hotspotTypes.isEmpty {
                let list = hotspotTypes
                    .map { "\($0.type): resident \(ByteFormat.string($0.residentBytes)) / dirty \(ByteFormat.string($0.dirtyBytes))，\($0.regionCount) 区" }
                    .joined(separator: "\n")
                findings.append(DiagnosisFinding(
                    severity: .info,
                    title: "WindowServer vmmap 中的图面类区域",
                    detail: "来自特权采集的 vmmap 区域分类，可直接看到 WindowServer 内部哪些类型在吃内存：\n\(list)",
                    suspect: nil
                ))
            }
            if report.heap.totalBytes > 0 {
                let top = report.heap.allocations.prefix(6)
                    .map { "\($0.className)（\($0.type.isEmpty ? "?" : $0.type)）: \(ByteFormat.string($0.bytes)) · \($0.count) 个 · \($0.binary)" }
                    .joined(separator: "\n")
                findings.append(DiagnosisFinding(
                    severity: .info,
                    title: "WindowServer 堆分配热点",
                    detail: "来自 heap 采集，堆内占用最高的对象类型：\n\(top)",
                    suspect: nil
                ))
            }
        }

        return findings.sorted { $0.severity > $1.severity }
    }
}
