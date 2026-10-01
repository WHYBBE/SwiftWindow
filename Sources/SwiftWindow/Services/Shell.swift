import Foundation

enum Shell {
    @discardableResult
    static func run(_ executable: String,
                    _ arguments: [String],
                    timeout: TimeInterval = 20) -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return (error.localizedDescription, -1)
        }

        let readQueue = DispatchQueue(label: "SwiftWindow.Shell.read")
        var outputData = Data()
        let done = DispatchSemaphore(value: 0)

        readQueue.async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
            return ("命令执行超时（\(Int(timeout))s）", -1)
        }

        process.waitUntilExit()
        return (String(decoding: outputData, as: UTF8.self), process.terminationStatus)
    }
}
