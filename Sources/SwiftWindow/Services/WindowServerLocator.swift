import Foundation

enum WindowServerLocator {
    static func locatePID() -> Int? {
        let result = Shell.run("/bin/ps", ["-Ao", "pid=,comm="])
        for raw in result.output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let spaceIndex = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let pidPart = line[..<spaceIndex].trimmingCharacters(in: .whitespaces)
            let comm = line[spaceIndex...].trimmingCharacters(in: .whitespaces)
            if comm.contains("WindowServer"), let pid = Int(pidPart) {
                return pid
            }
        }
        return nil
    }

    static func stat(pid: Int) -> BasicProcessStats? {
        let result = Shell.run("/bin/ps", [
            "-o", "pid=,rss=,vsz=,pcpu=,pmem=,etime=,comm=",
            "-p", String(pid)
        ])
        guard let raw = result.output.split(separator: "\n").first, !raw.isEmpty else { return nil }
        let line = raw.trimmingCharacters(in: .whitespaces)
        let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard columns.count >= 6 else { return nil }

        return BasicProcessStats(
            pid: Int(columns[0]) ?? pid,
            path: columns.dropFirst(6).joined(separator: " "),
            residentBytes: (UInt64(columns[1]) ?? 0) * 1024,
            virtualBytes: (UInt64(columns[2]) ?? 0) * 1024,
            cpuPercent: Double(columns[3]) ?? 0,
            memPercent: Double(columns[4]) ?? 0,
            threadCount: threadCount(pid: pid),
            elapsed: columns[5],
            sampledAt: Date()
        )
    }

    static func threadCount(pid: Int) -> Int {
        let result = Shell.run("/bin/ps", ["-M", String(pid)])
        let lines = result.output.split(separator: "\n").count
        return max(0, lines - 1)
    }

    static func locateAndStat() -> BasicProcessStats? {
        guard let pid = locatePID() else { return nil }
        return stat(pid: pid)
    }
}
