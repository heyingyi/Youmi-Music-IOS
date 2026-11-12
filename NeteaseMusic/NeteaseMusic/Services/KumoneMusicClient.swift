import Foundation
import UIKit
import CoreImage.CIFilterBuiltins

/// Direct NetEase weapi/eapi client, transport copied from missuo/kumone.
final class KumoneMusicClient {
    static let shared = KumoneMusicClient()

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    private let session: URLSession
    private let cookiesKey = "kumone.netease.cookies"
    private let youmiCookieKey = "netease_cookie"
    private var storedCookies: [String: String] = [:]
    private let lock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        session = URLSession(configuration: config)

        if let data = UserDefaults.standard.data(forKey: cookiesKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            storedCookies = saved
        }
        if storedCookies.isEmpty, let raw = UserDefaults.standard.string(forKey: youmiCookieKey) {
            importCookieString(raw)
        }
        if storedCookies.isEmpty,
           let legacy = UserDefaults.standard.data(forKey: "beans.netease.cookies"),
           let saved = try? JSONDecoder().decode([String: String].self, from: legacy) {
            storedCookies = saved
            persistCookiesLocked()
        }
    }

    // MARK: - Cookie

    func cookieHeaderString() -> String {
        lock.lock()
        let cookies = storedCookies
        lock.unlock()
        return cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    func hasLoginCookie() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !(storedCookies["MUSIC_U"] ?? "").isEmpty
    }

    func clearCookies() {
        lock.lock()
        storedCookies.removeAll()
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: cookiesKey)
        UserDefaults.standard.removeObject(forKey: youmiCookieKey)
        UserDefaults.standard.removeObject(forKey: "beans.netease.cookies")
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where cookie.domain.contains("163.com") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    func harvestCookieStorage() {
        let storage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        guard let cookies = storage.cookies, !cookies.isEmpty else { return }
        var new: [String: String] = [:]
        for cookie in cookies {
            let domain = cookie.domain.lowercased()
            guard domain.contains("163.com") else { continue }
            if !cookie.value.isEmpty, cookie.value != "\"\"" {
                new[cookie.name] = cookie.value
            }
        }
        if !new.isEmpty { setCookies(new) }
    }

    func importCookieString(_ cookie: String) {
        var parsed: [String: String] = [:]
        for part in cookie.replacingOccurrences(of: ";;", with: ";").split(separator: ";") {
            let item = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = item.firstIndex(of: "=") else { continue }
            let name = String(item[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(item[item.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty, name != "__kumone_session_binding" else { continue }
            parsed[name] = value
        }
        guard !parsed.isEmpty else { return }
        lock.lock()
        for (key, value) in parsed {
            storedCookies[key] = value
        }
        persistCookiesLocked()
        lock.unlock()
    }

    private func persistCookiesLocked() {
        if let data = try? JSONEncoder().encode(storedCookies) {
            UserDefaults.standard.set(data, forKey: cookiesKey)
        }
        let header = storedCookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        if !header.isEmpty {
            UserDefaults.standard.set(header, forKey: youmiCookieKey)
        }
    }

    private func cookie(named name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedCookies[name]
    }

    private func setCookies(_ new: [String: String]) {
        lock.lock()
        for (key, value) in new where !value.isEmpty && value != "\"\"" {
            storedCookies[key] = value
        }
        persistCookiesLocked()
        lock.unlock()
    }

    // MARK: - Public song URL

    struct SongPlayURL {
        let url: String
        let durationMS: Int
        let fee: Int
        let payed: Int
        let isTrial: Bool
    }

    func songURL(id: Int, level: String) async throws -> String? {
        try await songPlayURL(id: id, level: level)?.url
    }

    func songPlayURL(id: Int, level: String) async throws -> SongPlayURL? {
        let info = try await songURLInfo(ids: [id], level: level)
        return info[id]
    }

    func songURLInfo(ids: [Int], level: String) async throws -> [Int: SongPlayURL] {
        var payload: [String: Any] = [
            "ids": "[" + ids.map(String.init).joined(separator: ",") + "]",
            "level": level,
            "encodeType": "flac"
        ]
        if level == "sky" { payload["immerseType"] = "c51" }
        let json = try await request("/api/song/enhance/player/url/v1", payload: payload, crypto: "eapi")
        let data = json["data"] as? [[String: Any]] ?? []
        var result: [Int: SongPlayURL] = [:]
        for item in data {
            let id = intValue(item["id"])
            guard id != 0, let url = item["url"] as? String, !url.isEmpty else { continue }
            let durationMS = intValue(item["time"])
            let fee = intValue(item["fee"])
            let payed = intValue(item["payed"])
            let trialInfo = item["freeTrialInfo"]
            let hasTrialInfo = {
                if trialInfo == nil || trialInfo is NSNull { return false }
                if let dict = trialInfo as? [String: Any], dict.isEmpty { return false }
                return true
            }()
            let trialPrivilege = item["freeTrialPrivilege"] as? [String: Any]
            let timeTrial = item["freeTimeTrialPrivilege"] as? [String: Any]
            let privilegeTrial = (trialPrivilege?["resConsumable"] as? Bool == true)
                && (trialPrivilege?["userConsumable"] as? Bool == false)
            let timeTrialFlag = (timeTrial?["resConsumable"] as? Bool == true)
                && (timeTrial?["userConsumable"] as? Bool == false)
            let shortClip = durationMS > 0 && durationMS <= 35000
            let isTrial = hasTrialInfo || privilegeTrial || timeTrialFlag || shortClip
            result[id] = SongPlayURL(url: url, durationMS: durationMS, fee: fee, payed: payed, isTrial: isTrial)
        }
        return result
    }

    // MARK: - Proxy NeteaseCloudMusicApi paths

    func shouldHandle(url: URL) -> Bool {
        let value = url.absoluteString
        return value.hasPrefix(APIConfig.baseURL) || url.host == "youmimusicapi.preview.aliyun-zeabur.cn"
    }

    func proxy(url: URL) async throws -> (Data, URLResponse) {
        let (route, query) = parseRoute(url)
        return try await dispatch(route: route, query: query)
    }

    private func parseRoute(_ url: URL) -> (String, [String: String]) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in comps?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        var path = comps?.path ?? url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.hasSuffix("/") { path.removeLast() }
        return (path, query)
    }

    private func dispatch(route: String, query: [String: String]) async throws -> (Data, URLResponse) {
        switch route {
        case "", "/":
            return try pass(["code": 200, "message": "kumone-direct"])

        case "login/qr/key":
            let key = try await qrKey()
            return try pass(["code": 200, "data": ["code": 200, "unikey": key]])

        case "login/qr/create":
            let key = query["key"] ?? ""
            let qrurl = "https://music.163.com/login?codekey=\(key)"
            let qrimg = generateQRCodeBase64(qrurl) ?? qrurl
            return try pass(["code": 200, "data": ["qrurl": qrurl, "qrimg": qrimg]])

        case "login/qr/check":
            let key = query["key"] ?? ""
            let json = try await request("/api/login/qrcode/client/login", payload: [
                "key": key,
                "type": 1
            ], crypto: "weapi")
            var body: [String: Any] = ["code": intValue(json["code"], fallback: -1)]
            if let message = json["message"] { body["message"] = message }
            if intValue(json["code"]) == 803 {
                if let cookie = json["cookie"] as? String, !cookie.isEmpty {
                    importCookieString(cookie.replacingOccurrences(of: ";;", with: ";"))
                }
                body["cookie"] = cookieHeaderString()
                body["message"] = json["message"] ?? "授权成功"
            }
            return try pass(body)

        case "login/cellphone":
            return try await loginCellphone(query)

        case "captcha/sent":
            let json = try await request("/api/sms/captcha/sent", payload: [
                "ctcode": query["ctcode"] ?? "86",
                "cellphone": query["phone"] ?? "",
                "secrete": "music_middleuser_pclogin"
            ], crypto: "weapi")
            return try pass(json)

        case "captcha/verify":
            let json = try await request("/api/sms/captcha/verify", payload: [
                "cellphone": query["phone"] ?? "",
                "captcha": query["captcha"] ?? "",
                "ctcode": query["ctcode"] ?? "86"
            ], crypto: "weapi")
            return try pass(json)

        case "login/status", "user/account":
            CrashLogStore.shared.breadcrumb("kumone \(route) begin")
            let json = try await request("/api/w/nuser/account/get", payload: [:], crypto: "weapi")
            let profile = json["profile"] as? [String: Any]
            CrashLogStore.shared.breadcrumb("kumone \(route) code=\(intValue(json["code"])) uid=\(intValue(profile?["userId"]))")
            if route == "login/status" {
                return try pass([
                    "data": [
                        "code": json["code"] ?? 200,
                        "account": slimAccount(json["account"]),
                        "profile": slimProfile(json["profile"])
                    ]
                ])
            }
            return try pass([
                "code": json["code"] ?? 200,
                "account": slimAccount(json["account"]),
                "profile": slimProfile(json["profile"])
            ])

        case "logout":
            _ = try? await request("/api/logout", payload: [:], crypto: "weapi")
            clearCookies()
            return try pass(["code": 200])

        case "user/detail":
            let uid = intQuery(query, "uid")
            CrashLogStore.shared.breadcrumb("kumone user/detail uid=\(uid)")
            let json = try await request("/api/v1/user/detail/\(uid)", payload: [:], crypto: "weapi")
            CrashLogStore.shared.breadcrumb("kumone user/detail code=\(intValue(json["code"]))")
            return try pass(slimUserDetail(json))

        case "user/playlist":
            CrashLogStore.shared.breadcrumb("kumone user/playlist uid=\(intQuery(query, "uid"))")
            let json = try await request("/api/user/playlist", payload: [
                "uid": intQuery(query, "uid"),
                "limit": min(intQuery(query, "limit", 1000), 1000),
                "offset": intQuery(query, "offset", 0),
                "includeVideo": false
            ], crypto: "weapi", maxBytes: 240_000)
            let slim = slimPlaylists(json)
            let count = (slim["playlist"] as? [Any])?.count ?? -1
            CrashLogStore.shared.breadcrumb("kumone user/playlist code=\(intValue(slim["code"])) count=\(count) more=\(json["more"] ?? false)")
            return try pass(slim)

        case "playlist/sublist":
            CrashLogStore.shared.breadcrumb("kumone playlist/sublist")
            let json = try await request("/api/playlist/collect/list", payload: [
                "limit": min(intQuery(query, "limit", 100), 100),
                "offset": intQuery(query, "offset", 0)
            ], crypto: "weapi", maxBytes: 160_000)
            let items = slimPlaylistItems(json)
            CrashLogStore.shared.breadcrumb("kumone playlist/sublist code=\(intValue(json["code"])) count=\(items.count)")
            return try pass([
                "code": items.isEmpty ? intValue(json["code"], fallback: 200) : 200,
                "playlist": items,
                "data": items,
                "count": json["count"] ?? items.count
            ])

        case "likelist":
            CrashLogStore.shared.breadcrumb("kumone likelist uid=\(intQuery(query, "uid"))")
            let json = try await request("/api/song/like/get", payload: [
                "uid": intQuery(query, "uid")
            ], crypto: "weapi")
            let count = (json["ids"] as? [Any])?.count ?? -1
            CrashLogStore.shared.breadcrumb("kumone likelist code=\(intValue(json["code"])) count=\(count)")
            return try pass(slimLikelist(json))

        case "like":
            let id = intQuery(query, "id")
            let liked = (query["like"] ?? "true") != "false"
            let json = try await request("/api/radio/like?alg=itembased&trackId=\(id)&time=3", payload: [
                "trackId": id,
                "like": liked
            ], crypto: "weapi")
            return try pass(json)

        case "album/sublist":
            let json = try await request("/api/album/sublist", payload: [
                "limit": min(intQuery(query, "limit", 50), 50),
                "offset": intQuery(query, "offset", 0),
                "total": true
            ], crypto: "weapi")
            return try pass(slimAlbums(json))

        case "personalized":
            let json = try await request("/api/personalized/playlist", payload: [
                "limit": intQuery(query, "limit", 30),
                "total": true,
                "n": 1000
            ], crypto: "weapi")
            return try pass(json)

        case "playlist/detail":
            let json = try await request("/api/v6/playlist/detail", payload: [
                "id": intQuery(query, "id"),
                "n": 1000,
                "s": 8
            ], crypto: "weapi")
            return try pass(json)

        case "playlist/track/all":
            let json = try await request("/api/v6/playlist/detail", payload: [
                "id": intQuery(query, "id"),
                "n": 1000,
                "s": 8
            ], crypto: "weapi")
            let playlist = json["playlist"] as? [String: Any] ?? [:]
            var tracks = playlist["tracks"] as? [[String: Any]] ?? []
            let limit = intQuery(query, "limit", tracks.count)
            let offset = intQuery(query, "offset", 0)
            if offset < tracks.count {
                let end = min(tracks.count, offset + max(limit, 0))
                tracks = Array(tracks[offset..<end])
            } else {
                tracks = []
            }
            return try pass(["code": json["code"] ?? 200, "songs": tracks])

        case "banner":
            let json = try await request("/api/v2/banner/get", payload: [
                "clientType": "pc",
                "os": "pc"
            ], crypto: "weapi")
            return try pass(json)

        case "lyric":
            return try await lyric(id: intQuery(query, "id"), preferV1: false)

        case "lyric/new":
            return try await lyric(id: intQuery(query, "id"), preferV1: true)

        case "search":
            return try await search(query)

        case "search/hot/detail":
            return try await hotSearchDetail()

        case "search/suggest":
            let json = try await request("/api/search/suggest/web", payload: [
                "s": query["keywords"] ?? query["s"] ?? ""
            ], crypto: "weapi")
            return try pass(json)

        case "song/detail":
            let ids = (query["ids"] ?? "").split(separator: ",").compactMap { Int($0) }
            let c = "[" + ids.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
            let json = try await request("/api/v3/song/detail", payload: ["c": c], crypto: "weapi")
            return try pass(json)

        case "song/url":
            let id = intQuery(query, "id")
            let br = intQuery(query, "br", 320000)
            var payload: [String: Any] = [
                "ids": "[\(id)]",
                "level": levelFromBitrate(br),
                "encodeType": "flac"
            ]
            let json = try await request("/api/song/enhance/player/url/v1", payload: payload, crypto: "eapi")
            return try pass(json)

        case "check/music":
            let id = intQuery(query, "id")
            let ok = try await songURL(id: id, level: "exhigh") != nil
            return try pass(["success": ok, "message": ok ? "ok" : "unavailable"])

        case "toplist":
            let json = try await request("/api/toplist/detail", payload: [:], crypto: "weapi")
            return try pass(json)

        case "top/playlist/highquality":
            var payload: [String: Any] = [
                "cat": query["cat"] ?? "全部",
                "limit": intQuery(query, "limit", 30),
                "lasttime": 0,
                "total": true
            ]
            if let before = query["before"], let value = Int(before) {
                payload["lasttime"] = value
            }
            let json = try await request("/api/playlist/highquality/list", payload: payload, crypto: "weapi")
            return try pass(json)

        case "top/playlist":
            let json = try await request("/api/playlist/list", payload: [
                "cat": query["cat"] ?? "全部",
                "order": query["order"] ?? "hot",
                "limit": intQuery(query, "limit", 30),
                "offset": intQuery(query, "offset", 0),
                "total": true
            ], crypto: "weapi")
            return try pass(json)

        case "top/song":
            let json = try await request("/api/v1/discovery/new/songs", payload: [
                "areaId": intQuery(query, "type", 0),
                "total": true
            ], crypto: "weapi")
            return try pass(json)

        case "album/new":
            let json = try await request("/api/album/new", payload: [
                "area": query["area"] ?? "ALL",
                "limit": intQuery(query, "limit", 30),
                "offset": intQuery(query, "offset", 0),
                "total": true
            ], crypto: "weapi")
            return try pass(json)

        case "top/artists":
            let json = try await request("/api/artist/top", payload: [
                "offset": intQuery(query, "offset", 0),
                "total": true,
                "limit": intQuery(query, "limit", 50)
            ], crypto: "weapi")
            return try pass(json)

        case "personalized/newsong":
            let json = try await request("/api/personalized/newsong", payload: [
                "type": "recommend",
                "limit": intQuery(query, "limit", 10),
                "areaId": 0
            ], crypto: "weapi")
            return try pass(json)

        case "playlist/catlist":
            let json = try await request("/api/playlist/catlist", payload: [:], crypto: "weapi")
            return try pass(json)

        case "album/detail/dynamic":
            let json = try await request("/api/album/detail/dynamic", payload: [
                "id": intQuery(query, "id")
            ], crypto: "eapi")
            return try pass(json)

        case "playmode/intelligence/list":
            let songId = intQuery(query, "id")
            let json = try await request("/api/playmode/intelligence/list", payload: [
                "songId": songId,
                "type": "fromPlayOne",
                "playlistId": intQuery(query, "pid"),
                "startMusicId": intQuery(query, "sid", songId),
                "count": 1
            ], crypto: "weapi")
            return try pass(json)

        case "recommend/songs":
            let json = try await request("/api/v3/discovery/recommend/songs", payload: [:], crypto: "weapi")
            return try pass(json)

        case "comment/music":
            let id = intQuery(query, "id")
            let json = try await request("/api/v1/resource/comments/R_SO_4_\(id)", payload: [
                "rid": id,
                "limit": intQuery(query, "limit", 20),
                "offset": intQuery(query, "offset", 0),
                "beforeTime": 0
            ], crypto: "weapi")
            return try pass(json)

        case "comment/new":
            let id = intQuery(query, "id")
            let payload: [String: Any] = [
                "threadId": "R_SO_4_\(id)",
                "pageNo": intQuery(query, "pageNo", 1),
                "pageSize": intQuery(query, "pageSize", 20),
                "sortType": intQuery(query, "sortType", 3),
                "cursor": query["cursor"] ?? "0",
                "offset": 0,
                "orderType": 1
            ]
            let json = try await request("/api/v2/resource/comments", payload: payload, crypto: "eapi")
            return try pass(json)

        case "comment/hot":
            let id = intQuery(query, "id")
            let json = try await request("/api/v1/resource/hotcomments/R_SO_4_\(id)", payload: [
                "rid": id,
                "limit": intQuery(query, "limit", 20),
                "offset": intQuery(query, "offset", 0)
            ], crypto: "weapi")
            return try pass(json)

        case "comment":
            return try await sendComment(query)

        case "comment/like":
            let t = intQuery(query, "t", 1)
            let json = try await request("/api/v1/comment/\(t == 1 ? "like" : "unlike")", payload: [
                "threadId": "R_SO_4_\(intQuery(query, "id"))",
                "commentId": intQuery(query, "cid")
            ], crypto: "weapi")
            return try pass(json)

        case "comment/floor":
            let json = try await request("/api/resource/comment/floor/get", payload: [
                "parentCommentId": intQuery(query, "parentCommentId"),
                "threadId": "R_SO_4_\(intQuery(query, "id"))",
                "limit": intQuery(query, "limit", 20),
                "time": intQuery(query, "time", 0)
            ], crypto: "weapi")
            return try pass(json)

        case "artist/detail":
            let json = try await request("/api/artist/head/info/get", payload: [
                "id": intQuery(query, "id")
            ], crypto: "weapi")
            return try pass(json)

        case "artist/top/song":
            let id = intQuery(query, "id")
            var json = try await request("/api/v1/artist/\(id)", payload: [:], crypto: "weapi")
            if json["songs"] == nil {
                json["songs"] = json["hotSongs"]
            }
            return try pass(json)

        case "artist/album":
            let id = intQuery(query, "id")
            let json = try await request("/api/artist/albums/\(id)", payload: [
                "limit": intQuery(query, "limit", 30),
                "offset": intQuery(query, "offset", 0),
                "total": true
            ], crypto: "weapi")
            return try pass(json)

        case "album":
            let json = try await request("/api/v1/album/\(intQuery(query, "id"))", payload: [:], crypto: "weapi")
            return try pass(json)

        case "personal_fm":
            let json = try await request("/api/v1/radio/get", payload: [:], crypto: "weapi")
            return try pass(json)

        case "fm_trash":
            let id = intQuery(query, "id")
            let json = try await request("/api/radio/trash/add?alg=RT&songId=\(id)&time=25", payload: [
                "songId": id
            ], crypto: "weapi")
            return try pass(json)

        case "user/cloud":
            let json = try await request("/api/v1/cloud/get", payload: [
                "limit": intQuery(query, "limit", 50),
                "offset": intQuery(query, "offset", 0)
            ], crypto: "weapi")
            return try pass(json)

        case "dj/sublist":
            CrashLogStore.shared.breadcrumb("kumone dj/sublist")
            let json = try await request("/api/djradio/get/subed", payload: [
                "limit": intQuery(query, "limit", 100),
                "offset": intQuery(query, "offset", 0),
                "total": true
            ], crypto: "weapi")
            let radios = extractRadios(json)
            CrashLogStore.shared.breadcrumb("kumone dj/sublist code=\(intValue(json["code"])) count=\(radios.count)")
            return try pass([
                "code": intValue(json["code"], fallback: 200),
                "djRadios": radios.map(slimRadio)
            ])

        case "user/dj":
            CrashLogStore.shared.breadcrumb("kumone user/dj uid=\(intQuery(query, "uid"))")
            var json = try await request("/api/djradio/get/byuser", payload: [
                "userId": intQuery(query, "uid")
            ], crypto: "weapi")
            var radios = extractRadios(json)
            if radios.isEmpty {
                let alt = try await request("/api/dj/get/byuser", payload: [
                    "userId": intQuery(query, "uid"),
                    "limit": intQuery(query, "limit", 100),
                    "offset": intQuery(query, "offset", 0)
                ], crypto: "weapi")
                let altRadios = extractRadios(alt)
                if !altRadios.isEmpty {
                    json = alt
                    radios = altRadios
                }
            }
            CrashLogStore.shared.breadcrumb("kumone user/dj radios=\(radios.count)")
            return try pass([
                "code": intValue(json["code"], fallback: 200),
                "djRadios": radios.map(slimRadio)
            ])

        case "dj/program":
            CrashLogStore.shared.breadcrumb("kumone dj/program rid=\(intQuery(query, "rid"))")
            let json = try await request("/api/dj/program/byradio", payload: [
                "radioId": intQuery(query, "rid"),
                "limit": min(intQuery(query, "limit", 100), 100),
                "offset": intQuery(query, "offset", 0),
                "asc": false
            ], crypto: "weapi")
            let programs = extractPrograms(json).map(slimProgram)
            CrashLogStore.shared.breadcrumb("kumone dj/program count=\(programs.count)")
            return try pass([
                "code": intValue(json["code"], fallback: 200),
                "programs": programs
            ])

        case "dj/program/sublist":
            CrashLogStore.shared.breadcrumb("kumone program/sublist begin")
            var programs: [[String: Any]] = []
            let payload: [String: Any] = [
                "limit": 30,
                "offset": intQuery(query, "offset", 0),
                "total": true
            ]
            let attempts: [(String, String)] = [
                ("/api/djprogram/subscribed", "weapi"),
                ("/api/nuser/program/sub/list", "weapi"),
                ("/api/voice/liked/get", "weapi"),
                ("/api/program/sub/list", "eapi"),
                ("/api/program/sub/list", "weapi")
            ]
            for (path, crypto) in attempts {
                CrashLogStore.shared.breadcrumb("kumone program/sublist try \(path)")
                do {
                    let json = try await request(path, payload: payload, crypto: crypto, maxBytes: 80_000)
                    let extracted = extractPrograms(json)
                    CrashLogStore.shared.breadcrumb("kumone program/sublist \(path) code=\(intValue(json["code"])) count=\(extracted.count) keys=\(Array(json.keys).sorted().joined(separator: ","))")
                    if !extracted.isEmpty {
                        programs = Array(extracted.prefix(40).map(slimProgram))
                        break
                    }
                } catch {
                    CrashLogStore.shared.breadcrumb("kumone program/sublist miss \(path) \(error.localizedDescription)")
                }
            }
            CrashLogStore.shared.breadcrumb("kumone program/sublist done count=\(programs.count)")
            return try pass([
                "code": 200,
                "programs": programs,
                "count": programs.count
            ])

        case "dj/program/sub":
            let id = intQuery(query, "id")
            let sub = intQuery(query, "t", 1) == 1
            let action = sub ? "sub" : "unsub"
            let attempts: [(String, [String: Any])] = [
                ("/api/djprogram/\(action)", ["id": id]),
                ("/api/program/\(action)", ["id": id]),
                ("/api/djprogram/sub", ["id": id, "t": sub ? 1 : 0]),
                ("/api/program/sub", ["id": id, "t": sub ? 1 : 0]),
                ("/api/dj/program/\(action)", ["id": id]),
                ("/api/resource/like", ["threadId": "A_DJ_1_\(id)", "t": sub ? 1 : 0])
            ]
            var json: [String: Any] = ["code": 400]
            for (path, payload) in attempts {
                guard let result = try? await request(path, payload: payload, crypto: "weapi") else { continue }
                json = result
                if isSuccessCode(json["code"]) { break }
            }
            return try pass(json)

        case "dj/program/add":
            let radioId = intQuery(query, "radioId")
            let programId = intQuery(query, "programId")
            let attempts: [(String, [String: Any])] = [
                ("/api/dj/program/add", ["djId": radioId, "programId": programId]),
                ("/api/djradio/program/add", ["djId": radioId, "programId": programId]),
                ("/api/djradio/program/add", ["radioId": radioId, "programId": programId]),
                ("/api/dj/program/add", ["id": radioId, "programId": programId])
            ]
            var json: [String: Any] = ["code": 400]
            for (path, payload) in attempts {
                guard let result = try? await request(path, payload: payload, crypto: "weapi") else { continue }
                json = result
                if isSuccessCode(json["code"]) { break }
            }
            return try pass(json)

        default:
            let payload = payloadFromQuery(query)
            let json = try await request("/api/\(route)", payload: payload, crypto: "weapi")
            return try pass(json)
        }
    }

    // MARK: - Auth helpers

    private func qrKey() async throws -> String {
        let json = try await request("/api/login/qrcode/unikey", payload: ["type": 1], crypto: "weapi")
        if let key = json["unikey"] as? String, !key.isEmpty { return key }
        if let data = json["data"] as? [String: Any], let key = data["unikey"] as? String, !key.isEmpty { return key }
        throw NetEaseDirectError.unknown("获取二维码密钥失败")
    }

    private func loginCellphone(_ query: [String: String]) async throws -> (Data, URLResponse) {
        let countryCode = query["countrycode"] ?? query["ctcode"] ?? "86"
        let json: [String: Any]
        if let captcha = query["captcha"], !captcha.isEmpty {
            json = try await request("/api/w/login/cellphone", payload: [
                "type": "1",
                "https": "true",
                "phone": query["phone"] ?? "",
                "countrycode": countryCode,
                "captcha": captcha,
                "remember": "true",
                "secureCaptcha": ""
            ], crypto: "weapi")
        } else {
            let password = query["password"] ?? ""
            json = try await request("/api/login/cellphone", payload: [
                "phone": query["phone"] ?? "",
                "countrycode": countryCode,
                "rememberLogin": "true",
                "password": isMD5(password) ? password : NetEaseCrypto.md5Hex(password)
            ], crypto: "weapi")
        }
        var body = json
        body["cookie"] = cookieHeaderString()
        return try pass(body)
    }

    private func search(_ query: [String: String]) async throws -> (Data, URLResponse) {
        let json = try await request("/api/cloudsearch/pc", payload: [
            "s": query["keywords"] ?? query["s"] ?? "",
            "type": intQuery(query, "type", 1),
            "limit": intQuery(query, "limit", 30),
            "offset": intQuery(query, "offset", 0),
            "total": true
        ], crypto: "eapi")
        var result = json["result"] as? [String: Any] ?? [:]
        if let songs = result["songs"] as? [[String: Any]] {
            result["songs"] = normalizeSongs(songs)
        }
        return try pass(["code": json["code"] ?? 200, "result": result])
    }

    private func lyric(id: Int, preferV1: Bool) async throws -> (Data, URLResponse) {
        if preferV1 {
            if let json = try? await request("/api/song/lyric/v1", payload: [
                "id": id, "cp": false,
                "lv": 0, "kv": 0, "tv": 0, "rv": 0, "yv": 0, "ytv": 0, "yrv": 0
            ], crypto: "weapi") {
                let lrc = ((json["lrc"] as? [String: Any])?["lyric"] as? String) ?? ""
                let yrc = ((json["yrc"] as? [String: Any])?["lyric"] as? String) ?? ""
                if !lrc.isEmpty || !yrc.isEmpty {
                    return try pass(json)
                }
            }
        }
        let json = try await request("/api/song/lyric", payload: [
            "id": id,
            "lv": -1,
            "kv": -1,
            "tv": -1,
            "rv": -1
        ], crypto: "weapi")
        return try pass(json)
    }

    private func hotSearchDetail() async throws -> (Data, URLResponse) {
        if let json = try? await request("/api/hotsearchlist/get", payload: [:], crypto: "weapi"),
           let data = json["data"] as? [[String: Any]], !data.isEmpty {
            return try pass(["code": 200, "data": data])
        }
        let json = try await request("/api/search/hot", payload: ["type": 1111], crypto: "weapi")
        let hots = ((json["result"] as? [String: Any])?["hots"] as? [[String: Any]]) ?? []
        let data: [[String: Any]] = hots.compactMap { item in
            guard let word = item["first"] as? String, !word.isEmpty else { return nil }
            return [
                "searchWord": word,
                "score": item["second"] ?? NSNull(),
                "content": "",
                "iconType": 0
            ]
        }
        return try pass(["code": 200, "data": data])
    }

    private func sendComment(_ query: [String: String]) async throws -> (Data, URLResponse) {
        let t = intQuery(query, "t", 1)
        let id = intQuery(query, "id")
        let content = query["content"] ?? ""
        if t == 2, let commentId = query["commentId"], let cid = Int(commentId) {
            let json = try await request("/api/resource/comments/reply", payload: [
                "threadId": "R_SO_4_\(id)",
                "commentId": cid,
                "content": content
            ], crypto: "weapi")
            return try pass(json)
        }
        let json = try await request("/api/resource/comments/add", payload: [
            "threadId": "R_SO_4_\(id)",
            "content": content
        ], crypto: "weapi")
        return try pass(json)
    }

    // MARK: - kumone weapi / eapi

    private func request(_ uri: String, payload: [String: Any], crypto: String, maxBytes: Int = 180_000) async throws -> [String: Any] {
        let data: Data
        if crypto == "eapi" {
            data = try await eapi(uri, payload, maxBytes: maxBytes)
        } else {
            data = try await weapi(uri, payload, maxBytes: maxBytes)
        }
        CrashLogStore.shared.breadcrumb("kumone \(uri) bytes=\(data.count)")
        if data.count < 200 {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            CrashLogStore.shared.breadcrumb("kumone \(uri) body=\(snippet.prefix(120))")
        }
        if data.count > 12_000 {
            let scanned = scanJSONObject(data)
            CrashLogStore.shared.breadcrumb("kumone \(uri) scanned keys=\(scanned.count)")
            return scanned
        }
        let limited = data.count > 4_000 ? limitJSONDepth(data, maxDepth: 4) : data
        let parsed = autoreleasepool { () -> [String: Any]? in
            (try? JSONSerialization.jsonObject(with: limited)) as? [String: Any]
        }
        guard let json = parsed else {
            return scanJSONObject(data)
        }
        return json
    }

    private func limitJSONDepth(_ data: Data, maxDepth: Int) -> Data {
        data.withUnsafeBytes { raw -> Data in
            let buf = raw.bindMemory(to: UInt8.self)
            let n = buf.count
            var out = Data()
            out.reserveCapacity(min(n, 256_000))
            var i = 0
            var depth = 0
            var inString = false
            var escape = false
            while i < n {
                let b = buf[i]
                if inString {
                    out.append(b)
                    i += 1
                    if escape {
                        escape = false
                    } else if b == 0x5C {
                        escape = true
                    } else if b == 0x22 {
                        inString = false
                    }
                    continue
                }
                if b == 0x22 {
                    inString = true
                    out.append(b)
                    i += 1
                    continue
                }
                if b == 0x7B || b == 0x5B {
                    depth += 1
                    if depth > maxDepth {
                        if b == 0x7B {
                            out.append(contentsOf: [0x7B, 0x7D])
                        } else {
                            out.append(contentsOf: [0x5B, 0x5D])
                        }
                        skipJSONContainer(buf, count: n, index: &i)
                        depth -= 1
                        continue
                    }
                    out.append(b)
                    i += 1
                    continue
                }
                if b == 0x7D || b == 0x5D {
                    depth -= 1
                }
                out.append(b)
                i += 1
            }
            return out
        }
    }

    private func skipJSONContainer(_ buf: UnsafeBufferPointer<UInt8>, count n: Int, index i: inout Int) {
        guard i < n else { return }
        let open = buf[i]
        let close: UInt8 = open == 0x7B ? 0x7D : 0x5D
        var depth = 0
        var inString = false
        var escape = false
        while i < n {
            let b = buf[i]
            i += 1
            if inString {
                if escape {
                    escape = false
                } else if b == 0x5C {
                    escape = true
                } else if b == 0x22 {
                    inString = false
                }
                continue
            }
            if b == 0x22 {
                inString = true
                continue
            }
            if b == open {
                depth += 1
            } else if b == close {
                depth -= 1
                if depth == 0 { return }
            }
        }
    }

    private func scanJSONObject(_ data: Data) -> [String: Any] {
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return json
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return ["code": 200]
        }
        var out: [String: Any] = ["code": firstInt(in: text, key: "code") ?? 200]
        if let more = firstBool(in: text, key: "more") {
            out["more"] = more
        }
        let programs = extractShallowObjects(from: text, keys: ["programs", "djPrograms", "data", "records", "list"])
        if !programs.isEmpty {
            out["programs"] = programs
            out["data"] = programs
        }
        let playlists = extractShallowObjects(from: text, keys: ["playlist"])
        if !playlists.isEmpty {
            out["playlist"] = playlists
        }
        let radios = extractShallowObjects(from: text, keys: ["djRadios", "radios"])
        if !radios.isEmpty {
            out["djRadios"] = radios
        }
        return out
    }

    private func firstInt(in text: String, key: String) -> Int? {
        let needle = "\"\(key)\":"
        guard let range = text.range(of: needle) else { return nil }
        let rest = text[range.upperBound...]
        var digits = ""
        for ch in rest {
            if ch == "-" && digits.isEmpty { digits.append(ch); continue }
            if ch.isNumber { digits.append(ch); continue }
            break
        }
        return Int(digits)
    }

    private func firstBool(in text: String, key: String) -> Bool? {
        let needle = "\"\(key)\":"
        guard let range = text.range(of: needle) else { return nil }
        let rest = text[range.upperBound...].drop(while: { $0 == " " })
        if rest.hasPrefix("true") { return true }
        if rest.hasPrefix("false") { return false }
        return nil
    }

    private func extractShallowObjects(from text: String, keys: [String]) -> [[String: Any]] {
        for key in keys {
            let needle = "\"\(key)\":"
            guard let range = text.range(of: needle) else { continue }
            var i = range.upperBound
            while i < text.endIndex, text[i] == " " { i = text.index(after: i) }
            guard i < text.endIndex, text[i] == "[" else { continue }
            let items = parseShallowArray(text, from: i)
            if !items.isEmpty { return items }
        }
        return []
    }

    private func parseShallowArray(_ text: String, from start: String.Index) -> [[String: Any]] {
        var i = start
        guard i < text.endIndex, text[i] == "[" else { return [] }
        i = text.index(after: i)
        var items: [[String: Any]] = []
        items.reserveCapacity(32)
        while i < text.endIndex && items.count < 40 {
            while i < text.endIndex, " \n\r\t,".contains(text[i]) {
                i = text.index(after: i)
            }
            guard i < text.endIndex else { break }
            if text[i] == "]" { break }
            if text[i] != "{" { break }
            let (object, next) = parseShallowObject(text, from: i)
            i = next
            if intValue(object["id"]) != 0 || intValue(object["programId"]) != 0 {
                items.append(object)
            }
        }
        return items
    }

    private func parseShallowObject(_ text: String, from start: String.Index) -> ([String: Any], String.Index) {
        var i = start
        guard i < text.endIndex, text[i] == "{" else { return ([:], start) }
        i = text.index(after: i)
        var object: [String: Any] = [:]
        var depth = 1
        var inString = false
        var escape = false
        var key = ""
        var collectingKey = false
        var collectingString = false
        var value = ""
        var expectValue = false
        while i < text.endIndex && depth > 0 {
            let ch = text[i]
            i = text.index(after: i)
            if inString {
                if escape {
                    if collectingKey { key.append(ch) }
                    else if collectingString { value.append(ch) }
                    escape = false
                    continue
                }
                if ch == "\\" {
                    escape = true
                    continue
                }
                if ch == "\"" {
                    inString = false
                    if collectingKey {
                        collectingKey = false
                    } else if collectingString {
                        collectingString = false
                        if depth == 1, !key.isEmpty {
                            object[key] = value
                        }
                        key = ""
                        value = ""
                        expectValue = false
                    }
                    continue
                }
                if collectingKey { key.append(ch) }
                else if collectingString { value.append(ch) }
                continue
            }
            if ch == "\"" {
                inString = true
                if depth == 1 {
                    if expectValue {
                        collectingString = true
                        value = ""
                    } else {
                        collectingKey = true
                        key = ""
                    }
                }
                continue
            }
            if ch == "{" || ch == "[" {
                depth += 1
                expectValue = false
                continue
            }
            if ch == "}" || ch == "]" {
                depth -= 1
                if depth == 1, expectValue, !key.isEmpty, !value.isEmpty {
                    object[key] = parseLooseValue(value)
                    key = ""
                    value = ""
                }
                expectValue = false
                continue
            }
            if depth != 1 { continue }
            if ch == ":" {
                expectValue = true
                value = ""
                continue
            }
            if ch == "," {
                if expectValue, !key.isEmpty, !value.isEmpty {
                    object[key] = parseLooseValue(value)
                }
                key = ""
                value = ""
                expectValue = false
                continue
            }
            if expectValue, !" \n\r\t".contains(ch) {
                value.append(ch)
            }
        }
        return (object, i)
    }

    private func parseLooseValue(_ raw: String) -> Any {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" { return true }
        if trimmed == "false" { return false }
        if trimmed == "null" { return NSNull() }
        if let int = Int(trimmed) { return int }
        if let double = Double(trimmed) { return double }
        return trimmed
    }

    /// POST `https://music.163.com/weapi<path>` — path is `/api/...` internally.
    private func weapi(_ uri: String, _ payload: [String: Any], maxBytes: Int = 180_000) async throws -> Data {
        var body = payload
        let csrf = cookie(named: "__csrf") ?? ""
        body["csrf_token"] = csrf
        let json = try JSONSerialization.data(withJSONObject: jsonObject(body))
        let form = NetEaseCrypto.weapi(payload: json)

        var path = weapiPath(from: uri)
        if !csrf.isEmpty {
            path += (path.contains("?") ? "&" : "?") + "csrf_token=\(csrf)"
        }
        guard let url = URL(string: "https://music.163.com/weapi\(path)") else {
            throw NetEaseDirectError.unknown("请求地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(cookieHeader(extra: ["os": "pc", "appver": "3.1.17"]), forHTTPHeaderField: "Cookie")
        request.httpBody = encodeForm(form)
        return try await perform(request, maxBytes: maxBytes)
    }

    /// POST `https://interface.music.163.com/eapi<path>` with digest over `/api<path>`.
    private func eapi(_ uri: String, _ payload: [String: Any], cookieOverrides: [String: String] = [:], maxBytes: Int = 180_000) async throws -> Data {
        let apiPath = uri.hasPrefix("/api") ? uri : "/api" + uri
        let eapiPath = apiPath.hasPrefix("/api") ? String(apiPath.dropFirst(4)) : apiPath
        var body = payload
        var header: [String: String] = [
            "os": "pc",
            "appver": "3.1.17",
            "osver": "Version 14.0 (Build 23A344)",
            "deviceId": "kumone",
            "requestId": String(Int.random(in: 20_000_000...30_000_000)),
            "clientSign": "",
            "versioncode": "140",
            "buildver": String(Int(Date().timeIntervalSince1970)),
            "resolution": "1920x1080",
            "channel": ""
        ]
        if let musicU = cookie(named: "MUSIC_U") { header["MUSIC_U"] = musicU }
        if let csrf = cookie(named: "__csrf") { header["__csrf"] = csrf }
        body["header"] = header
        let json = try JSONSerialization.data(withJSONObject: jsonObject(body))
        let form = NetEaseCrypto.eapi(apiPath: apiPath, payload: json)

        guard let url = URL(string: "https://interface.music.163.com/eapi\(eapiPath)") else {
            throw NetEaseDirectError.unknown("请求地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(cookieHeader(extra: ["os": "pc", "appver": "3.1.17"], overrides: cookieOverrides),
                         forHTTPHeaderField: "Cookie")
        request.httpBody = encodeForm(form)
        return try await perform(request, maxBytes: maxBytes)
    }

    private func perform(_ request: URLRequest, maxBytes: Int = 180_000) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetEaseDirectError.network }
        absorbSetCookies(from: http, url: request.url!)
        harvestCookieStorage()
        guard (200..<300).contains(http.statusCode) else {
            throw NetEaseDirectError.httpStatus(http.statusCode, "")
        }
        var data = Data()
        data.reserveCapacity(min(maxBytes, 64_000))
        var truncated = false
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxBytes {
                    truncated = true
                    bytes.task.cancel()
                    break
                }
            }
        } catch {
            if !truncated { throw error }
        }
        if truncated {
            CrashLogStore.shared.breadcrumb("kumone truncated \(maxBytes)")
        }
        return data
    }

    private func absorbSetCookies(from response: HTTPURLResponse, url: URL) {
        var new: [String: String] = [:]
        var headerLines: [String] = []
        for (rawKey, rawValue) in response.allHeaderFields {
            let key = "\(rawKey)"
            guard key.caseInsensitiveCompare("Set-Cookie") == .orderedSame else { continue }
            if let values = rawValue as? [String] {
                headerLines.append(contentsOf: values)
            } else {
                headerLines.append("\(rawValue)")
            }
        }
        if headerLines.isEmpty, let single = response.value(forHTTPHeaderField: "Set-Cookie") {
            headerLines = [single]
        }
        for line in headerLines.flatMap({ splitSetCookieValues($0) }) {
            let pair = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? line
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !value.isEmpty, value != "\"\"" {
                new[name] = value
            }
        }
        if new.isEmpty {
            var fields: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                fields["\(key)"] = "\(value)"
            }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            where !cookie.value.isEmpty && cookie.value != "\"\"" {
                new[cookie.name] = cookie.value
            }
        }
        if !new.isEmpty { setCookies(new) }
    }

    private func splitSetCookieValues(_ header: String) -> [String] {
        var result: [String] = []
        var current = ""
        for part in header.split(separator: ",", omittingEmptySubsequences: false) {
            let piece = String(part)
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if current.isEmpty {
                current = piece
                continue
            }
            let name = trimmed.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            let isNewCookie = !name.isEmpty && name.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).contains($0)
            }
            if isNewCookie && trimmed.contains("=") {
                result.append(current)
                current = trimmed
            } else {
                current += "," + piece
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func cookieHeader(extra: [String: String], overrides: [String: String] = [:]) -> String {
        lock.lock()
        var all = storedCookies
        lock.unlock()
        for (k, v) in extra where all[k] == nil { all[k] = v }
        for (k, v) in overrides { all[k] = v }
        return all.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private func weapiPath(from uri: String) -> String {
        if uri.hasPrefix("/api") { return String(uri.dropFirst(4)) }
        return uri.hasPrefix("/") ? uri : "/" + uri
    }

    private func encodeForm(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    // MARK: - Helpers

    private func pass(_ json: [String: Any]) throws -> (Data, URLResponse) {
        let sanitized = jsonObject(json)
        guard JSONSerialization.isValidJSONObject(sanitized) else {
            throw NetEaseDirectError.decoding("invalid json")
        }
        let data = try JSONSerialization.data(withJSONObject: sanitized, options: [])
        let response = HTTPURLResponse(
            url: URL(string: "https://music.163.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    private func jsonObject(_ value: Any, depth: Int = 0) -> Any {
        if depth > 6 { return NSNull() }
        if value is NSNull { return value }
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (key, item) in dict {
                out[key] = jsonObject(item, depth: depth + 1)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { jsonObject($0, depth: depth + 1) }
        }
        if JSONSerialization.isValidJSONObject([value]) {
            return value
        }
        return NSNull()
    }

    private func asDict(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private func slimPlaylistItem(_ item: [String: Any]) -> [String: Any] {
        [
            "id": item["id"] ?? 0,
            "name": item["name"] ?? "",
            "coverImgUrl": item["coverImgUrl"] ?? item["picUrl"] ?? "",
            "trackCount": item["trackCount"] ?? 0,
            "playCount": item["playCount"] ?? 0,
            "userId": item["userId"] ?? 0,
            "createTime": item["createTime"] ?? 0,
            "specialType": item["specialType"] ?? 0,
            "description": item["description"] ?? ""
        ]
    }

    private func slimPlaylistItems(_ json: [String: Any]) -> [[String: Any]] {
        let raw = dictList(json["playlist"])
        if !raw.isEmpty { return raw.map(slimPlaylistItem) }
        return dictList(json["data"]).map(slimPlaylistItem)
    }

    private func slimPlaylists(_ json: [String: Any]) -> [String: Any] {
        var out: [String: Any] = ["code": json["code"] ?? 200]
        out["playlist"] = slimPlaylistItems(json)
        return out
    }

    private func slimAlbums(_ json: [String: Any]) -> [String: Any] {
        var out: [String: Any] = ["code": json["code"] ?? 200]
        out["count"] = json["count"] ?? 0
        out["data"] = dictList(json["data"]).map { item -> [String: Any] in
            let artist = asDict(item["artist"])
            return [
                "id": item["id"] ?? 0,
                "name": item["name"] ?? "",
                "picUrl": item["picUrl"] ?? "",
                "size": item["size"] ?? 0,
                "publishTime": item["publishTime"] ?? 0,
                "artist": [
                    "id": artist["id"] ?? 0,
                    "name": artist["name"] ?? ""
                ]
            ]
        }
        return out
    }

    private func slimAccount(_ value: Any?) -> Any {
        guard let account = value as? [String: Any] else { return NSNull() }
        return [
            "id": account["id"] ?? 0,
            "userName": account["userName"] ?? "",
            "type": account["type"] ?? 0,
            "status": account["status"] ?? 0,
            "createTime": account["createTime"] ?? 0,
            "vipType": account["vipType"] ?? 0
        ]
    }

    private func slimProfile(_ value: Any?) -> Any {
        guard let profile = value as? [String: Any] else { return NSNull() }
        return [
            "userId": profile["userId"] ?? 0,
            "nickname": profile["nickname"] ?? "",
            "avatarUrl": profile["avatarUrl"] ?? "",
            "backgroundUrl": profile["backgroundUrl"] ?? "",
            "signature": profile["signature"] ?? "",
            "gender": profile["gender"] ?? 0,
            "birthday": profile["birthday"] ?? 0,
            "city": profile["city"] ?? 0,
            "province": profile["province"] ?? 0,
            "followed": profile["followed"] ?? false,
            "followeds": profile["followeds"] ?? 0,
            "follows": profile["follows"] ?? 0,
            "playlistCount": profile["playlistCount"] ?? 0,
            "eventCount": profile["eventCount"] ?? 0,
            "vipType": profile["vipType"] ?? 0,
            "level": profile["level"] ?? 0,
            "listenSongs": profile["listenSongs"] ?? 0
        ]
    }

    private func slimLikelist(_ json: [String: Any]) -> [String: Any] {
        var out: [String: Any] = ["code": json["code"] ?? 200]
        out["ids"] = json["ids"] ?? []
        return out
    }

    private func slimUserDetail(_ json: [String: Any]) -> [String: Any] {
        var profile = asDict(slimProfile(json["profile"]))
        if profile["level"] as? Int == 0 { profile["level"] = json["level"] ?? 0 }
        if profile["listenSongs"] as? Int == 0 { profile["listenSongs"] = json["listenSongs"] ?? 0 }
        return [
            "code": json["code"] ?? 200,
            "level": json["level"] ?? 0,
            "listenSongs": json["listenSongs"] ?? 0,
            "profile": profile
        ]
    }

    private func slimRadio(_ item: [String: Any]) -> [String: Any] {
        let dj = item["dj"] as? [String: Any]
        return [
            "id": item["id"] ?? item["radioId"] ?? 0,
            "name": item["name"] ?? "",
            "picUrl": item["picUrl"] ?? item["coverUrl"] ?? "",
            "programCount": item["programCount"] ?? 0,
            "playCount": item["playCount"] ?? 0,
            "desc": item["desc"] ?? "",
            "userId": item["userId"] ?? item["createUserId"] ?? 0,
            "dj": [
                "nickname": dj?["nickname"] ?? "",
                "userId": dj?["userId"] ?? dj?["id"] ?? 0
            ]
        ]
    }

    private func slimProgram(_ item: [String: Any]) -> [String: Any] {
        let radio = item["radio"] as? [String: Any]
        let song = (item["mainSong"] as? [String: Any]) ?? (item["song"] as? [String: Any])
        return [
            "id": item["id"] ?? item["programId"] ?? 0,
            "name": item["name"] ?? "",
            "coverUrl": item["coverUrl"] ?? item["picUrl"] ?? item["coverImgUrl"] ?? "",
            "duration": item["duration"] ?? 0,
            "listenerCount": item["listenerCount"] ?? 0,
            "createTime": item["createTime"] ?? 0,
            "description": item["description"] ?? "",
            "mainSong": [
                "id": song?["id"] ?? 0,
                "name": song?["name"] ?? "",
                "duration": song?["duration"] ?? song?["dt"] ?? 0
            ],
            "radio": [
                "id": radio?["id"] ?? 0,
                "name": radio?["name"] ?? "",
                "picUrl": radio?["picUrl"] ?? ""
            ]
        ]
    }

    private func intQuery(_ query: [String: String], _ key: String, _ fallback: Int = 0) -> Int {
        if let value = query[key], let parsed = Int(value) { return parsed }
        return fallback
    }

    private func intValue(_ value: Any?, fallback: Int = 0) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let int = Int(string) { return int }
        return fallback
    }

    private func payloadFromQuery(_ query: [String: String]) -> [String: Any] {
        var payload: [String: Any] = [:]
        for (key, value) in query where key != "timestamp" {
            if let int = Int(value) {
                payload[key] = int
            } else if value == "true" {
                payload[key] = true
            } else if value == "false" {
                payload[key] = false
            } else {
                payload[key] = value
            }
        }
        return payload
    }

    private func asStringKeyedDict(_ value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        guard let dict = value as? NSDictionary else { return nil }
        var out: [String: Any] = [:]
        dict.forEach { key, val in
            if let k = key as? String { out[k] = val }
        }
        return out
    }

    private func dictList(_ value: Any?) -> [[String: Any]] {
        guard let value, !(value is NSNull) else { return [] }
        if let items = value as? [[String: Any]] { return items }
        if let items = value as? [Any] {
            return items.compactMap(asStringKeyedDict)
        }
        if let array = value as? NSArray {
            var out: [[String: Any]] = []
            out.reserveCapacity(array.count)
            for i in 0..<array.count {
                if let dict = asStringKeyedDict(array[i]) {
                    out.append(dict)
                }
            }
            return out
        }
        return []
    }

    private func extractList(_ json: [String: Any], keys: [String]) -> [[String: Any]] {
        for key in keys {
            let items = dictList(json[key])
            if !items.isEmpty { return items }
        }
        return []
    }

    private func unwrapProgramItem(_ item: [String: Any]) -> [String: Any] {
        var merged = item
        if let resource = item["resource"] as? [String: Any] {
            if let nested = resource["program"] as? [String: Any] {
                merged = nested
            } else {
                merged = resource
            }
            if merged["radio"] == nil { merged["radio"] = resource["radio"] ?? item["radio"] }
        }
        if let program = (merged["program"] as? [String: Any]) ?? (item["program"] as? [String: Any]) {
            var inner = program
            if inner["radio"] == nil { inner["radio"] = merged["radio"] ?? item["radio"] }
            merged = inner
        }
        if intValue(merged["id"]) == 0 {
            let fallback = [merged["programId"], item["programId"], item["id"], merged["serialNum"]]
                .map { intValue($0) }
                .first { $0 != 0 } ?? 0
            if fallback != 0 { merged["id"] = fallback }
        }
        if merged["coverUrl"] == nil {
            merged["coverUrl"] = item["coverUrl"]
                ?? item["picUrl"]
                ?? merged["picUrl"]
                ?? merged["blurCoverUrl"]
                ?? (merged["radio"] as? [String: Any])?["picUrl"]
                ?? (item["radio"] as? [String: Any])?["picUrl"]
        }
        return merged
    }

    private func extractPrograms(_ json: [String: Any]) -> [[String: Any]] {
        extractList(json, keys: ["programs", "djPrograms", "data", "records", "list"])
            .map(unwrapProgramItem)
            .filter { intValue($0["id"]) != 0 || intValue($0["programId"]) != 0 }
    }

    private func isSuccessCode(_ value: Any?) -> Bool {
        let code = intValue(value)
        return code == 200 || code == 201 || code == 301
    }

    private func extractRadios(_ json: [String: Any]) -> [[String: Any]] {
        extractList(json, keys: ["djRadios", "data", "records", "radios", "djRadio"])
            .filter { intValue($0["id"]) != 0 || intValue($0["radioId"]) != 0 }
    }

    private func unwrapProgramList(_ json: [String: Any]) -> [String: Any] {
        var result = json
        result["programs"] = extractPrograms(json)
        return result
    }

    private func normalizeSongs(_ songs: [[String: Any]]) -> [[String: Any]] {
        songs.map { song in
            var item = song
            if item["artists"] == nil { item["artists"] = item["ar"] }
            if item["album"] == nil { item["album"] = item["al"] }
            if item["duration"] == nil { item["duration"] = item["dt"] }
            return item
        }
    }

    private func levelFromBitrate(_ br: Int) -> String {
        if br >= 999000 { return "lossless" }
        if br >= 320000 { return "exhigh" }
        return "standard"
    }

    private func isMD5(_ value: String) -> Bool {
        value.count == 32 && value.allSatisfy { $0.isHexDigit }
    }

    private func generateQRCodeBase64(_ string: String) -> String? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        guard let png = image.pngData() else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }
}

enum NetEaseDirectError: LocalizedError {
    case network
    case httpStatus(Int, String)
    case decoding(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network:
            return "网络连接失败，请检查网络"
        case .httpStatus(let code, let snippet):
            return snippet.isEmpty ? "服务器响应异常（\(code)）" : "服务器响应异常（\(code)）\(snippet)"
        case .decoding(let snippet):
            return snippet.isEmpty ? "数据解析失败" : "数据解析失败：\(snippet)"
        case .unknown(let message):
            return message
        }
    }
}
