import Foundation
import CoreGraphics
import AppKit
import Darwin

/// Reads window surface information through the private SkyLight (`SLS*`,
/// formerly `CGS*`) window-server API.
///
/// Safety on macOS 27 (verified):
///   - `SLSMainConnectionID`        works, no crash.
///   - `SLSGetSurfaceCount`         works cross-process, no crash (used).
///   - `SLSGetSurfaceList`          intermittently crashes — not used.
///   - `SLSGetSurfaceBounds`        returns kCGErrorIllegalArgument for surfaces
///                                  owned by another process (the WindowServer
///                                  case) — no usable data.
///   - `SLSGetSurfaceResolution`    returns kCGErrorFailure and then corrupts
///                                  memory / aborts the process.
///
/// Therefore we only use `SLSMainConnectionID` + `SLSGetSurfaceCount`, which
/// returned reliably, and never touch the others. Everything still runs in a
/// short-lived child process (`--surface-probe`) so that if a future macOS
/// changes this behaviour, a crash only kills the child and the parent falls
/// back to geometry estimates.
///
/// Output format (one line per window): `<windowID>\t<surfaceCount>`
enum SurfaceProbe {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias GetSurfaceCountFn = @convention(c) (Int32, Int32, UnsafeMutablePointer<Int>?) -> Int32
    private typealias GetWindowOwnerFn = @convention(c) (Int32, Int32, UnsafeMutablePointer<Int32>?) -> Int32

    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        // RTLD_DEFAULT: search all already-loaded images (SkyLight is loaded by
        // CoreGraphics/AppKit).
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    /// Entry point for the `--surface-probe` child process.
    static func run() {
        setvbuf(stdout, nil, _IONBF, 0) // unbuffered so output survives if we abort

        // The private API needs a fully-launched window-server connection, so we
        // run a normal NSApplication and do the work in
        // `applicationDidFinishLaunching` (calling it earlier gives SIGBUS).
        // The prohibited activation policy keeps the probe from flashing a Dock
        // icon while it runs.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.run()
    }

    private final class ProbeDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            SurfaceProbe.enumerateAndPrint()
            exit(0)
        }
    }

    /// Only the safe calls are used (see the type-level comment). The private
    /// API can abort the process, which is why this runs in its own process.
    private static func enumerateAndPrint() {
        guard let mainConnection = symbol("SLSMainConnectionID", MainConnectionFn.self),
              let getSurfaceCount = symbol("SLSGetSurfaceCount", GetSurfaceCountFn.self),
              let getWindowOwner = symbol("SLSGetWindowOwner", GetWindowOwnerFn.self) else {
            FileHandle.standardError.write(Data("private surface symbols unavailable\n".utf8))
            exit(2)
        }

        let connection = mainConnection()

        guard let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        // `SLSGetSurfaceCount` + `SLSGetWindowOwner` were the only surface/window
        // calls that stayed reliable across every test. `SLSGetSurfaceList`
        // crashed intermittently and the Bounds/Resolution/FrontBuffer calls
        // either corrupt memory or reject foreign surfaces, so none of those are
        // used. Owner connection 0 means the window is server-owned (no client).
        for info in infoList {
            guard let windowID = info["kCGWindowNumber"] as? Int else { continue }
            var surfaceCount = 0
            _ = getSurfaceCount(connection, Int32(windowID), &surfaceCount)
            var owner: Int32 = -1
            _ = getWindowOwner(connection, Int32(windowID), &owner)
            print("\(windowID)\t\(surfaceCount)\t\(owner)")
        }
    }
}
