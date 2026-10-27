import Foundation

/// NetEase serves each signed audio path from a pair of CDN hosts,
/// `mN.music.126.net` and `mNc.music.126.net`. The signature lives in the
/// path, so a URL whose host cannot be reached can be retried on its twin.
enum NeteaseCDNHost {
    private static let suffix = ".music.126.net"
    static let unreachableTTL: TimeInterval = 10 * 60
    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private struct HostState {
        var failedAt: TimeInterval?
        var answeredAt: TimeInterval?
    }

    private static let lock = NSLock()
    private static var hosts: [String: HostState] = [:]

    static func alternate(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              host.hasSuffix(suffix) else { return nil }
        var label = host.dropLast(suffix.count)
        guard label.first == "m" else { return nil }
        label = label.dropFirst()
        let isTwin = label.last == "c"
        if isTwin { label = label.dropLast() }
        guard !label.isEmpty, label.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        components.host = "m\(label)\(isTwin ? "" : "c")\(suffix)"
        return components.url
    }

    static func isHostUnreachable(_ error: Error) -> Bool {
        var queue = [error as NSError]
        var visited = 0
        while !queue.isEmpty, visited < 16 {
            let error = queue.removeFirst()
            visited += 1
            let codes = error.domain == NSURLErrorDomain ? unreachableURLCodes
                : error.domain == cfNetworkDomain ? unreachableURLCodes.union(unreachableHostCodes)
                : []
            if codes.contains(error.code) { return true }
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                queue.append(underlying)
            }
            if let several = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
                queue.append(contentsOf: several)
            }
        }
        return false
    }

    private static let unreachableURLCodes: Set<Int> = [
        NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorCannotConnectToHost,
        NSURLErrorTimedOut, NSURLErrorServerCertificateUntrusted
    ]
    private static let unreachableHostCodes: Set<Int> = [1, 2]
    private static let cfNetworkDomain = kCFErrorDomainCFNetwork as String

    static func failover(from url: URL, after error: Error, now: TimeInterval = uptime) -> URL? {
        guard isHostUnreachable(error),
              let twin = alternate(for: url),
              let host = url.host?.lowercased(),
              let twinHost = twin.host else { return nil }
        lock.lock()
        hosts[host, default: HostState()].failedAt = now
        let twinFailed = isFresh(hosts[twinHost], now: now)
        lock.unlock()
        return twinFailed ? nil : twin
    }

    static func markReachable(_ url: URL, now: TimeInterval = uptime) {
        guard alternate(for: url) != nil, let host = url.host?.lowercased() else { return }
        lock.lock()
        hosts[host] = HostState(failedAt: nil, answeredAt: now)
        lock.unlock()
    }

    static func preferred(for url: URL, now: TimeInterval = uptime) -> URL {
        guard let twin = alternate(for: url),
              let host = url.host?.lowercased(),
              let twinHost = twin.host else { return url }
        lock.lock()
        let state = hosts[host]
        let twinState = hosts[twinHost]
        let useTwin: Bool
        if !isFresh(state, now: now) {
            useTwin = false
        } else if !isFresh(twinState, now: now) {
            useTwin = true
        } else {
            useTwin = (twinState?.answeredAt ?? -.infinity) > (state?.answeredAt ?? -.infinity)
        }
        lock.unlock()
        return useTwin ? twin : url
    }

    private static func isFresh(_ state: HostState?, now: TimeInterval) -> Bool {
        guard let failedAt = state?.failedAt else { return false }
        return now - failedAt < unreachableTTL
    }
}
