import Foundation

enum FootprintParser {
    private static let headerRegex = try! NSRegularExpression(pattern:
        #"^(?<name>.+?)\s*\[(?<pid>\d+)\]:.*Footprint:\s*(?<size>[0-9.]+)\s*(?<unit>[KMGT]?B).*?\((?<page>\d+) bytes per page\)"#)

    private static let categoryRegex = try! NSRegularExpression(pattern:
        #"^\s*(?<d>[0-9.]+)\s*(?<du>B|KB|MB|GB)\s+(?<c>[0-9.]+)\s*(?<cu>B|KB|MB|GB)\s+(?<r>[0-9.]+)\s*(?<ru>B|KB|MB|GB)\s+(?<reg>\d+)\s+(?<cat>.+?)\s*$"#)

    static func parse(_ text: String) -> FootprintReport {
        var report = FootprintReport()
        var categories: [FootprintCategory] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.contains("Footprint:") && line.contains("bytes per page"),
               let match = match(headerRegex, line) {
                report.processName = group(match, "name", in: line)
                report.pid = Int(group(match, "pid", in: line)) ?? 0
                report.footprintBytes = SizeParser.bytes(number: group(match, "size", in: line), unit: group(match, "unit", in: line))
                report.pageSize = UInt64(group(match, "page", in: line)) ?? 0
                continue
            }
            if line.contains("phys_footprint:"), !line.contains("peak") {
                report.footprintBytes = SizeParser.parse(after("phys_footprint:", in: line))
                continue
            }
            if line.contains("phys_footprint_peak:") {
                report.peakBytes = SizeParser.parse(after("phys_footprint_peak:", in: line))
                continue
            }
            if line.contains("Category") || line.contains("Dirty") || line.contains("---") {
                continue
            }
            if let match = match(categoryRegex, line) {
                let category = group(match, "cat", in: line)
                categories.append(FootprintCategory(
                    category: category,
                    dirtyBytes: SizeParser.bytes(number: group(match, "d", in: line), unit: group(match, "du", in: line)),
                    cleanBytes: SizeParser.bytes(number: group(match, "c", in: line), unit: group(match, "cu", in: line)),
                    reclaimableBytes: SizeParser.bytes(number: group(match, "r", in: line), unit: group(match, "ru", in: line)),
                    regionCount: Int(group(match, "reg", in: line)) ?? 0
                ))
            }
        }

        if report.footprintBytes == 0, let total = categories.first(where: { $0.category == "TOTAL" }) {
            report.footprintBytes = total.dirtyBytes + total.cleanBytes
        }
        if report.peakBytes == 0 { report.peakBytes = report.footprintBytes }
        report.categories = categories.filter { $0.category != "TOTAL" }
            .sorted { $0.dirtyBytes > $1.dirtyBytes }
        return report
    }

    private static func after(_ prefix: String, in line: String) -> String {
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
