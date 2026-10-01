import Foundation

enum HeapParser {
    private static let zonesRegex = try! NSRegularExpression(pattern: #"^Process\s+\d+:\s+(?<zones>\d+)\s+zones?\s*$"#)
    private static let totalRegex = try! NSRegularExpression(pattern: #"^All zones:\s+(?<nodes>[\d,]+)\s+nodes\s+\((?<bytes>[\d,]+)\s+bytes\)\s*$"#)
    private static let rowRegex = try! NSRegularExpression(pattern:
        #"^\s*(?<count>[\d,]+)\s+(?<bytes>[\d,]+)\s+(?<avg>[0-9.]+)\s+(?<rest>.+?)\s*$"#)

    static func parse(_ text: String) -> HeapReport {
        var report = HeapReport()
        var allocations: [HeapAllocation] = []
        var inTable = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if let match = match(zonesRegex, line) {
                report.zoneCount = Int(group(match, "zones", in: line).replacingOccurrences(of: ",", with: "")) ?? 0
                continue
            }
            if let match = match(totalRegex, line) {
                report.totalNodes = Int(group(match, "nodes", in: line).replacingOccurrences(of: ",", with: "")) ?? 0
                report.totalBytes = UInt64(group(match, "bytes", in: line).replacingOccurrences(of: ",", with: "")) ?? 0
                continue
            }
            if line.contains("COUNT") && line.contains("CLASS_NAME") {
                inTable = true
                continue
            }
            if inTable && line.contains("====") { continue }
            guard inTable else { continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if line.contains("Type names") || line.hasPrefix("Found:") { continue }

            if let match = match(rowRegex, line), let allocation = parseRow(match, line) {
                allocations.append(allocation)
            }
        }

        if report.totalBytes == 0 {
            report.totalBytes = allocations.reduce(0) { $0 + $1.bytes }
        }
        if report.totalNodes == 0 {
            report.totalNodes = allocations.reduce(0) { $0 + $1.count }
        }
        report.allocations = allocations.sorted { $0.bytes > $1.bytes }
        return report
    }

    private static func parseRow(_ match: NSTextCheckingResult, _ line: String) -> HeapAllocation? {
        let countText = group(match, "count", in: line).replacingOccurrences(of: ",", with: "")
        let bytesText = group(match, "bytes", in: line).replacingOccurrences(of: ",", with: "")
        let rest = group(match, "rest", in: line)
        guard let count = Int(countText), let bytes = UInt64(bytesText) else { return nil }

        let tokens = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let knownTypes: Set<String> = ["C", "ObjC", "CF", "Swift", "C++", "ObjC++", "CG", "OS_dispatch"]
        var className = rest
        var type = ""
        var binary = ""

        if tokens.count >= 3, knownTypes.contains(tokens[tokens.count - 2]) {
            type = tokens[tokens.count - 2]
            binary = tokens[tokens.count - 1]
            className = tokens.dropLast(2).joined(separator: " ")
        } else if tokens.count >= 2, looksLikeBinary(tokens[tokens.count - 1]) {
            binary = tokens[tokens.count - 1]
            className = tokens.dropLast(1).joined(separator: " ")
        }

        return HeapAllocation(className: className, type: type, binary: binary, count: count, bytes: bytes)
    }

    private static func looksLikeBinary(_ token: String) -> Bool {
        token.contains(".") || token.contains("/")
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
