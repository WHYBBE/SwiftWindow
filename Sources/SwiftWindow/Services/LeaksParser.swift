import Foundation

struct LeakEntry: Sendable, Identifiable {
    var id = UUID()
    var bytes: UInt64
    var description: String
}

struct LeaksReport: Sendable {
    var totalLeaks: Int = 0
    var totalBytes: UInt64 = 0
    var entries: [LeakEntry] = []
    var rawSummary: [String] = []
}

enum LeaksParser {
    private static let summaryRegex = try! NSRegularExpression(pattern:
        #"Process\s+\d+:\s+(?<count>[\d,]+)\s+leaks?\s+for\s+(?<bytes>[\d,]+)\s+total leaked bytes"#)
    private static let headerRegex = try! NSRegularExpression(pattern:
        #"STACK OF \d+ INSTANCES? OF '(?<desc>.*?)':"#)
    private static let bytesRegex = try! NSRegularExpression(pattern: #"(?<bytes>[\d,]+) bytes"#)

    static func parse(_ text: String) -> LeaksReport {
        var report = LeaksReport()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for line in lines {
            if let match = match(summaryRegex, line) {
                report.totalLeaks = Int(group(match, "count", in: line).replacingOccurrences(of: ",", with: "")) ?? 0
                report.totalBytes = UInt64(group(match, "bytes", in: line).replacingOccurrences(of: ",", with: "")) ?? 0
                report.rawSummary.append(line.trimmingCharacters(in: .whitespaces))
                continue
            }
            if let match = match(headerRegex, line) {
                let description = group(match, "desc", in: line)
                report.entries.append(LeakEntry(bytes: 0, description: description))
                continue
            }
            if line.contains("leaked bytes") {
                report.rawSummary.append(line.trimmingCharacters(in: .whitespaces))
            }
        }

        // Attach the "N bytes" that follows each stack header.
        var currentIndex = -1
        for line in lines {
            if line.contains("STACK OF") { currentIndex += 1; continue }
            guard currentIndex >= 0, currentIndex < report.entries.count else { continue }
            if report.entries[currentIndex].bytes == 0, line.contains(" bytes") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("NULL") || trimmed.count > 40 { continue }
                if let match = match(bytesRegex, trimmed) {
                    report.entries[currentIndex].bytes = UInt64(group(match, "bytes", in: trimmed).replacingOccurrences(of: ",", with: "")) ?? 0
                }
            }
        }

        report.entries.sort { $0.bytes > $1.bytes }
        return report
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
