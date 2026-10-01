import Foundation

enum VMMapParser {
    private static let regionRegex = try! NSRegularExpression(pattern:
        #"^\s*(?<type>.+?)\s+(?<start>[0-9a-fA-F]+)-(?<end>[0-9a-fA-F]+)\s+\[\s*(?<vs>[0-9.]+)\s*(?<vu>[KMGTP]?)\s+(?<rs>[0-9.]+)\s*(?<ru>[KMGTP]?)\s+(?<ds>[0-9.]+)\s*(?<du>[KMGTP]?)\s+(?<ss>[0-9.]+)\s*(?<su>[KMGTP]?)\]\s+(?<prot>\S+)\s+(?<share>\S+)(?:\s+(?<detail>.*?))?\s*$"#)

    private static let processRegex = try! NSRegularExpression(pattern:
        #"^Process:\s+(?<name>.+?)\s+\[(?<pid>\d+)\]\s*$"#)

    private static let zoneRegex = try! NSRegularExpression(pattern:
        #"^\s*(?<name>\S+)\s+(?<vs>[0-9.]+)\s*(?<vu>[KMGTP]?)\s+(?<rs>[0-9.]+)\s*(?<ru>[KMGTP]?)\s+(?<ds>[0-9.]+)\s*(?<du>[KMGTP]?)\s+(?<ss>[0-9.]+)\s*(?<su>[KMGTP]?)\s+(?<ac>\d+)\s+(?<ba>[0-9.]+)\s*(?<bu>[KMGTP]?)\s+(?<fr>[0-9.]+)\s*(?<fu>[KMGTP]?)\s+(?<fp>\d+)%\s+(?<rc>\d+)\s*$"#)

    private enum ZoneState { case idle, header, rows, done }

    static func parse(_ text: String, pid fallbackPid: Int) -> VMMapReport {
        var report = VMMapReport(pid: fallbackPid)
        var regions: [MemoryRegion] = []
        var zones: [MallocZone] = []
        var zoneState: ZoneState = .idle

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("Process:"), let match = match(processRegex, line) {
                report.processName = group(match, "name", in: line)
                report.pid = Int(group(match, "pid", in: line)) ?? fallbackPid
                continue
            }
            if line.hasPrefix("Code Type:") {
                report.codeType = value(after: "Code Type:", in: line)
                continue
            }
            if line.hasPrefix("OS Version:") {
                report.osVersion = value(after: "OS Version:", in: line)
                continue
            }
            if line.hasPrefix("VM page size:") {
                let number = value(after: "VM page size:", in: line)
                    .components(separatedBy: " ").first ?? ""
                report.pageSize = UInt64(number) ?? 0
                continue
            }
            if line.contains("Physical footprint:") {
                let raw = value(after: "Physical footprint:", in: line)
                report.physicalFootprint = SizeParser.parse(raw.components(separatedBy: "(").first ?? raw)
                continue
            }
            if line.contains("Physical footprint (peak):") {
                let raw = value(after: "Physical footprint (peak):", in: line)
                report.physicalFootprintPeak = SizeParser.parse(raw.components(separatedBy: "(").first ?? raw)
                continue
            }

            if line.hasPrefix("MALLOC ZONE") {
                zoneState = .header
                continue
            }
            switch zoneState {
            case .header:
                if line.contains("====") { zoneState = .rows }
                continue
            case .rows:
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if line.contains("====") || trimmed.hasPrefix("TOTAL") {
                    zoneState = .done
                    continue
                }
                if let zone = parseZone(line) { zones.append(zone) }
                continue
            case .idle, .done:
                break
            }

            if line.contains("[") && line.contains("]") && line.contains("-"),
               let match = match(regionRegex, line) {
                let region = MemoryRegion(
                    type: group(match, "type", in: line),
                    start: group(match, "start", in: line),
                    end: group(match, "end", in: line),
                    virtualBytes: SizeParser.bytes(number: group(match, "vs", in: line), unit: group(match, "vu", in: line)),
                    residentBytes: SizeParser.bytes(number: group(match, "rs", in: line), unit: group(match, "ru", in: line)),
                    dirtyBytes: SizeParser.bytes(number: group(match, "ds", in: line), unit: group(match, "du", in: line)),
                    swappedBytes: SizeParser.bytes(number: group(match, "ss", in: line), unit: group(match, "su", in: line)),
                    protection: group(match, "prot", in: line),
                    sharing: group(match, "share", in: line),
                    detail: group(match, "detail", in: line)
                )
                regions.append(region)
            }
        }

        report.regions = regions
        report.virtualSize = regions.reduce(0) { $0 + $1.virtualBytes }
        report.aggregates = aggregate(regions)
        report.zones = zones.sorted { $0.residentBytes > $1.residentBytes }
        return report
    }

    private static func aggregate(_ regions: [MemoryRegion]) -> [RegionAggregate] {
        var buckets: [String: RegionAggregate] = [:]
        for region in regions {
            var bucket = buckets[region.type] ?? RegionAggregate(
                type: region.type,
                virtualBytes: 0,
                residentBytes: 0,
                dirtyBytes: 0,
                regionCount: 0
            )
            bucket.virtualBytes += region.virtualBytes
            bucket.residentBytes += region.residentBytes
            bucket.dirtyBytes += region.dirtyBytes
            bucket.regionCount += 1
            buckets[region.type] = bucket
        }
        return buckets.values.sorted { $0.dirtyBytes > $1.dirtyBytes }
    }

    private static func parseZone(_ line: String) -> MallocZone? {
        guard let match = match(zoneRegex, line) else { return nil }
        return MallocZone(
            name: group(match, "name", in: line),
            virtualBytes: SizeParser.bytes(number: group(match, "vs", in: line), unit: group(match, "vu", in: line)),
            residentBytes: SizeParser.bytes(number: group(match, "rs", in: line), unit: group(match, "ru", in: line)),
            dirtyBytes: SizeParser.bytes(number: group(match, "ds", in: line), unit: group(match, "du", in: line)),
            allocatedBytes: SizeParser.bytes(number: group(match, "ba", in: line), unit: group(match, "bu", in: line)),
            allocationCount: Int(group(match, "ac", in: line)) ?? 0,
            fragBytes: SizeParser.bytes(number: group(match, "fr", in: line), unit: group(match, "fu", in: line)),
            fragPercent: Double(group(match, "fp", in: line)) ?? 0,
            regionCount: Int(group(match, "rc", in: line)) ?? 0
        )
    }

    private static func value(after prefix: String, in line: String) -> String {
        guard let range = line.range(of: prefix) else { return "" }
        return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    private static func match(_ regex: NSRegularExpression, _ line: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
    }

    private static func group(_ match: NSTextCheckingResult, _ name: String, in line: String) -> String {
        let index = match.range(withName: name)
        guard index.location != NSNotFound, let range = Range(index, in: line) else { return "" }
        return line[range].trimmingCharacters(in: .whitespaces)
    }
}
