import Foundation

enum PrivilegedError: LocalizedError {
    case notAllowed(String)
    case cancelled
    case busy
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAllowed(let tool): return "不允许执行的命令：\(tool)"
        case .cancelled: return "已取消管理员授权。"
        case .busy: return "已有一次管理员授权正在进行，请稍候。"
        case .failed(let message): return "命令执行失败：\(message)"
        }
    }
}

enum PrivilegedRunner {
    /// A process-wide guard so only ONE administrator prompt can ever be
    /// in flight. Without this, tapping the buttons repeatedly queues several
    /// `do shell script ... with administrator privileges` calls and the
    /// password sheet appears over and over.
    private static let flightLock = NSLock()
    private static var inFlight = false

    private static let allowlist: Set<String> = [
        "/usr/bin/vmmap",
        "/usr/bin/footprint",
        "/usr/bin/heap",
        "/usr/bin/leaks",
        "/usr/bin/sample",
        "/usr/bin/top",
        "/bin/ps"
    ]

    /// Runs one or more commands as root. A single authorization prompt is shown
    /// for the whole batch.
    static func runBatch(_ commands: [[String]], timeout: TimeInterval = 180) throws -> [String] {
        guard !commands.isEmpty else { return [] }

        flightLock.lock()
        if inFlight {
            flightLock.unlock()
            Self.log("BUSY rejected")
            throw PrivilegedError.busy
        }
        inFlight = true
        flightLock.unlock()
        Self.log("begin cmds")
        defer {
            flightLock.lock()
            inFlight = false
            flightLock.unlock()
            Self.log("end")
        }

        for command in commands {
            guard let executable = command.first, allowlist.contains(executable) else {
                throw PrivilegedError.notAllowed(command.first ?? "")
            }
            for argument in command.dropFirst() where argument.contains("\n") {
                throw PrivilegedError.notAllowed("包含非法参数")
            }
        }

        let fileManager = FileManager.default
        let token = UUID().uuidString
        var scriptLines = ["#!/bin/sh"]
        var outputURLs: [URL] = []

        for (index, command) in commands.enumerated() {
            let outputURL = fileManager.temporaryDirectory
                .appendingPathComponent("swiftwindow-\(token)-\(index).txt")
            outputURLs.append(outputURL)
            let joined = command.map(singleQuote).joined(separator: " ")
            scriptLines.append("\(joined) > \(singleQuote(outputURL.path)) 2>&1")
            scriptLines.append("/bin/chmod 644 \(singleQuote(outputURL.path))")
        }

        let script = scriptLines.joined(separator: "\n") + "\n"
        let scriptURL = fileManager.temporaryDirectory
            .appendingPathComponent("swiftwindow-\(token).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        defer {
            try? fileManager.removeItem(at: scriptURL)
            for url in outputURLs { try? fileManager.removeItem(at: url) }
        }

        if geteuid() == 0 {
            let result = Shell.run("/bin/sh", [scriptURL.path], timeout: timeout)
            if result.status != 0 { throw PrivilegedError.failed(result.output) }
        } else {
            let appleScript = "do shell script \(doubleQuote(scriptURL.path)) with administrator privileges with prompt \(doubleQuote("SwiftWindow 需要管理员权限来读取 WindowServer 的内存明细（vmmap / footprint / heap）。"))"
            let result = Shell.run("/usr/bin/osascript", ["-e", appleScript], timeout: timeout)
            if result.status != 0 {
                let lower = result.output.lowercased()
                if result.output.contains("-128") || lower.contains("cancel") || lower.contains("user canceled") {
                    throw PrivilegedError.cancelled
                }
                throw PrivilegedError.failed(result.output)
            }
        }

        return outputURLs.map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }
    }

    static func log(_ message: String) {
        guard ProcessInfo.processInfo.environment["SWIFTWINDOW_DEBUG"] != nil else { return }
        let line = "\(Date()) [\(getpid())] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/swiftwindow-priv.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func singleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func doubleQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
