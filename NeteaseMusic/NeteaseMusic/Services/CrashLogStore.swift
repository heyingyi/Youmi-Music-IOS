import Foundation
import UIKit
import Darwin

/// 崩溃诊断：面包屑写磁盘，下次启动可复制。信号处理器只写预分配缓冲。
final class CrashLogStore {
    static let shared = CrashLogStore()

    private let queue = DispatchQueue(label: "com.youmi.crashlog")
    private let breadcrumbURL: URL
    private let crashURL: URL
    private var lines: [String] = []
    private var snapshot = ""
    private let maxLines = 120
    private var installed = false

    private init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CrashLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        breadcrumbURL = dir.appendingPathComponent("breadcrumbs.log")
        crashURL = dir.appendingPathComponent("last-crash.log")
        if let data = try? Data(contentsOf: breadcrumbURL),
           let text = String(data: data, encoding: .utf8) {
            lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count > maxLines {
                lines = Array(lines.suffix(maxLines))
            }
            snapshot = lines.joined(separator: "\n")
        }
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
            breadcrumb("previous-crash-present bytes=\(last.count)")
        }
    }

    func breadcrumb(_ message: String) {
        let stamp = CrashLogStore.stamp()
        let line = "[\(stamp)] \(message)"
        queue.async {
            self.lines.append(line)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
            self.snapshot = self.lines.joined(separator: "\n")
            try? self.snapshot.write(to: self.breadcrumbURL, atomically: true, encoding: .utf8)
        }
        #if DEBUG
        print("CRASHLOG \(line)")
        #endif
    }

    func recordException(_ exception: NSException) {
        let stack = exception.callStackSymbols.joined(separator: "\n")
        let body = """
        === CRASH \(CrashLogStore.stamp()) ===
        name=\(exception.name.rawValue)
        reason=\(exception.reason ?? "")
        userInfo=\(exception.userInfo ?? [:])
        stack:
        \(stack)

        breadcrumbs:
        \(snapshotBreadcrumbs())
        """
        writeCrash(body)
    }

    func recordSignal(_ sig: Int32) {
        let name: String
        switch sig {
        case SIGABRT: name = "SIGABRT"
        case SIGSEGV: name = "SIGSEGV"
        case SIGBUS: name = "SIGBUS"
        case SIGILL: name = "SIGILL"
        case SIGFPE: name = "SIGFPE"
        case SIGTRAP: name = "SIGTRAP"
        default: name = "SIGNAL(\(sig))"
        }
        let body = """
        === CRASH \(CrashLogStore.stamp()) ===
        signal=\(name) (\(sig))
        breadcrumbs:
        \(snapshot)
        """
        writeCrash(body)
    }

    func lastCrashText() -> String? {
        guard let data = try? Data(contentsOf: crashURL),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    func exportText() -> String {
        var parts: [String] = []
        parts.append("=== Youmi 诊断 \(CrashLogStore.stamp()) ===")
        if let crash = lastCrashText() {
            parts.append(crash)
        } else {
            parts.append("(无上次崩溃记录)")
        }
        parts.append("")
        parts.append("=== breadcrumbs ===")
        parts.append(snapshotBreadcrumbs())
        return parts.joined(separator: "\n")
    }

    func clear() {
        queue.sync {
            lines = []
            snapshot = ""
            try? FileManager.default.removeItem(at: breadcrumbURL)
            try? FileManager.default.removeItem(at: crashURL)
        }
    }

    private func snapshotBreadcrumbs() -> String {
        queue.sync { snapshot.isEmpty ? lines.joined(separator: "\n") : snapshot }
    }

    private func writeCrash(_ text: String) {
        text.withCString { cstr in
            let fd = open(crashURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            guard fd >= 0 else { return }
            let len = strlen(cstr)
            _ = Darwin.write(fd, cstr, len)
            close(fd)
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}

private func youmiUncaughtException(_ exception: NSException) {
    CrashLogStore.shared.recordException(exception)
}

private func youmiSignalHandler(_ sig: Int32) {
    CrashLogStore.shared.recordSignal(sig)
    signal(sig, SIG_DFL)
    raise(sig)
}
