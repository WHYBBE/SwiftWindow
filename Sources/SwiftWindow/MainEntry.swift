import Foundation
import Darwin

/// Explicit entry point so the same binary can double as the private-API
/// surface probe subprocess (`--surface-probe`) before SwiftUI starts.
@main
enum MainEntry {
    static func main() {
        if CommandLine.arguments.contains("--surface-probe") {
            SurfaceProbe.run()
            exit(0)
        }
        SwiftWindowApp.main()
    }
}
