import Foundation

// MARK: - 推荐歌单响应
struct PersonalizedResponse: Codable {
    let code: Int
    let result: [RecommendPlaylist]?
}

// MARK: - 推荐歌单
struct RecommendPlaylist: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let coverImgUrl: String?  // 热门歌单API返回的字段
    let playCount: Int?
    let trackCount: Int?
    let copywriter: String?  // 推荐理由
    
    // 获取封面URL，优先使用picUrl，否则使用coverImgUrl
    var coverUrl: String? {
        picUrl ?? coverImgUrl
    }
    
    var playCountText: String {
        guard let count = playCount else { return "" }
        if count >= 100000000 {
            return String(format: "%.1f亿", Double(count) / 100000000)
        } else if count >= 10000 {
            return String(format: "%.1f万", Double(count) / 10000)
        }
        return "\(count)"
    }
}

// MARK: - 歌单详情响应
struct PlaylistDetailResponse: Codable {
    let code: Int
    let playlist: PlaylistDetail?
}

// MARK: - 歌单所有歌曲响应
struct PlaylistAllTracksResponse: Codable {
    let code: Int
    let songs: [Track]?
}

// MARK: - 歌单详情
struct PlaylistDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let description: String?
    let playCount: Int?
    let trackCount: Int?
    let creator: PlaylistCreator?
    let tracks: [Track]?
}

// MARK: - 歌单创建者
struct PlaylistCreator: Codable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
}

// MARK: - 歌曲
struct Track: Codable, Identifiable {
    let id: Int
    let name: String
    let ar: [Artist]?      // 歌手 (歌单详情API)
    let al: Album?         // 专辑 (歌单详情API)
    let artists: [Artist]? // 歌手 (新歌速递API)
    let album: Album?      // 专辑 (新歌速递API)
    let dt: Int?           // 时长(毫秒) - 歌单详情API
    let duration: Int?     // 时长(毫秒) - 新歌速递API
    let mv: Int?           // MV ID，0表示没有MV - 歌单详情API
    let mvid: Int?         // MV ID - 新歌速递API
    let fee: Int?
    let privilege: TrackPrivilege?
    
    var artistName: String {
        // 优先使用artists，其次ar
        if let artists = artists, !artists.isEmpty {
            return artists.map { $0.name }.joined(separator: "/")
        }
        return ar?.map { $0.name }.joined(separator: "/") ?? "未知歌手"
    }

    var primaryArtistId: Int? {
        artists?.first?.id ?? ar?.first?.id
    }
    
    var albumName: String {
        // 优先使用album，其次al
        (album?.name ?? al?.name) ?? "未知专辑"
    }
    
    var coverUrl: String? {
        // 优先使用album，其次al
        album?.picUrl ?? al?.picUrl
    }
    
    var durationText: String {
        // 优先使用duration，其次dt
        guard let dur = duration ?? dt else { return "" }
        let seconds = dur / 1000
        let min = seconds / 60
        let sec = seconds % 60
        return String(format: "%d:%02d", min, sec)
    }
    
    /// 是否有MV
    var hasMV: Bool {
        let mvId = mvid ?? mv ?? 0
        return mvId > 0
    }
    
    /// 时长（秒）
    var durationSeconds: Double {
        guard let dur = duration ?? dt else { return 0 }
        return Double(dur) / 1000.0
    }

    var isVIP: Bool {
        let value = fee ?? privilege?.fee ?? 0
        return value == 1 || value == 4
    }
    
    init(id: Int, name: String, ar: [Artist]? = nil, al: Album? = nil, artists: [Artist]? = nil, album: Album? = nil, dt: Int? = nil, duration: Int? = nil, mv: Int? = nil, mvid: Int? = nil, fee: Int? = nil, privilege: TrackPrivilege? = nil) {
        self.id = id
        self.name = name
        self.ar = ar
        self.al = al
        self.artists = artists
        self.album = album
        self.dt = dt
        self.duration = duration
        self.mv = mv
        self.mvid = mvid
        self.fee = fee
        self.privilege = privilege
    }
}

struct TrackPrivilege: Codable {
    let fee: Int?
    let flag: Int?
    let st: Int?
    let pl: Int?
    let maxbr: Int?
}

// MARK: - 歌手
struct Artist: Codable, Identifiable {
    let id: Int
    let name: String
}

// MARK: - 专辑
struct Album: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
}

// MARK: - Banner响应
struct BannerResponse: Codable {
    let code: Int
    let banners: [Banner]?
}

struct Banner: Codable, Identifiable {
    let pic: String?           // API返回的字段名
    let imageUrl: String?      // 备用字段
    let targetId: Int?
    let targetType: Int?
    let titleColor: String?
    let typeTitle: String?
    let url: String?           // 链接
    
    var id: String {
        bannerImageUrl ?? UUID().uuidString
    }
    
    // 获取图片URL，优先使用pic
    var bannerImageUrl: String? {
        pic ?? imageUrl
    }
}

// MARK: - 搜索响应
struct SearchResponse: Codable {
    let code: Int
    let result: SearchResult?
}

struct SearchResult: Codable {
    let songs: [SearchSong]?
    let songCount: Int?
}

struct SearchSong: Codable, Identifiable {
    let id: Int
    let name: String
    let artists: [SearchArtist]?
    let album: SearchAlbum?
    let duration: Int?
    
    var artistName: String {
        artists?.map { $0.name }.joined(separator: "/") ?? "未知歌手"
    }
    
    var albumName: String {
        album?.name ?? "未知专辑"
    }
    
    var coverUrl: String? {
        album?.coverUrl
    }
    
    var albumId: Int? {
        album?.id
    }
    
    var artistId: Int? {
        artists?.first?.id
    }
    
    var durationText: String {
        guard let dur = duration else { return "" }
        let seconds = dur / 1000
        let min = seconds / 60
        let sec = seconds % 60
        return String(format: "%d:%02d", min, sec)
    }
    
    init(id: Int, name: String, artists: [SearchArtist]? = nil, album: SearchAlbum? = nil, duration: Int? = nil) {
        self.id = id
        self.name = name
        self.artists = artists
        self.album = album
        self.duration = duration
    }
    
    // 转换为Track（可传入外部封面URL覆盖）
    func toTrack(withCoverUrl overrideCoverUrl: String? = nil) -> Track {
        let finalCoverUrl = overrideCoverUrl ?? album?.coverUrl

        return Track(
            id: id,
            name: name,
            ar: artists?.map { Artist(id: $0.id, name: $0.name) },
            al: album.map { Album(id: $0.id, name: $0.name, picUrl: finalCoverUrl) },
            artists: nil,
            album: nil,
            dt: duration,
            duration: nil,
            mv: nil,
            mvid: nil
        )
    }
}

struct SearchArtist: Codable {
    let id: Int
    let name: String
}

struct SearchAlbum: Codable {
    let id: Int
    let name: String
    let picUrl: String?
    let blurPicUrl: String?    // 备用封面
    let picId: Int?            // 封面ID
    let pic: Int?              // 备用封面ID

    // 获取封面URL，优先使用picUrl，其次blurPicUrl
    var coverUrl: String? {
        picUrl ?? blurPicUrl
    }
}

// MARK: - 搜索歌手响应
struct SearchArtistResponse: Codable {
    let code: Int
    let result: SearchArtistResult.Container?
}

extension SearchArtistResult {
    struct Container: Codable {
        let artists: [SearchArtistResult]?
        let artistCount: Int?
    }
}

struct SearchArtistResult: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?       // 歌手头像
    let img1v1Url: String?    // 备用头像
    let alias: [String]?      // 别名
    let albumSize: Int?       // 专辑数
    let mvSize: Int?          // MV数
    
    var avatarUrl: String? {
        img1v1Url ?? picUrl
    }
    
    var aliasText: String? {
        guard let alias = alias, !alias.isEmpty else { return nil }
        return alias.joined(separator: "、")
    }
}

// MARK: - 搜索专辑响应
struct SearchAlbumResponse: Codable {
    let code: Int
    let result: SearchAlbumResult.Container?
}

extension SearchAlbumResult {
    struct Container: Codable {
        let albums: [SearchAlbumResult]?
        let albumCount: Int?
    }
}

struct SearchAlbumResult: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?       // 专辑封面
    let artist: SearchArtistBasic?  // 歌手信息
    let artists: [SearchArtistBasic]?  // 多个歌手
    let publishTime: Int?     // 发行时间
    let size: Int?            // 曲目数
    
    var artistName: String {
        if let artists = artists, !artists.isEmpty {
            return artists.map { $0.name }.joined(separator: "/")
        }
        return artist?.name ?? "未知歌手"
    }
    
    var publishYear: String {
        guard let time = publishTime else { return "" }
        let date = Date(timeIntervalSince1970: Double(time) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }
}

struct SearchArtistBasic: Codable {
    let id: Int
    let name: String
}

// MARK: - 热搜响应
struct HotSearchResponse: Codable {
    let code: Int
    let data: [HotSearch]?
}

struct HotSearch: Codable, Identifiable {
    let searchWord: String
    let score: Int?
    let content: String?
    let iconUrl: String?
    let iconType: Int?    // 1=热 2=新 3=飙升 5=推荐
    
    var id: String { searchWord }
}

// MARK: - 歌曲详情响应
struct SongDetailResponse: Codable {
    let code: Int
    let songs: [Track]?
}

// MARK: - 新歌速递响应
struct TopSongResponse: Codable {
    let code: Int
    let data: [Track]?  // 新歌速递API返回的是data字段，不是songs
}

// MARK: - 新碑上架响应
struct NewAlbumResponse: Codable {
    let code: Int
    let albums: [NewAlbum]?
    let total: Int?
}

struct NewAlbum: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let artist: Artist?
    let artists: [Artist]?
    let publishTime: Int?     // 发行时间(ms)
    let size: Int?            // 曲目数
    let company: String?      // 发行公司
    
    var artistName: String {
        if let artists = artists, !artists.isEmpty {
            return artists.map { $0.name }.joined(separator: "/")
        }
        return artist?.name ?? "未知歌手"
    }
    
    var publishDate: String {
        guard let time = publishTime else { return "" }
        let date = Date(timeIntervalSince1970: Double(time) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct TopArtistsResponse: Codable {
    let code: Int
    let artists: [SearchArtistResult]?
    let more: Bool?
}

// MARK: - 推荐新音乐响应
struct PersonalizedNewSongResponse: Codable {
    let code: Int
    let result: [PersonalizedSong]?
}

struct PersonalizedSong: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let song: PersonalizedSongDetail?
    
    var artistName: String {
        song?.artists?.map { $0.name }.joined(separator: "/") ?? "未知歌手"
    }
    
    var albumName: String {
        song?.album?.name ?? "未知专辑"
    }
    
    // 转换为Track
    func toTrack() -> Track {
        Track(
            id: id,
            name: name,
            ar: song?.artists,
            al: song?.album.map { Album(id: $0.id, name: $0.name, picUrl: $0.picUrl) },
            artists: nil,
            album: nil,
            dt: song?.duration,
            duration: nil,
            mv: song?.mvid,
            mvid: nil
        )
    }
}

struct PersonalizedSongDetail: Codable {
    let id: Int
    let name: String
    let artists: [Artist]?
    let album: PersonalizedAlbum?
    let duration: Int?
    let mvid: Int?
}

struct PersonalizedAlbum: Codable {
    let id: Int
    let name: String
    let picUrl: String?
}

// MARK: - 歌词响应
struct LyricResponse: Codable {
    let code: Int
    let lrc: LyricContent?
    let tlyric: LyricContent?  // 翻译歌词
}

struct LyricContent: Codable {
    let lyric: String?
}

// MARK: - 歌词行
struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double      // 秒
    let text: String
    
    static func parse(_ lyricString: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = "\\[(\\d{2}):(\\d{2})(?:\\.(\\d{2,3}))?\\](.*)" 
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        for line in lyricString.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if let minRange = Range(match.range(at: 1), in: line),
                   let secRange = Range(match.range(at: 2), in: line),
                   let textRange = Range(match.range(at: 4), in: line) {
                    
                    let minutes = Double(line[minRange]) ?? 0
                    let seconds = Double(line[secRange]) ?? 0
                    var milliseconds: Double = 0
                    
                    if let msRange = Range(match.range(at: 3), in: line) {
                        let msStr = String(line[msRange])
                        if msStr.count == 2 {
                            milliseconds = (Double(msStr) ?? 0) * 10
                        } else {
                            milliseconds = Double(msStr) ?? 0
                        }
                    }
                    
                    let time = minutes * 60 + seconds + milliseconds / 1000
                    let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                    
                    if !text.isEmpty {
                        lines.append(LyricLine(time: time, text: text))
                    }
                }
            }
        }
        
        return lines.sorted { $0.time < $1.time }
    }
}

// MARK: - 音乐可用性检查响应
struct CheckMusicResponse: Codable {
    let success: Bool?
    let message: String?
}

// MARK: - 排行榜响应
struct ToplistResponse: Codable {
    let code: Int
    let list: [ToplistItem]?
}

struct ToplistItem: Codable, Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let description: String?
    let playCount: Int?
    let updateFrequency: String?  // 更新频率，如"每天更新"
    let trackCount: Int?
    let tracks: [ToplistTrack]?   // 前几首歌曲
    
    var playCountText: String {
        guard let count = playCount else { return "" }
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000)
        } else if count >= 10000 {
            return String(format: "%.1f万", Double(count) / 10000)
        }
        return "\(count)"
    }
}

struct ToplistTrack: Codable {
    let first: String   // 歌曲名
    let second: String  // 歌手
}

// MARK: - 精品歌单响应
struct TopPlaylistResponse: Codable {
    let code: Int
    let playlists: [RecommendPlaylist]?
    let total: Int?
    let more: Bool?
    let lasttime: Int?
}

// MARK: - 热门歌单响应
struct HotPlaylistResponse: Codable {
    let code: Int
    let playlists: [RecommendPlaylist]?
    let total: Int?
    let more: Bool?
}

// MARK: - 歌单分类响应
struct PlaylistCatResponse: Codable {
    let code: Int
    let all: PlaylistCategory?
    let sub: [PlaylistCategory]?
    let categories: [String: String]?
}

struct PlaylistCategory: Codable, Identifiable, Hashable {
    let name: String
    let category: Int?
    let hot: Bool?
    
    var id: String { name }
}

// MARK: - 动态封面响应
struct DynamicCoverResponse: Codable {
    let code: Int
    let data: DynamicCoverData?
}

struct DynamicCoverData: Codable {
    let videoGroup: DynamicVideoGroup?
}

struct DynamicVideoGroup: Codable {
    let video: DynamicVideo?
}

struct DynamicVideo: Codable {
    let url: String?           // 动态封面视频URL
    let coverUrl: String?      // 封面图
    let width: Int?
    let height: Int?
}

// MARK: - iTunes Search API 响应
struct ITunesSearchResponse: Codable {
    let resultCount: Int?
    let results: [ITunesTrack]?
}

struct ITunesTrack: Codable {
    let trackId: Int?
    let trackName: String?
    let artistName: String?
    let collectionId: Int?      // 专辑ID
    let collectionName: String?
    let artworkUrl100: String?
}

// MARK: - Apple Music AMP API 响应
struct AppleMusicAlbumResponse: Codable {
    let data: [AppleMusicAlbumData]?
}

struct AppleMusicAlbumData: Codable {
    let id: String?
    let attributes: AppleMusicAlbumAttributes?
}

struct AppleMusicAlbumAttributes: Codable {
    let name: String?
    let artistName: String?
    let editorialVideo: AppleMusicEditorialVideo?
}

struct AppleMusicEditorialVideo: Codable {
    let motionSquareVideo1x1: AppleMusicVideoAsset?
    let motionDetailSquare: AppleMusicVideoAsset?
    let motionTallVideo3x4: AppleMusicVideoAsset?
}

struct AppleMusicVideoAsset: Codable {
    let video: String?          // 视频URL
    let previewFrame: AppleMusicPreviewFrame?
}

struct AppleMusicPreviewFrame: Codable {
    let url: String?
}

// MARK: - 评论响应

struct CommentResponse: Codable {
    let code: Int
    let total: Int?
    let more: Bool?
    let hotComments: [Comment]?
    let comments: [Comment]?
}

// MARK: - 新版评论响应

struct CommentNewResponse: Codable {
    let code: Int
    let data: CommentNewData?
}

struct CommentNewData: Codable {
    let commentsTitle: String?
    let comments: [Comment]?
    let totalCount: Int?
    let hasMore: Bool?
    let cursor: String?
    let sortType: Int?
}

// MARK: - 热门评论响应

struct HotCommentResponse: Codable {
    let code: Int
    let total: Int?
    let hasMore: Bool?
    let hotComments: [Comment]?
}

struct Comment: Codable, Identifiable {
    let commentId: Int
    let content: String
    let time: Int               // 时间戳(ms)
    let likedCount: Int?
    let replyCount: Int?        // 回复数量
    let user: CommentUser
    let beReplied: [ReplyComment]?
    let ipLocation: IPLocation?
    
    var id: Int { commentId }
    
    // 是否有回复
    var hasReplies: Bool {
        return (replyCount ?? 0) > 0 || (beReplied?.isEmpty == false)
    }
    
    var timeText: String {
        let date = Date(timeIntervalSince1970: Double(time) / 1000)
        let now = Date()
        let diff = now.timeIntervalSince(date)
        
        if diff < 60 {
            return "刚刚"
        } else if diff < 3600 {
            return "\(Int(diff / 60))分钟前"
        } else if diff < 86400 {
            return "\(Int(diff / 3600))小时前"
        } else if diff < 86400 * 30 {
            return "\(Int(diff / 86400))天前"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
    }
    
    var likedCountText: String {
        guard let count = likedCount, count > 0 else { return "" }
        if count >= 10000 {
            return String(format: "%.1f万", Double(count) / 10000)
        }
        return "\(count)"
    }
}

struct CommentUser: Codable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
}

struct ReplyComment: Codable {
    let content: String
    let user: CommentUser
    let beRepliedUser: CommentUser?  // 被回复的用户
}

struct IPLocation: Codable {
    let location: String?
}

// MARK: - 楼层回复响应

struct CommentFloorResponse: Codable {
    let code: Int
    let data: CommentFloorData?
}

struct CommentFloorData: Codable {
    let comments: [FloorComment]?
    let totalCount: Int?
    let hasMore: Bool?
    let time: Int?  // 用于分页
}

struct FloorComment: Codable, Identifiable {
    let commentId: Int
    let content: String
    let time: Int
    let likedCount: Int?
    let user: CommentUser
    let beRepliedUser: CommentUser?  // 被回复的用户
    let ipLocation: IPLocation?
    
    var id: Int { commentId }
    
    var timeText: String {
        let date = Date(timeIntervalSince1970: Double(time) / 1000)
        let now = Date()
        let diff = now.timeIntervalSince(date)
        
        if diff < 60 {
            return "刚刚"
        } else if diff < 3600 {
            return "\(Int(diff / 60))分钟前"
        } else if diff < 86400 {
            return "\(Int(diff / 3600))小时前"
        } else if diff < 86400 * 30 {
            return "\(Int(diff / 86400))天前"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }
    }
}

// MARK: - 发送评论响应

struct SendCommentResponse: Codable {
    let code: Int
    let comment: Comment?
    let message: String?
}

// MARK: - 基础响应

struct BaseResponse: Codable {
    let code: Int
    let message: String?
}

// MARK: - 歌手详情响应

struct ArtistDetailResponse: Codable {
    let code: Int
    let data: ArtistDetailData?
}

struct ArtistDetailData: Codable {
    let artist: ArtistDetail?
}

struct ArtistDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let cover: String?          // 歌手封面
    let avatar: String?         // 歌手头像
    let briefDesc: String?      // 简介
    let albumSize: Int?         // 专辑数
    let musicSize: Int?         // 单曲数
    let mvSize: Int?            // MV数
    
    var imageUrl: String? {
        avatar ?? cover
    }
}

// MARK: - 歌手热门歌曲响应

struct ArtistTopSongsResponse: Codable {
    let code: Int
    let songs: [Track]?
    let more: Bool?
}

// MARK: - 歌手专辑响应

struct ArtistAlbumsResponse: Codable {
    let code: Int
    let hotAlbums: [AlbumDetail]?
    let more: Bool?
}

// MARK: - 专辑详情响应

struct AlbumDetailResponse: Codable {
    let code: Int
    let album: AlbumDetail?
    let songs: [Track]?
}

struct AlbumDetail: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?         // 专辑封面
    let description: String?    // 专辑描述
    let publishTime: Int?       // 发行时间(ms)
    let size: Int?              // 曲目数
    let company: String?        // 发行公司
    let subType: String?        // 专辑类型
    let artist: Artist?         // 歌手
    let artists: [Artist]?      // 歌手列表
    
    var publishTimeText: String {
        guard let time = publishTime else { return "" }
        let date = Date(timeIntervalSince1970: Double(time) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    var artistName: String {
        if let artists = artists, !artists.isEmpty {
            return artists.map { $0.name }.joined(separator: "/")
        }
        return artist?.name ?? "未知歌手"
    }
}

// MARK: - 带翻译的歌词行

struct LyricLineWithTranslation: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
    let translation: String?    // 翻译歌词
    
    init(time: Double, text: String, translation: String?) {
        self.time = time
        self.text = text
        self.translation = translation
    }
    
    /// 解析原文歌词和翻译歌词
    static func parse(lyric: String, translation: String?) -> [LyricLineWithTranslation] {
        let originalLines = parseLyricString(lyric)
        
        guard let translation = translation, !translation.isEmpty else {
            // 没有翻译歌词
            return originalLines.map { LyricLineWithTranslation(time: $0.time, text: $0.text, translation: nil) }
        }
        
        let translationLines = parseLyricString(translation)
        var translationDict: [Double: String] = [:]
        
        // 将翻译歌词按时间建立索引
        for line in translationLines {
            translationDict[line.time] = line.text
        }
        
        // 合并原文和翻译
        return originalLines.map { line in
            // 尝试找到对应的翻译（允许0.5秒误差）
            var trans: String?
            for (time, text) in translationDict {
                if abs(time - line.time) < 0.5 {
                    trans = text
                    break
                }
            }
            return LyricLineWithTranslation(time: line.time, text: line.text, translation: trans)
        }
    }
    
    /// 解析歌词字符串
    private static func parseLyricString(_ lyricString: String) -> [(time: Double, text: String)] {
        var lines: [(time: Double, text: String)] = []
        let pattern = "\\[(\\d{2}):(\\d{2})(?:\\.(\\d{2,3}))?\\](.*)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        for line in lyricString.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if let minRange = Range(match.range(at: 1), in: line),
                   let secRange = Range(match.range(at: 2), in: line),
                   let textRange = Range(match.range(at: 4), in: line) {
                    
                    let minutes = Double(line[minRange]) ?? 0
                    let seconds = Double(line[secRange]) ?? 0
                    var milliseconds: Double = 0
                    
                    if let msRange = Range(match.range(at: 3), in: line) {
                        let msStr = String(line[msRange])
                        if msStr.count == 2 {
                            milliseconds = (Double(msStr) ?? 0) * 10
                        } else {
                            milliseconds = Double(msStr) ?? 0
                        }
                    }
                    
                    let time = minutes * 60 + seconds + milliseconds / 1000
                    let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                    
                    if !text.isEmpty {
                        lines.append((time: time, text: text))
                    }
                }
            }
        }
        
        return lines.sorted { $0.time < $1.time }
    }
}

// MARK: - 逐字歌词(YRC)响应

struct YrcLyricResponse: Codable {
    let code: Int
    let lrc: LyricContent?
    let tlyric: LyricContent?    // 翻译歌词
    let yrc: YrcContent?         // 逐字歌词
}

struct YrcContent: Codable {
    let version: Int?
    let lyric: String?
}

// MARK: - 逐字歌词单词

struct YrcWord: Identifiable {
    let id = UUID()
    let startTime: Double    // 开始时间(秒)
    let duration: Double     // 时长(秒)
    let text: String         // 文字
    
    var endTime: Double {
        startTime + duration
    }
    
    /// 计算当前时间的变色进度(0-1)
    func progress(at currentTime: Double) -> Double {
        if currentTime < startTime {
            return 0
        } else if currentTime >= endTime {
            return 1
        } else {
            return (currentTime - startTime) / duration
        }
    }
}

// MARK: - 逐字歌词行

struct YrcLine: Identifiable {
    let id = UUID()
    let startTime: Double    // 行开始时间(秒)
    let duration: Double     // 行时长(秒)
    let words: [YrcWord]     // 逐字列表
    let translation: String? // 翻译
    
    var endTime: Double {
        startTime + duration
    }
    
    /// 完整文本
    var text: String {
        words.map { $0.text }.joined()
    }
    
    /// 解析YRC格式字符串
    /// 格式: [行开始时间,行时长](字开始时间,字时长,0)字1(字开始时间,字时长,0)字2...
    static func parse(yrcString: String, translation: String?) -> [YrcLine] {
        var lines: [YrcLine] = []
        
        // 解析翻译歌词建立时间索引
        var translationDict: [Double: String] = [:]
        if let translation = translation, !translation.isEmpty {
            let transLines = parseLrcString(translation)
            for (time, text) in transLines {
                translationDict[time] = text
            }
        }
        
        // 解析YRC每一行
        // 行格式: [行开始时间,行时长](字开始,字时长,0)字...
        let linePattern = #"\[(\d+),(\d+)\](.*)"#
        guard let lineRegex = try? NSRegularExpression(pattern: linePattern) else {
            return []
        }
        
        for line in yrcString.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let lineMatch = lineRegex.firstMatch(in: trimmed, range: range),
                  let startRange = Range(lineMatch.range(at: 1), in: trimmed),
                  let durationRange = Range(lineMatch.range(at: 2), in: trimmed),
                  let contentRange = Range(lineMatch.range(at: 3), in: trimmed) else {
                continue
            }
            
            let lineStartMs = Double(trimmed[startRange]) ?? 0
            let lineDurationMs = Double(trimmed[durationRange]) ?? 0
            let content = String(trimmed[contentRange])
            
            // 解析逐字: (开始时间,时长,0)字
            let lineStartSec = lineStartMs / 1000.0
            let words = parseWords(content)

            if !words.isEmpty {
                // 查找对应的翻译
                var trans: String?
                for (time, text) in translationDict {
                    if abs(time - lineStartSec) < 0.5 {
                        trans = text
                        break
                    }
                }
                
                lines.append(YrcLine(
                    startTime: lineStartSec,
                    duration: lineDurationMs / 1000.0,
                    words: words,
                    translation: trans
                ))
            }
        }
        
        return lines.sorted { $0.startTime < $1.startTime }
    }
    
    /// 解析逐字内容
    private static func parseWords(_ content: String) -> [YrcWord] {
        var words: [YrcWord] = []

        // 匹配 (startTime,duration,0)text 格式
        let wordPattern = #"\((\d+),(\d+),\d+\)([^(]*)"#
        guard let wordRegex = try? NSRegularExpression(pattern: wordPattern) else {
            return []
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = wordRegex.matches(in: content, range: range)

        for match in matches {
            guard let startRange = Range(match.range(at: 1), in: content),
                  let durationRange = Range(match.range(at: 2), in: content),
                  let textRange = Range(match.range(at: 3), in: content) else {
                continue
            }

            let startMs = Double(content[startRange]) ?? 0
            let durationMs = Double(content[durationRange]) ?? 0
            let text = String(content[textRange])

            if !text.isEmpty {
                words.append(YrcWord(
                    startTime: startMs / 1000.0,
                    duration: durationMs / 1000.0,
                    text: text
                ))
            }
        }

        return words
    }
    
    /// 解析普通LRC格式
    private static func parseLrcString(_ lyricString: String) -> [(time: Double, text: String)] {
        var lines: [(time: Double, text: String)] = []
        let pattern = "\\[(\\d{2}):(\\d{2})(?:\\.(\\d{2,3}))?\\](.*)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        
        for line in lyricString.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if let minRange = Range(match.range(at: 1), in: line),
                   let secRange = Range(match.range(at: 2), in: line),
                   let textRange = Range(match.range(at: 4), in: line) {
                    
                    let minutes = Double(line[minRange]) ?? 0
                    let seconds = Double(line[secRange]) ?? 0
                    var milliseconds: Double = 0
                    
                    if let msRange = Range(match.range(at: 3), in: line) {
                        let msStr = String(line[msRange])
                        if msStr.count == 2 {
                            milliseconds = (Double(msStr) ?? 0) * 10
                        } else {
                            milliseconds = Double(msStr) ?? 0
                        }
                    }
                    
                    let time = minutes * 60 + seconds + milliseconds / 1000
                    let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                    
                    if !text.isEmpty {
                        lines.append((time: time, text: text))
                    }
                }
            }
        }
        
        return lines
    }
}


// MARK: - 心动模式响应

struct HeartbeatModeResponse: Codable {
    let code: Int
    let data: [HeartbeatSong]?
}

struct HeartbeatSong: Codable, Identifiable {
    let id: Int
    let songInfo: HeartbeatSongInfo?
    let recommended: Bool?
    
    // 转换为Track
    func toTrack() -> Track? {
        guard let info = songInfo else { return nil }
        return Track(
            id: info.id,
            name: info.name,
            ar: info.ar,
            al: info.al,
            artists: nil,
            album: nil,
            dt: info.dt,
            duration: nil,
            mv: info.mv,
            mvid: nil
        )
    }
}

struct HeartbeatSongInfo: Codable {
    let id: Int
    let name: String
    let ar: [Artist]?
    let al: Album?
    let dt: Int?
    let mv: Int?
}

// MARK: - 雷达歌单响应

struct RadarPlaylistResponse: Codable {
    let code: Int
    let data: RadarPlaylistData?
}

struct RadarPlaylistData: Codable {
    let blocks: [RadarBlock]?
}

struct RadarBlock: Codable {
    let blockCode: String?
    let creatives: [RadarCreative]?
}

struct RadarCreative: Codable {
    let creativeId: String?
    let resources: [RadarResource]?
}

struct RadarResource: Codable {
    let resourceId: String?
    let resourceType: String?
    let resourceExtInfo: RadarResourceExtInfo?
}

struct RadarResourceExtInfo: Codable {
    let playCount: Int?
    let highQuality: Bool?
    let specialType: Int?
    let songData: RadarSongData?
}

struct RadarSongData: Codable {
    let id: Int?
    let name: String?
    let ar: [Artist]?
    let al: Album?
    let dt: Int?
    
    func toTrack() -> Track? {
        guard let id = id, let name = name else { return nil }
        return Track(
            id: id,
            name: name,
            ar: ar,
            al: al,
            artists: nil,
            album: nil,
            dt: dt,
            duration: nil,
            mv: nil,
            mvid: nil
        )
    }
}

// MARK: - 每日推荐歌曲响应

struct DailyRecommendSongsResponse: Codable {
    let code: Int
    let data: DailyRecommendData?
}

struct DailyRecommendData: Codable {
    let dailySongs: [Track]?
}

// MARK: - 私人FM响应

struct PersonalFMResponse: Codable {
    let code: Int
    let data: [FMTrack]?
}

struct FMTrack: Codable {
    let id: Int
    let name: String
    let artists: [Artist]?
    let album: Album?
    let duration: Int?
    let mvid: Int?
    
    func toTrack() -> Track {
        Track(
            id: id,
            name: name,
            ar: nil,
            al: nil,
            artists: artists,
            album: album,
            dt: nil,
            duration: duration,
            mv: nil,
            mvid: mvid
        )
    }
}

// MARK: - FM垃圾桶响应

struct FMTrashResponse: Codable {
    let code: Int
}

// MARK: - 搜索建议响应

struct SearchSuggestResponse: Codable {
    let code: Int
    let result: SearchSuggestResult?
}

struct SearchSuggestResult: Codable {
    let songs: [SuggestSong]?
    let artists: [SuggestArtist]?
    let albums: [SuggestAlbum]?
    let order: [String]?
}

struct SuggestSong: Codable, Identifiable {
    let id: Int
    let name: String
    let artists: [SuggestArtistBrief]?
    let album: SuggestAlbumBrief?
    
    var artistName: String {
        artists?.map { $0.name }.joined(separator: "/") ?? "未知歌手"
    }
}

struct SuggestArtist: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
}

struct SuggestAlbum: Codable, Identifiable {
    let id: Int
    let name: String
    let artist: SuggestArtistBrief?
    let picUrl: String?
}

struct SuggestArtistBrief: Codable {
    let id: Int
    let name: String
}

struct SuggestAlbumBrief: Codable {
    let id: Int
    let name: String
}
