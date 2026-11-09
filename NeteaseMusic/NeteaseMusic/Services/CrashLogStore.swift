import Foundation
import UIKit
import Darwin

final class CrashLogStore {
    static let shared = CrashLogStore()

    private let queue = DispatchQueue(label: "com.youmi.crashlog")
    private let breadcrumbURL: URL
    private let crashURL: URL
    private var lines: [String] = []
    private let maxLines = 160
    private var installed = false

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YoumiDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        breadcrumbURL = dir.appendingPathComponent("breadcrumbs.log")
        crashURL = dir.appendingPathComponent("last-crash.log")
        if let data = try? Data(contentsOf: breadcrumbURL),
           let text = String(data: data, encoding: .utf8) {
            lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count > maxLines {
                lines = Array(lines.suffix(maxLines))
            }
        }
        youmiCrashPrepare(crashURL.path, breadcrumbURL.path)
        youmiCrashSetSnapshot(lines.joined(separator: "\n"))
    }

    func install() {
        queue.sync {
            guard !installed else { return }
            installed = true
            NSSetUncaughtExceptionHandler(youmiUncaughtException)
            signal(SIGABRT, youmiSignalHandler)
            signal(SIGSEGV, youmiSignalHandler)
            signal(SIGBUS, youmiSignalHandler)
            signal(SIGILL, youmiSignalHandler)
            signal(SIGFPE, youmiSignalHandler)
            signal(SIGTRAP, youmiSignalHandler)
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        breadcrumb(
            "launch iOS=\(UIDevice.current.systemVersion) app=\(version)(\(build)) model=\(UIDevice.current.model)"
        )
        if let last = lastCrashText(), !last.isEmpty {
            breadcrumb("previous-crash-present bytes=\(last.utf8.count)")
        }
    }

    func breadcrumb(_ message: String) {
        let line = "[\(CrashLogStore.stamp())] \(message)"
        queue.sync {
            self.lines.append(line)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
            let text = self.lines.joined(separator: "\n")
            youmiCrashSetSnapshot(text)
            youmiCrashWritePath(self.breadcrumbURL.path, text)
        }
        #if DEBUG
        print("CRASHLOG \(line)")
        #endif
    }

    func recordException(_ exception: NSException) {
        let stack = exception.callStackSymbols.prefix(40).joined(separator: "\n")
        let body = """
        === CRASH \(CrashLogStore.stamp()) ===
        name=\(exception.name.rawValue)
        reason=\(exception.reason ?? "")
        stack:
        \(stack)

        breadcrumbs:
        \(snapshotBreadcrumbs())
        """
        youmiCrashWritePath(crashURL.path, body)
    }

    func lastCrashText() -> String? {
        guard let data = try? Data(contentsOf: crashURL),
              let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    func hasDiagnostics() -> Bool {
        lastCrashText() != nil || !snapshotBreadcrumbs().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func exportText() -> String {
        var parts: [String] = []
        parts.append("=== Youmi 诊断 \(CrashLogStore.stamp()) ===")
        if let crash = lastCrashText() {
            parts.append(crash)
        } else {
            parts.append("(无上次崩溃记录，下面是运行轨迹)")
        }
        parts.append("")
        parts.append("=== breadcrumbs ===")
        let crumbs = snapshotBreadcrumbs()
        parts.append(crumbs.isEmpty ? "(空)" : crumbs)
        return parts.joined(separator: "\n")
    }

    func clear() {
        queue.sync {
            lines = []
            youmiCrashSetSnapshot("")
            try? FileManager.default.removeItem(at: breadcrumbURL)
            try? FileManager.default.removeItem(at: crashURL)
            youmiCrashPrepare(crashURL.path, breadcrumbURL.path)
        }
    }

    private func snapshotBreadcrumbs() -> String {
        queue.sync { lines.joined(separator: "\n") }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}

private let youmiSnapshotCapacity = 8192
private var youmiSnapshotBuf = UnsafeMutablePointer<CChar>.allocate(capacity: 8192)
private var youmiSigHdr = UnsafeMutablePointer<CChar>.allocate(capacity: 8)
private var youmiCrashFD: Int32 = -1
private var youmiBuffersReady = false

private func youmiCrashPrepare(_ crashPath: String, _ breadcrumbPath: String) {
    if !youmiBuffersReady {
        youmiSnapshotBuf.initialize(repeating: 0, count: youmiSnapshotCapacity)
        youmiSigHdr.initialize(repeating: 0, count: 8)
        let seed: [CChar] = [83, 73, 71, 32, 48, 48, 10, 0]
        for i in 0..<8 { youmiSigHdr[i] = seed[i] }
        youmiBuffersReady = true
    }
    if youmiCrashFD >= 0 { close(youmiCrashFD) }
    youmiCrashFD = open(crashPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    _ = breadcrumbPath
}

private func youmiCrashSetSnapshot(_ text: String) {
    let clipped = String(text.suffix(youmiSnapshotCapacity - 1))
    clipped.withCString { src in
        strncpy(youmiSnapshotBuf, src, youmiSnapshotCapacity - 1)
        youmiSnapshotBuf[youmiSnapshotCapacity - 1] = 0
    }
}

private func youmiCrashWritePath(_ path: String, _ text: String) {
    text.withCString { cstr in
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        _ = Darwin.write(fd, cstr, strlen(cstr))
        fsync(fd)
        close(fd)
    }
}

private func youmiUncaughtException(_ exception: NSException) {
    CrashLogStore.shared.recordException(exception)
}

private func youmiSignalHandler(_ sig: Int32) {
    youmiSigHdr[4] = 48 + CChar((sig / 10) % 10)
    youmiSigHdr[5] = 48 + CChar(sig % 10)
    if youmiCrashFD >= 0 {
        _ = Darwin.write(youmiCrashFD, youmiSigHdr, 7)
        _ = Darwin.write(youmiCrashFD, youmiSnapshotBuf, strlen(youmiSnapshotBuf))
        fsync(youmiCrashFD)
    }
    signal(sig, SIG_DFL)
    raise(sig)
}
