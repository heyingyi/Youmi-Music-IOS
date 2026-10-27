import Foundation

/// Resolves a play URL from a user-provided HTTP template.
/// Placeholders: `{id}` `{songId}` `{quality}` `{br}` `{source}`.
enum CustomAudioSourceService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func resolve(id: Int, quality: String) async -> String? {
        let config = MusicSourceConfig.shared
        guard config.enableCustomSource else { return nil }
        let template = config.customSourceTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty, id > 0 else { return nil }

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
            "{source}": "netease"
        ]
        for (key, value) in replacements {
            urlString = urlString.replacingOccurrences(of: key, with: value)
        }
        guard let url = URL(string: urlString) else { return nil }

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
            let path = config.customSourceJSONPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidates = [path, "url", "data.url", "data.0.url"].filter { !$0.isEmpty }
            for candidate in candidates {
                if let value = value(at: candidate, in: object) as? String, !value.isEmpty {
                    return value
                }
            }
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           text.hasPrefix("http") {
            return text
        }
        return nil
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
}
