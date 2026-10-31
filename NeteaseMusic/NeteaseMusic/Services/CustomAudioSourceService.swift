import Foundation
import JavaScriptCore

struct CustomAudioResolveResult {
    let url: String
    let sourceName: String
}

/// Resolves a play URL from a user-provided HTTP template or lx/GitHub JS plugin.
enum CustomAudioSourceService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let jsQueue = DispatchQueue(label: "youmi.customSource.js")
    private static var cachedScriptURL: String?
    private static var cachedScript: String?
    private static var cachedScriptName: String?

    static func resolve(id: Int, quality: String, trackName: String = "", artistName: String = "") async -> CustomAudioResolveResult? {
        let config = MusicSourceConfig.shared
        guard config.enableCustomSource else { return nil }
        let template = config.customSourceTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty, id > 0 else { return nil }

        if isJavaScriptSource(template) {
            return await resolveJavaScript(
                source: template,
                id: id,
                quality: quality,
                trackName: trackName,
                artistName: artistName
            )
        }
        if let url = await resolveHTTPTemplate(template: template, id: id, quality: quality) {
            return CustomAudioResolveResult(url: url, sourceName: displayName(from: template, fallback: "自定义"))
        }
        return nil
    }

    // MARK: - HTTP template

    private static func resolveHTTPTemplate(template: String, id: Int, quality: String) async -> String? {
        let br: String
        switch quality {
        case "standard": br = "128"
        case "exhigh": br = "320"
        default: br = "999"
        }

        var urlString = template
        let replacements: [String: String] = [
            "{id}": String(id),
            "{songId}": String(id),
            "{songid}": String(id),
            "{quality}": quality,
            "{br}": br,
            "{level}": quality,
            "{source}": "netease"
        ]
        for (key, value) in replacements {
            urlString = urlString.replacingOccurrences(of: key, with: value)
        }
        guard let url = URL(string: urlString) else { return nil }
        return await fetchPlayURL(from: url)
    }

    private static func fetchPlayURL(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("YoumiMusic/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            let path = MusicSourceConfig.shared.customSourceJSONPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidates = [path, "url", "data.url", "data.0.url", "data.music"].filter { !$0.isEmpty }
            for candidate in candidates {
                if let value = value(at: candidate, in: object) as? String, looksLikePlayURL(value) {
                    return value
                }
            }
            if let extracted = firstHTTPURL(in: object) {
                return extracted
            }
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           looksLikePlayURL(text) {
            return text
        }
        return nil
    }

    // MARK: - JavaScript / lx plugin

    private static func isJavaScriptSource(_ template: String) -> Bool {
        let lower = template.lowercased()
        return lower.contains(".js") || lower.contains("/blob/") || lower.contains("gist.github")
    }

    private static func resolveJavaScript(
        source: String,
        id: Int,
        quality: String,
        trackName: String,
        artistName: String
    ) async -> CustomAudioResolveResult? {
        guard let script = await loadScript(from: source) else { return nil }
        let name = cachedScriptName ?? displayName(from: source, fallback: "自定义")
        if let url = await runLXPlugin(
            script: script,
            id: id,
            quality: quality,
            trackName: trackName,
            artistName: artistName
        ) {
            return CustomAudioResolveResult(url: url, sourceName: name)
        }
        if let url = await fallbackURLsFromScript(script, id: id, quality: quality) {
            return CustomAudioResolveResult(url: url, sourceName: name)
        }
        return nil
    }

    private static func loadScript(from source: String) async -> String? {
        let urlString = normalizeScriptURL(source)
        if cachedScriptURL == urlString, let cachedScript {
            return cachedScript
        }
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("YoumiMusic/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8),
                  text.contains("globalThis") || text.contains("function") || text.contains("http") else {
                return nil
            }
            cachedScriptURL = urlString
            cachedScript = text
            cachedScriptName = parseScriptName(text) ?? displayName(from: source, fallback: "自定义")
            return text
        } catch {
            return nil
        }
    }

    private static func normalizeScriptURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = trimmed as NSString
        let regex = try? NSRegularExpression(pattern: #"^https://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$"#)
        if let match = regex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges == 5 {
            let user = ns.substring(with: match.range(at: 1))
            let repo = ns.substring(with: match.range(at: 2))
            let branch = ns.substring(with: match.range(at: 3))
            let path = ns.substring(with: match.range(at: 4))
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ns.substring(with: match.range(at: 4))
            return "https://raw.githubusercontent.com/\(user)/\(repo)/\(branch)/\(path)"
        }
        return trimmed.replacingOccurrences(of: "https://github.com/", with: "https://raw.githubusercontent.com/")
            .replacingOccurrences(of: "/blob/", with: "/")
    }

    private static func parseScriptName(_ script: String) -> String? {
        let patterns = [#"@name\s+([^\n\r*]+)"#, #"^\s*\*\s*@name\s+([^\n\r*]+)"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
               let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
               let range = Range(match.range(at: 1), in: script) {
                let name = script[range].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    private static func runLXPlugin(
        script: String,
        id: Int,
        quality: String,
        trackName: String,
        artistName: String
    ) async -> String? {
        await withCheckedContinuation { continuation in
            jsQueue.async {
                var resumed = false
                func finish(_ value: String?) {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: value)
                }

                guard let context = JSContext() else {
                    finish(nil)
                    return
                }
                context.exceptionHandler = { _, _ in }

                let nativeRequest: @convention(block) (String, JSValue?, JSValue?) -> Void = { urlString, options, callback in
                    guard let url = URL(string: urlString) else {
                        callback?.call(withArguments: ["invalid url", NSNull()])
                        return
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.timeoutInterval = 6
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    if let options, options.isObject,
                       let headers = options.forProperty("headers"), headers.isObject,
                       let keys = headers.toDictionary()?.keys {
                        for key in keys {
                            let name = String(describing: key)
                            if let value = headers.forProperty(name).toString() {
                                request.setValue(value, forHTTPHeaderField: name)
                            }
                        }
                    }
                    session.dataTask(with: request) { data, _, error in
                        jsQueue.async {
                            if let error {
                                callback?.call(withArguments: [error.localizedDescription, NSNull()])
                                return
                            }
                            let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                            callback?.call(withArguments: [NSNull(), ["body": body, "statusCode": 200]])
                        }
                    }.resume()
                }
                context.setObject(nativeRequest, forKeyedSubscript: "__youmiNativeRequest" as NSString)

                let onResolved: @convention(block) (String) -> Void = { url in
                    finish(looksLikePlayURL(url) ? url : nil)
                }
                let onFailed: @convention(block) (String) -> Void = { _ in
                    finish(nil)
                }
                context.setObject(onResolved, forKeyedSubscript: "__youmiResolved" as NSString)
                context.setObject(onFailed, forKeyedSubscript: "__youmiFailed" as NSString)

                context.evaluateScript(Self.lxRuntimePrelude)
                context.evaluateScript(script)
                let lxQuality = lxQuality(from: quality)
                let escapedName = trackName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                let escapedArtist = artistName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                context.evaluateScript("""
                (function() {
                  var handler = globalThis.__lxOnRequest;
                  if (!handler) { __youmiFailed('no handler'); return; }
                  Promise.resolve(handler({
                    action: 'musicUrl',
                    source: 'wy',
                    info: {
                      type: '\(lxQuality)',
                      musicInfo: {
                        id: '\(id)',
                        songmid: '\(id)',
                        songId: '\(id)',
                        hash: '\(id)',
                        name: '\(escapedName)',
                        singer: '\(escapedArtist)'
                      }
                    }
                  })).then(function(url) {
                    __youmiResolved(typeof url === 'string' ? url : '');
                  }).catch(function(err) {
                    __youmiFailed(String(err));
                  });
                })();
                """)

                jsQueue.asyncAfter(deadline: .now() + 10) {
                    finish(nil)
                }
            }
        }
    }

    private static let lxRuntimePrelude = """
    if (typeof console === 'undefined') { var console = { log: function(){}, error: function(){}, warn: function(){} }; }
    if (typeof Promise !== 'undefined' && !Promise.any) {
      Promise.any = function(promises) {
        return new Promise(function(resolve, reject) {
          var list = Array.from(promises || []);
          if (!list.length) { reject(new Error('All promises were rejected')); return; }
          var errors = [];
          var rejected = 0;
          list.forEach(function(p, i) {
            Promise.resolve(p).then(resolve, function(err) {
              errors[i] = err;
              rejected += 1;
              if (rejected === list.length) reject(new Error('All promises were rejected'));
            });
          });
        });
      };
    }
    globalThis.__lxOnRequest = null;
    globalThis.lx = {
      EVENT_NAMES: { request: 'request', inited: 'inited', updateAlert: 'updateAlert' },
      request: function(url, options, cb) { __youmiNativeRequest(String(url), options || {}, cb); },
      on: function(name, handler) { if (name === 'request' || name === globalThis.lx.EVENT_NAMES.request) { globalThis.__lxOnRequest = handler; } },
      send: function() {}
    };
    """

    private static func lxQuality(from quality: String) -> String {
        switch quality {
        case "standard": return "128k"
        case "exhigh": return "320k"
        case "lossless": return "flac"
        default: return "flac24bit"
        }
    }

    private static func fallbackURLsFromScript(_ script: String, id: Int, quality: String) async -> String? {
        let level: String
        switch quality {
        case "standard": level = "standard"
        case "exhigh": level = "exhigh"
        default: level = "lossless"
        }
        let br: String
        switch quality {
        case "standard": br = "128"
        case "exhigh": br = "320"
        default: br = "999"
        }
        var candidates: [String] = []
        let patterns = [
            #"https?://[^\s"'`]+163[^\s"'`]*"#,
            #"https?://[^\s"'`]+netease[^\s"'`]*"#,
            #"https?://[^\s"'`]+/wy[^\s"'`]*"#,
            #"https?://[^\s"'`]+chksz[^\s"'`]*"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: script, range: NSRange(script.startIndex..., in: script))
            for match in matches {
                guard let range = Range(match.range, in: script) else { continue }
                var url = String(script[range])
                    .replacingOccurrences(of: "${id}", with: String(id))
                    .replacingOccurrences(of: "{id}", with: String(id))
                    .replacingOccurrences(of: "${lv}", with: level)
                    .replacingOccurrences(of: "{level}", with: level)
                    .replacingOccurrences(of: "${br}", with: br)
                    .replacingOccurrences(of: "{br}", with: br)
                if url.contains("id=") || !url.contains("{") {
                    if !url.contains("id=") {
                        url += url.contains("?") ? "&id=\(id)" : "?id=\(id)"
                    }
                    if looksLikeAPIEndpoint(url) {
                        candidates.append(url)
                    }
                }
            }
        }
        let extra = [
            "https://api.chksz.top/api/163_music?id=\(id)&level=\(level)",
            "https://oiapi.net/api/Music_163?id=\(id)",
            "https://music-api.gdstudio.xyz/api.php?types=url&source=netease&id=\(id)&br=\(br)"
        ]
        if script.contains("chksz") || script.contains("oiapi") || script.contains("gdstudio") {
            candidates.append(contentsOf: extra)
        }
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            guard let url = URL(string: candidate) else { continue }
            if let playURL = await fetchPlayURL(from: url) {
                return playURL
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func displayName(from template: String, fallback: String) -> String {
        if let name = cachedScriptName, !name.isEmpty { return name }
        if let url = URL(string: template) {
            let last = url.lastPathComponent.replacingOccurrences(of: ".js", with: "")
            if !last.isEmpty, last != "/" { return last }
            if let host = url.host { return host }
        }
        return fallback
    }

    private static func looksLikePlayURL(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("http://") || text.hasPrefix("https://")
    }

    private static func looksLikeAPIEndpoint(_ value: String) -> Bool {
        looksLikePlayURL(value) && !value.contains("t.me")
    }

    private static func value(at path: String, in root: Any) -> Any? {
        var current: Any? = root
        for raw in path.split(separator: ".") {
            let key = String(raw)
            if let index = Int(key), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dict = current as? [String: Any] {
                current = dict[key]
            } else {
                return nil
            }
        }
        return current
    }

    private static func firstHTTPURL(in object: Any) -> String? {
        if let text = object as? String, looksLikePlayURL(text) {
            return text
        }
        if let dict = object as? [String: Any] {
            for key in ["url", "music", "src", "path"] {
                if let text = dict[key] as? String, looksLikePlayURL(text) {
                    return text
                }
            }
            for value in dict.values {
                if let found = firstHTTPURL(in: value) { return found }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let found = firstHTTPURL(in: value) { return found }
            }
        }
        return nil
    }
}
