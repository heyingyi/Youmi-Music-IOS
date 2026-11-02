import Foundation

private enum JSONFlex {
    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Int64.self, forKey: key) { return Int(v) }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return nil
    }

    static func int64<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int64? {
        if let v = try? c.decodeIfPresent(Int64.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return Int64(v) }
        if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int64(v) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int64(s) { return v }
        return nil
    }

    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let v = try? c.decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return String(v) }
        return nil
    }

    static func bool<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool? {
        if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            if s == "true" || s == "1" { return true }
            if s == "false" || s == "0" { return false }
        }
        return nil
    }

    static func array<T: Decodable, K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [T]? {
        guard var unkeyed = try? c.nestedUnkeyedContainer(forKey: key) else { return nil }
        var items: [T] = []
        while !unkeyed.isAtEnd {
            if let item = try? unkeyed.decode(T.self) {
                items.append(item)
            } else {
                _ = try? unkeyed.decode(JSONSkip.self)
            }
        }
        return items
    }
}

private struct JSONSkip: Decodable {
    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd {
                _ = try? unkeyed.decode(JSONSkip.self)
            }
            return
        }
        if let _ = try? decoder.container(keyedBy: JSONSkipKey.self) {
            return
        }
        _ = try? decoder.singleValueContainer()
    }
}

private struct JSONSkipKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

// MARK: - 登录响应
struct LoginResponse: Codable {
    let code: Int
    let cookie: String?
    let token: String?
    let account: Account?
    let profile: UserProfile?
    let message: String?
}

// MARK: - 账户信息
struct Account: Codable {
    let id: Int
    let userName: String?
    let type: Int?
    let status: Int?
    let createTime: Int64?
    let vipType: Int?

    enum CodingKeys: String, CodingKey {
        case id, userName, type, status, createTime, vipType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.int(c, .id) ?? 0
        userName = JSONFlex.string(c, .userName)
        type = JSONFlex.int(c, .type)
        status = JSONFlex.int(c, .status)
        createTime = JSONFlex.int64(c, .createTime)
        vipType = JSONFlex.int(c, .vipType)
    }
}

// MARK: - 用户资料
struct UserProfile: Codable, Equatable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
    let backgroundUrl: String?
    let signature: String?
    let gender: Int?           // 0: 未知, 1: 男, 2: 女
    let birthday: Int64?
    let city: Int?
    let province: Int?
    let followed: Bool?
    let followeds: Int?        // 粉丝数
    let follows: Int?          // 关注数
    let playlistCount: Int?
    let eventCount: Int?       // 动态数
    let vipType: Int?
    let level: Int?            // 等级
    let listenSongs: Int?      // 听歌数量

    enum CodingKeys: String, CodingKey {
        case userId, nickname, avatarUrl, backgroundUrl, signature
        case gender, birthday, city, province, followed, followeds, follows
        case playlistCount, eventCount, vipType, level, listenSongs
    }

    init(
        userId: Int,
        nickname: String,
        avatarUrl: String? = nil,
        backgroundUrl: String? = nil,
        signature: String? = nil,
        gender: Int? = nil,
        birthday: Int64? = nil,
        city: Int? = nil,
        province: Int? = nil,
        followed: Bool? = nil,
        followeds: Int? = nil,
        follows: Int? = nil,
        playlistCount: Int? = nil,
        eventCount: Int? = nil,
        vipType: Int? = nil,
        level: Int? = nil,
        listenSongs: Int? = nil
    ) {
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.backgroundUrl = backgroundUrl
        self.signature = signature
        self.gender = gender
        self.birthday = birthday
        self.city = city
        self.province = province
        self.followed = followed
        self.followeds = followeds
        self.follows = follows
        self.playlistCount = playlistCount
        self.eventCount = eventCount
        self.vipType = vipType
        self.level = level
        self.listenSongs = listenSongs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = JSONFlex.int(c, .userId) ?? 0
        nickname = JSONFlex.string(c, .nickname) ?? ""
        avatarUrl = JSONFlex.string(c, .avatarUrl)
        backgroundUrl = JSONFlex.string(c, .backgroundUrl)
        signature = JSONFlex.string(c, .signature)
        gender = JSONFlex.int(c, .gender)
        birthday = JSONFlex.int64(c, .birthday)
        city = JSONFlex.int(c, .city)
        province = JSONFlex.int(c, .province)
        followed = JSONFlex.bool(c, .followed)
        followeds = JSONFlex.int(c, .followeds)
        follows = JSONFlex.int(c, .follows)
        playlistCount = JSONFlex.int(c, .playlistCount)
        eventCount = JSONFlex.int(c, .eventCount)
        vipType = JSONFlex.int(c, .vipType)
        level = JSONFlex.int(c, .level)
        listenSongs = JSONFlex.int(c, .listenSongs)
    }
    
    var genderText: String {
        switch gender {
        case 1: return "男"
        case 2: return "女"
        default: return "未知"
        }
    }
}

// MARK: - 用户详情响应
struct UserDetailResponse: Codable {
    let code: Int
    let level: Int?
    let listenSongs: Int?
    let profile: UserProfile?
    let createDays: Int?       // 注册天数
    let createTime: Int64?

    enum CodingKeys: String, CodingKey {
        case code, level, listenSongs, profile, createDays, createTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = JSONFlex.int(c, .code) ?? 0
        level = JSONFlex.int(c, .level)
        listenSongs = JSONFlex.int(c, .listenSongs)
        profile = try c.decodeIfPresent(UserProfile.self, forKey: .profile)
        createDays = JSONFlex.int(c, .createDays)
        createTime = JSONFlex.int64(c, .createTime)
    }
}

// MARK: - 用户账户响应
struct UserAccountResponse: Codable {
    let code: Int
    let account: Account?
    let profile: UserProfile?

    enum CodingKeys: String, CodingKey {
        case code, account, profile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = JSONFlex.int(c, .code) ?? 0
        account = try c.decodeIfPresent(Account.self, forKey: .account)
        profile = try c.decodeIfPresent(UserProfile.self, forKey: .profile)
    }
}

// MARK: - 登录状态响应
struct LoginStatusResponse: Codable {
    let data: LoginStatusData?
}

struct LoginStatusData: Codable {
    let code: Int
    let account: Account?
    let profile: UserProfile?

    enum CodingKeys: String, CodingKey {
        case code, account, profile
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = JSONFlex.int(c, .code) ?? 200
        account = try c.decodeIfPresent(Account.self, forKey: .account)
        profile = try c.decodeIfPresent(UserProfile.self, forKey: .profile)
    }
}

// MARK: - 二维码相关
struct QRKeyResponse: Codable {
    let code: Int
    let data: QRKeyData?
}

struct QRKeyData: Codable {
    let code: Int
    let unikey: String?
}

struct QRCreateResponse: Codable {
    let code: Int
    let data: QRCreateData?
}

struct QRCreateData: Codable {
    let qrimg: String?
    let qrurl: String?
}

struct QRCheckResponse: Codable {
    let code: Int
    let cookie: String?
    let message: String?
}

// MARK: - 退出登录响应
struct LogoutResponse: Codable {
    let code: Int
}

// MARK: - 验证码相关
struct CaptchaSentResponse: Codable {
    let code: Int
    let data: Bool?
    let message: String?
}

struct CaptchaVerifyResponse: Codable {
    let code: Int
    let data: Bool?
    let message: String?
}

// MARK: - 用户歌单相关
struct UserPlaylistResponse: Codable {
    let code: Int
    let playlist: [CloudPlaylist]?
}

struct CloudPlaylist: Codable, Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let trackCount: Int?
    let playCount: Int?
    let userId: Int?
    let createTime: Int64?
    let specialType: Int?       // 5 表示喜欢的音乐
    let description: String?
    
    var isLikedPlaylist: Bool {
        specialType == 5
    }
    
    var coverUrl: String? {
        coverImgUrl?.replacingOccurrences(of: "http://", with: "https://")
    }
}

// MARK: - 喜欢的音乐ID列表
struct LikelistResponse: Codable {
    let code: Int
    let ids: [Int]?
}

// MARK: - 喜欢歌曲响应
struct LikeResponse: Codable {
    let code: Int
    let playlistId: Int?
}

// MARK: - 收藏的专辑
struct AlbumSublistResponse: Codable {
    let code: Int
    let data: [CloudAlbum]?
    let count: Int?
}

struct CloudAlbum: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let artist: CloudArtist?
    let artists: [CloudArtist]?
    let size: Int?              // 歌曲数
    let publishTime: Int64?
    
    var coverUrl: String? {
        picUrl?.replacingOccurrences(of: "http://", with: "https://")
    }
    
    var artistName: String {
        artist?.name ?? artists?.first?.name ?? "未知艺术家"
    }
}

struct CloudArtist: Codable {
    let id: Int
    let name: String
}

// MARK: - 播客
struct DJSublistResponse: Decodable {
    let code: Int
    let count: Int?
    let djRadios: [CloudDJRadio]?

    enum CodingKeys: String, CodingKey {
        case code, count, djRadios, data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = JSONFlex.int(c, .code) ?? 0
        count = JSONFlex.int(c, .count)
        djRadios = JSONFlex.array(c, .djRadios) ?? JSONFlex.array(c, .data)
    }
}

struct CloudDJRadio: Decodable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let dj: CloudDJCreator?
    let programCount: Int?
    let playCount: Int?
    let desc: String?

    enum CodingKeys: String, CodingKey {
        case id, name, picUrl, dj, programCount, playCount, desc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.int(c, .id) ?? 0
        name = JSONFlex.string(c, .name) ?? ""
        picUrl = JSONFlex.string(c, .picUrl)
        dj = try? c.decodeIfPresent(CloudDJCreator.self, forKey: .dj)
        programCount = JSONFlex.int(c, .programCount)
        playCount = JSONFlex.int(c, .playCount)
        desc = JSONFlex.string(c, .desc)
    }

    var coverUrl: String? {
        picUrl?.replacingOccurrences(of: "http://", with: "https://")
    }

    var creatorName: String {
        dj?.nickname ?? ""
    }
}

struct CloudDJCreator: Decodable {
    let nickname: String?

    enum CodingKeys: String, CodingKey { case nickname }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nickname = JSONFlex.string(c, .nickname)
    }
}

struct DJProgramListResponse: Decodable {
    let code: Int
    let count: Int?
    let programs: [CloudDJProgram]?
    let more: Bool?

    enum CodingKeys: String, CodingKey {
        case code, count, programs, more, djPrograms
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = JSONFlex.int(c, .code) ?? 0
        count = JSONFlex.int(c, .count)
        more = JSONFlex.bool(c, .more)
        programs = JSONFlex.array(c, .programs) ?? JSONFlex.array(c, .djPrograms)
    }
}

struct CloudDJProgram: Decodable, Identifiable {
    let id: Int
    let name: String
    let coverUrl: String?
    let duration: Int?
    let listenerCount: Int?
    let createTime: Int64?
    let description: String?
    let mainSong: CloudDJMainSong?
    let radio: CloudDJRadioBrief?

    enum CodingKeys: String, CodingKey {
        case id, name, coverUrl, blurCoverUrl, duration, listenerCount
        case createTime, description, mainSong, radio, serialNum
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.int(c, .id) ?? JSONFlex.int(c, .serialNum) ?? 0
        name = JSONFlex.string(c, .name) ?? ""
        coverUrl = JSONFlex.string(c, .coverUrl) ?? JSONFlex.string(c, .blurCoverUrl)
        duration = JSONFlex.int(c, .duration)
        listenerCount = JSONFlex.int(c, .listenerCount)
        createTime = JSONFlex.int64(c, .createTime)
        description = JSONFlex.string(c, .description)
        mainSong = try? c.decodeIfPresent(CloudDJMainSong.self, forKey: .mainSong)
        radio = try? c.decodeIfPresent(CloudDJRadioBrief.self, forKey: .radio)
    }

    var artworkUrl: String? {
        (coverUrl ?? mainSong?.albumInfo?.picUrl)?.replacingOccurrences(of: "http://", with: "https://")
    }

    var durationText: String {
        let seconds = (duration ?? mainSong?.durationMS ?? 0) / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func toTrack() -> Track {
        let song = mainSong
        let trackId = song?.id ?? id
        return Track(
            id: trackId == 0 ? id : trackId,
            name: song?.name ?? name,
            ar: song?.artistList?.map { Artist(id: $0.id, name: $0.name) },
            al: song?.albumInfo.map { Album(id: $0.id, name: $0.name, picUrl: $0.picUrl) },
            dt: song?.durationMS ?? duration
        )
    }
}

struct CloudDJMainSong: Decodable {
    let id: Int
    let name: String?
    let duration: Int?
    let dt: Int?
    let artists: [CloudTrackArtist]?
    let ar: [CloudTrackArtist]?
    let album: CloudTrackAlbum?
    let al: CloudTrackAlbum?

    enum CodingKeys: String, CodingKey {
        case id, name, duration, dt, artists, ar, album, al
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.int(c, .id) ?? 0
        name = JSONFlex.string(c, .name)
        duration = JSONFlex.int(c, .duration)
        dt = JSONFlex.int(c, .dt)
        artists = try? c.decodeIfPresent([CloudTrackArtist].self, forKey: .artists)
        ar = try? c.decodeIfPresent([CloudTrackArtist].self, forKey: .ar)
        album = try? c.decodeIfPresent(CloudTrackAlbum.self, forKey: .album)
        al = try? c.decodeIfPresent(CloudTrackAlbum.self, forKey: .al)
    }

    var artistList: [CloudTrackArtist]? { artists ?? ar }
    var albumInfo: CloudTrackAlbum? { album ?? al }
    var durationMS: Int? { duration ?? dt }
}

struct CloudDJRadioBrief: Codable {
    let id: Int?
    let name: String?
}

// MARK: - 云端歌曲模型
struct CloudTrack: Decodable, Identifiable {
    let id: Int
    let name: String
    let ar: [CloudTrackArtist]?
    let al: CloudTrackAlbum?
    let dt: Int?  // 时长(毫秒)
    let fee: Int?
    
    var artistName: String {
        ar?.map { $0.name }.joined(separator: " / ") ?? "未知艺术家"
    }
    
    var albumName: String {
        al?.name ?? ""
    }
    
    var coverUrl: String? {
        al?.picUrl?.replacingOccurrences(of: "http://", with: "https://")
    }
    
    var durationSeconds: TimeInterval {
        Double(dt ?? 0) / 1000.0
    }

    var isVIP: Bool {
        fee == 1 || fee == 4
    }

    var durationText: String {
        let seconds = Int(durationSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    
    func toTrack() -> Track {
        Track(
            id: id,
            name: name,
            ar: ar?.map { Artist(id: $0.id, name: $0.name) },
            al: al.map { Album(id: $0.id, name: $0.name, picUrl: $0.picUrl) },
            artists: nil,
            album: nil,
            dt: dt,
            duration: nil,
            mv: nil,
            mvid: nil,
            fee: fee
        )
    }
}

struct CloudTrackArtist: Decodable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey { case id, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.int(c, .id) ?? 0
        name = JSONFlex.string(c, .name) ?? ""
    }
}

struct CloudTrackAlbum: Decodable {
    let id: Int
    let name: String
    let picUrl: String?

    enum CodingKeys: String, CodingKey { case id, name, picUrl }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = JSONFlex.int(c, .id) ?? 0
        name = JSONFlex.string(c, .name) ?? ""
        picUrl = JSONFlex.string(c, .picUrl)
    }
}

// MARK: - 云端歌单详情响应
struct CloudPlaylistDetailResponse: Decodable {
    let code: Int
    let playlist: CloudPlaylistDetailData?
}

struct CloudPlaylistDetailData: Decodable {
    let id: Int
    let name: String
    let tracks: [CloudTrack]?
}

// MARK: - 云端专辑详情响应
struct CloudAlbumDetailResponse: Decodable {
    let code: Int
    let album: CloudAlbumDetailData?
    let songs: [CloudTrack]?
}

struct CloudAlbumDetailData: Codable {
    let id: Int
    let name: String
}

// MARK: - 云盘响应

struct CloudDiskResponse: Codable {
    let code: Int
    let data: [CloudDiskSong]?
    let count: Int?       // 云盘歌曲总数
    let size: String?     // 已用空间（字节字符串）
    let maxSize: String?  // 总空间（字节字符串）
    let hasMore: Bool?
    
    // 支持 size/maxSize 可能是 String 或 Number
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = JSONFlex.int(container, .code) ?? 0
        data = JSONFlex.array(container, .data)
        count = JSONFlex.int(container, .count)
        hasMore = JSONFlex.bool(container, .hasMore)
        
        // size 可能是 String 或 Number
        if let s = try? container.decodeIfPresent(String.self, forKey: .size) {
            size = s
        } else if let n = try? container.decodeIfPresent(Int64.self, forKey: .size) {
            size = String(n)
        } else {
            size = nil
        }
        
        if let s = try? container.decodeIfPresent(String.self, forKey: .maxSize) {
            maxSize = s
        } else if let n = try? container.decodeIfPresent(Int64.self, forKey: .maxSize) {
            maxSize = String(n)
        } else {
            maxSize = nil
        }
    }
}

struct CloudDiskSong: Codable, Identifiable {
    let songId: Int
    let songName: String
    let artist: String?
    let album: String?
    let fileSize: Int?
    let bitrate: Int?
    let addTime: Int?         // 上传时间(ms)
    let fileName: String?
    let simpleSong: CloudDiskSimpleSong?
    
    var id: Int { songId }
    
    var fileSizeText: String {
        guard let size = fileSize else { return "" }
        let mb = Double(size) / 1024.0 / 1024.0
        if mb >= 1 {
            return String(format: "%.1fMB", mb)
        } else {
            return String(format: "%.0fKB", mb * 1024)
        }
    }
    
    func toTrack() -> Track {
        // 优先使用 simpleSong 中的详细信息
        if let simple = simpleSong {
            let artists: [Artist]? = simple.ar?.compactMap { a in
                Artist(id: a.id ?? 0, name: a.name ?? "未知")
            }
            let albumInfo: Album? = simple.al.map { a in
                Album(id: a.id ?? 0, name: a.name ?? "", picUrl: a.picUrl)
            }
            return Track(
                id: songId,
                name: simple.name ?? songName,
                ar: artists,
                al: albumInfo,
                artists: nil,
                album: nil,
                dt: simple.dt,
                duration: nil,
                mv: nil,
                mvid: nil
            )
        }
        
        // 降级：用云盘自身的字段构造
        return Track(
            id: songId,
            name: songName,
            ar: artist.map { [Artist(id: 0, name: $0)] },
            al: album.map { Album(id: 0, name: $0, picUrl: nil) },
            artists: nil,
            album: nil,
            dt: nil,
            duration: nil,
            mv: nil,
            mvid: nil
        )
    }
}

struct CloudDiskSimpleSong: Codable {
    let id: Int?
    let name: String?
    let ar: [CloudDiskArtist]?
    let al: CloudDiskAlbumInfo?
    let dt: Int?
}

struct CloudDiskArtist: Codable {
    let id: Int?
    let name: String?
}

struct CloudDiskAlbumInfo: Codable {
    let id: Int?
    let name: String?
    let picUrl: String?
}
