import Foundation

/// 音乐服务
class MusicService {
    static let shared = MusicService()
    private let network = NetworkService.shared
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - 通用网络请求方法

    /// 通用 GET 请求（自动解码，走 NetworkService 统一管理 cookie）
    private func fetch<T: Decodable>(_ endpoint: String) async throws -> T {
        guard let url = URL(string: "\(APIConfig.baseURL)/\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
        return try decoder.decode(T.self, from: data)
    }

    /// 通用 GET 请求（带完整 URL，走 NetworkService）
    private func fetchURL<T: Decodable>(_ url: URL) async throws -> T {
        let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
        return try decoder.decode(T.self, from: data)
    }

    /// 预热网络连接（DNS解析 + TCP连接）
    func warmup() {
        Task(priority: .background) {
            guard let url = URL(string: "\(APIConfig.baseURL)/personalized?limit=1") else { return }
            _ = try? await network.requestWithCookie(url: url, method: "GET")
        }
    }
    
    /// 获取推荐歌单（带缓存）
    /// - Parameter limit: 数量，默认30
    func getPersonalized(limit: Int = 30) async throws -> [RecommendPlaylist] {
        if let cached = await APICache.shared.getCachedPersonalized() {
            return cached
        }
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let response: PersonalizedResponse = try await fetch("personalized?limit=\(limit)&timestamp=\(timestamp)")
        let result = response.result ?? []
        await APICache.shared.cachePersonalized(result)
        return result
    }

    /// 获取歌单详情（带缓存 + 请求去重）
    /// - Parameter id: 歌单ID
    func getPlaylistDetail(id: Int) async throws -> PlaylistDetail? {
        let cacheKey = "playlistDetail_\(id)"
        return try await APICache.shared.deduplicated(cacheKey, ttl: 5 * 60) { [self] in
            let response: PlaylistDetailResponse = try await fetch("playlist/detail?id=\(id)")
            return response.playlist as PlaylistDetail?
        }
    }
    
    /// 获取歌单所有歌曲（用于歌曲数量较多的歌单）
    /// - Parameters:
    ///   - id: 歌单ID
    ///   - limit: 每次获取数量，默认500
    ///   - offset: 偏移量
    func getPlaylistAllTracks(id: Int, limit: Int = 500, offset: Int = 0) async throws -> [Track] {
        let response: PlaylistAllTracksResponse = try await fetch("playlist/track/all?id=\(id)&limit=\(limit)&offset=\(offset)")
        return response.songs ?? []
    }

    /// 获取Banner（带缓存）
    func getBanners() async throws -> [Banner] {
        if let cached = await APICache.shared.getCachedBanners() {
            return cached
        }
        let response: BannerResponse = try await fetch("banner?type=1")
        let result = response.banners ?? []
        await APICache.shared.cacheBanners(result)
        return result
    }

    /// 获取歌词
    func getLyric(id: Int) async throws -> String {
        let response: LyricResponse = try await fetch("lyric?id=\(id)")
        return response.lrc?.lyric ?? ""
    }

    /// 获取歌词（带翻译）
    func getLyricWithTranslation(id: Int) async throws -> (lyric: String, translation: String?) {
        let response: LyricResponse = try await fetch("lyric?id=\(id)")
        return (response.lrc?.lyric ?? "", response.tlyric?.lyric)
    }

    /// 获取逐字歌词（YRC格式）
    func getYrcLyric(id: Int) async throws -> (yrc: String?, lyric: String, translation: String?) {
        let response: YrcLyricResponse = try await fetch("lyric/new?id=\(id)")
        return (response.yrc?.lyric, response.lrc?.lyric ?? "", response.tlyric?.lyric)
    }

    /// 搜索歌曲
    func search(keyword: String, limit: Int = 30, offset: Int = 0) async throws -> [SearchSong] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let response: SearchResponse = try await fetch("search?keywords=\(encoded)&limit=\(limit)&offset=\(offset)&type=1")
        return response.result?.songs ?? []
    }

    /// 搜索歌手
    func searchArtists(keyword: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchArtistResult] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let response: SearchArtistResponse = try await fetch("search?keywords=\(encoded)&limit=\(limit)&offset=\(offset)&type=100")
        return response.result?.artists ?? []
    }

    /// 搜索专辑
    func searchAlbums(keyword: String, limit: Int = 20, offset: Int = 0) async throws -> [SearchAlbumResult] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let response: SearchAlbumResponse = try await fetch("search?keywords=\(encoded)&limit=\(limit)&offset=\(offset)&type=10")
        return response.result?.albums ?? []
    }

    /// 获取热搜列表（带缓存）
    func getHotSearch() async throws -> [HotSearch] {
        if let cached = await APICache.shared.getCachedHotSearch() {
            return cached
        }
        let response: HotSearchResponse = try await fetch("search/hot/detail")
        let result = response.data ?? []
        await APICache.shared.cacheHotSearch(result)
        return result
    }

    /// 获取歌曲详情(包含封面)
    func getSongDetail(ids: [Int]) async throws -> [Track] {
        let idsStr = ids.map { String($0) }.joined(separator: ",")
        let response: SongDetailResponse = try await fetch("song/detail?ids=\(idsStr)")
        return response.songs ?? []
    }

    /// 获取歌曲播放URL
    func getSongUrl(id: Int, br: Int = 320000) async throws -> SongUrlData? {
        let response: SongUrlResponse = try await fetch("song/url?id=\(id)&br=\(br)")
        return response.data?.first
    }

    /// 检查音乐是否可用（是否可播放）
    func checkMusicAvailable(id: Int) async throws -> Bool {
        let response: CheckMusicResponse = try await fetch("check/music?id=\(id)")
        return response.success ?? false
    }

    /// 获取所有排行榜（带缓存）
    func getToplist() async throws -> [ToplistItem] {
        if let cached = await APICache.shared.getCachedToplist() {
            return cached
        }
        let response: ToplistResponse = try await fetch("toplist")
        let result = response.list ?? []
        await APICache.shared.cacheToplist(result)
        return result
    }

    /// 获取精品歌单（歌单广场）
    func getTopPlaylist(cat: String = "全部", limit: Int = 30, before: Int? = nil) async throws -> [RecommendPlaylist] {
        let catEncoded = cat.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cat
        var endpoint = "top/playlist/highquality?cat=\(catEncoded)&limit=\(limit)"
        if let before = before {
            endpoint += "&before=\(before)"
        }
        let response: TopPlaylistResponse = try await fetch(endpoint)
        return response.playlists ?? []
    }

    /// 获取热门歌单
    func getHotPlaylist(cat: String = "全部", limit: Int = 30, offset: Int = 0) async throws -> [RecommendPlaylist] {
        let catEncoded = cat.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cat
        let response: HotPlaylistResponse = try await fetch("top/playlist?cat=\(catEncoded)&limit=\(limit)&offset=\(offset)")
        return response.playlists ?? []
    }
    
    /// 获取新歌速递
    /// - Parameter type: 地区类型 0:全部 7:华语 96:欧美 8:日本 16:韩国
    func getTopSongs(type: Int = 0) async throws -> [Track] {
        let response: TopSongResponse = try await fetch("top/song?type=\(type)")
        return response.data ?? []
    }
    
    /// 获取新碑上架（最新专辑）
    /// - Parameters:
    ///   - area: 地区 ALL:全部 ZH:华语 EA:欧美 JP:日本 KR:韩国
    ///   - limit: 数量
    ///   - offset: 偏移
    func getNewAlbums(area: String = "ALL", limit: Int = 30, offset: Int = 0) async throws -> [NewAlbum] {
        let response: NewAlbumResponse = try await fetch("album/new?area=\(area)&limit=\(limit)&offset=\(offset)")
        return response.albums ?? []
    }

    func getTopArtists(limit: Int = 20, offset: Int = 0) async throws -> [SearchArtistResult] {
        let response: TopArtistsResponse = try await fetch("top/artists?limit=\(limit)&offset=\(offset)")
        return response.artists ?? []
    }
    
    /// 获取推荐新音乐（首页推荐新歌）
    func getPersonalizedNewSong(limit: Int = 10) async throws -> [PersonalizedSong] {
        let response: PersonalizedNewSongResponse = try await fetch("personalized/newsong?limit=\(limit)")
        return response.result ?? []
    }

    /// 获取歌单分类
    func getPlaylistCategories() async throws -> PlaylistCatResponse {
        return try await fetch("playlist/catlist")
    }

    /// 获取专辑动态封面 (网易云)
    func getDynamicCover(albumId: Int) async throws -> String? {
        let response: DynamicCoverResponse = try await fetch("album/detail/dynamic?id=\(albumId)")
        return response.data?.videoGroup?.video?.url
    }
    
    /// 获取 Apple Music 动态封面
    /// - Parameters:
    ///   - songName: 歌曲名
    ///   - artistName: 歌手名
    func getAppleMusicAnimatedCover(songName: String, artistName: String) async throws -> String? {
        // Step 1 & 2: 并行执行 iTunes 搜索和 Token 获取
        let searchTerm = "\(songName) \(artistName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let searchUrl = URL(string: "https://itunes.apple.com/search?term=\(searchTerm)&media=music&entity=song&limit=1") else {
            throw NetworkError.invalidURL
        }

        async let tokenTask = AppleMusicTokenManager.shared.getToken()
        async let searchTask: (Data, URLResponse) = URLSession.shared.data(from: searchUrl)

        guard let token = await tokenTask else {
            print("❌ 无法获取 Apple Music Token")
            return nil
        }

        let (searchData, _) = try await searchTask
        let searchResponse = try JSONDecoder().decode(ITunesSearchResponse.self, from: searchData)

        guard let result = searchResponse.results?.first else {
            print("🎵 iTunes 未找到: \(songName) - \(artistName)")
            return nil
        }

        guard let collectionId = result.collectionId else {
            print("🎵 无专辑ID: \(songName)")
            return nil
        }

        // Step 3: 调用 Apple Music AMP API 获取动态封面
        guard let ampUrl = URL(string: "https://amp-api.music.apple.com/v1/catalog/cn/albums/\(collectionId)?extend=editorialVideo") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: ampUrl)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        
        let (ampData, _) = try await URLSession.shared.data(for: request)
        let ampResponse = try JSONDecoder().decode(AppleMusicAlbumResponse.self, from: ampData)
        
        // Step 4: 提取动态封面 URL
        if let editorialVideo = ampResponse.data?.first?.attributes?.editorialVideo {
            let videoUrl = editorialVideo.motionTallVideo3x4?.video ??
                           editorialVideo.motionSquareVideo1x1?.video ??
                           editorialVideo.motionDetailSquare?.video
            
            if videoUrl != nil {
                print("✅ 找到动态封面: \(songName)")
            } else {
                print("⚠️ 专辑无动态封面: \(songName) (albumId: \(collectionId))")
            }
            return videoUrl
        }
        
        print("⚠️ 专辑无 editorialVideo: \(songName) (albumId: \(collectionId))")
        return nil
    }
    
    // MARK: - 心动模式 API
    
    /// 获取心动模式歌曲列表
    /// - Parameters:
    ///   - songId: 当前歌曲ID
    ///   - playlistId: 歌单ID（必须是用户自己的歌单）
    ///   - startMusicId: 开始歌曲ID（可选，用于分页）
    func getHeartbeatList(songId: Int, playlistId: Int, startMusicId: Int? = nil) async throws -> [Track] {
        var endpoint = "playmode/intelligence/list?id=\(songId)&pid=\(playlistId)"
        if let startId = startMusicId {
            endpoint += "&sid=\(startId)"
        }
        
        guard let url = URL(string: "\(APIConfig.baseURL)/\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        
        // 先检查code
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? Int {
            if code == 301 {
                throw NetworkError.serverError(301, "需要登录")
            } else if code != 200 {
                throw NetworkError.serverError(code, json["message"] as? String)
            }
        }
        
        let response = try JSONDecoder().decode(HeartbeatModeResponse.self, from: data)
        return response.data?.compactMap { $0.toTrack() } ?? []
    }
    
    /// 获取用户的"喜欢的音乐"歌单ID
    func getUserLikedPlaylistId() async throws -> Int? {
        guard let url = URL(string: "\(APIConfig.baseURL)/user/account") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        
        // 解析用户ID
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let userId = profile["userId"] as? Int else {
            return nil
        }
        
        // 获取用户歌单
        guard let playlistUrl = URL(string: "\(APIConfig.baseURL)/user/playlist?uid=\(userId)") else {
            throw NetworkError.invalidURL
        }
        
        let (playlistData, _) = try await NetworkService.shared.requestWithCookie(url: playlistUrl, method: "GET")
        
        guard let playlistJson = try? JSONSerialization.jsonObject(with: playlistData) as? [String: Any],
              let playlists = playlistJson["playlist"] as? [[String: Any]] else {
            return nil
        }
        
        // 第一个歌单通常是"喜欢的音乐"
        return playlists.first?["id"] as? Int
    }
    
    // MARK: - 雷达歌单 API
    
    /// 获取用户的私人雷达歌单
    func getRadarPlaylist() async throws -> [Track] {
        guard let url = URL(string: "\(APIConfig.baseURL)/user/account") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        
        // 解析用户ID
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? Int,
              code == 200,
              let profile = json["profile"] as? [String: Any],
              let userId = profile["userId"] as? Int else {
            throw NetworkError.serverError(301, "需要登录")
        }
        
        // 获取用户歌单
        guard let playlistUrl = URL(string: "\(APIConfig.baseURL)/user/playlist?uid=\(userId)") else {
            throw NetworkError.invalidURL
        }
        
        let (playlistData, _) = try await NetworkService.shared.requestWithCookie(url: playlistUrl, method: "GET")
        
        guard let playlistJson = try? JSONSerialization.jsonObject(with: playlistData) as? [String: Any],
              let playlists = playlistJson["playlist"] as? [[String: Any]] else {
            throw NetworkError.serverError(500, "获取歌单失败")
        }
        
        // 查找私人雷达歌单（名字包含"私人雷达"）
        guard let radarPlaylist = playlists.first(where: { 
            ($0["name"] as? String)?.contains("私人雷达") == true 
        }),
              let radarId = radarPlaylist["id"] as? Int else {
            // 没有私人雷达歌单
            return []
        }
        
        // 获取雷达歌单的歌曲
        return try await getPlaylistAllTracks(id: radarId)
    }
    
    /// 获取每日推荐歌曲
    func getDailyRecommendSongs() async throws -> [Track] {
        guard let url = URL(string: "\(APIConfig.baseURL)/recommend/songs") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        let response = try JSONDecoder().decode(DailyRecommendSongsResponse.self, from: data)
        
        return response.data?.dailySongs ?? []
    }
    
    // MARK: - 评论 API
    
    /// 获取歌曲评论（旧版接口）
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - limit: 每页数量
    ///   - offset: 偏移量
    func getComments(id: Int, limit: Int = 20, offset: Int = 0) async throws -> CommentResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/comment/music?id=\(id)&limit=\(limit)&offset=\(offset)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
        return try decoder.decode(CommentResponse.self, from: data)
    }
    
    /// 获取歌曲评论（新版接口，支持排序）
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - sortType: 排序方式 1=推荐 2=热度 3=时间（最新）
    ///   - pageNo: 页码，从1开始
    ///   - pageSize: 每页数量
    ///   - cursor: 分页游标，第一页不传，后续传上一页返回的cursor
    func getCommentsNew(id: Int, sortType: Int = 3, pageNo: Int = 1, pageSize: Int = 20, cursor: String? = nil) async throws -> CommentNewResponse {
        var urlString = "\(APIConfig.baseURL)/comment/new?id=\(id)&type=0&sortType=\(sortType)&pageNo=\(pageNo)&pageSize=\(pageSize)"
        if let cursor = cursor {
            urlString += "&cursor=\(cursor)"
        }
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
        return try decoder.decode(CommentNewResponse.self, from: data)
    }
    
    /// 获取热门评论
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - limit: 每页数量
    ///   - offset: 偏移量
    func getHotComments(id: Int, limit: Int = 20, offset: Int = 0) async throws -> HotCommentResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/comment/hot?id=\(id)&type=0&limit=\(limit)&offset=\(offset)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
        return try decoder.decode(HotCommentResponse.self, from: data)
    }
    
    /// 发送歌曲评论
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - content: 评论内容
    ///   - commentId: 回复的评论ID（可选，用于回复评论）
    func sendComment(id: Int, content: String, commentId: Int? = nil) async throws -> SendCommentResponse {
        var urlString = "\(APIConfig.baseURL)/comment?t=1&type=0&id=\(id)&content=\(content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? content)"
        
        // 如果是回复评论
        if let commentId = commentId {
            urlString = "\(APIConfig.baseURL)/comment?t=2&type=0&id=\(id)&content=\(content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? content)&commentId=\(commentId)"
        }
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "POST")
        return try JSONDecoder().decode(SendCommentResponse.self, from: data)
    }
    
    /// 点赞/取消点赞评论
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - commentId: 评论ID
    ///   - like: true点赞，false取消
    func likeComment(id: Int, commentId: Int, like: Bool) async throws -> BaseResponse {
        let t = like ? 1 : 0
        guard let url = URL(string: "\(APIConfig.baseURL)/comment/like?id=\(id)&cid=\(commentId)&t=\(t)&type=0") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "POST")
        return try JSONDecoder().decode(BaseResponse.self, from: data)
    }
    
    /// 获取评论的楼层回复
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - commentId: 父评论ID
    ///   - limit: 每页数量
    ///   - time: 分页参数，第一页传0，后续传上一页最后一条回复的time
    func getCommentFloor(id: Int, commentId: Int, limit: Int = 20, time: Int = 0) async throws -> CommentFloorResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/comment/floor?parentCommentId=\(commentId)&id=\(id)&type=0&limit=\(limit)&time=\(time)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
        return try decoder.decode(CommentFloorResponse.self, from: data)
    }
    
    // MARK: - 歌手 API
    
    /// 获取歌手详情（带缓存 + 请求去重）
    /// - Parameter id: 歌手ID
    func getArtistDetail(id: Int) async throws -> ArtistDetail? {
        let cacheKey = "artistDetail_\(id)"
        return try await APICache.shared.deduplicated(cacheKey, ttl: 10 * 60) { [self] in
            guard let url = URL(string: "\(APIConfig.baseURL)/artist/detail?id=\(id)") else {
                throw NetworkError.invalidURL
            }
            let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
            let response = try JSONDecoder().decode(ArtistDetailResponse.self, from: data)
            return response.data?.artist as ArtistDetail?
        }
    }
    
    /// 获取歌手热门歌曲
    /// - Parameter id: 歌手ID
    func getArtistTopSongs(id: Int) async throws -> [Track] {
        guard let url = URL(string: "\(APIConfig.baseURL)/artist/top/song?id=\(id)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
        let response = try decoder.decode(ArtistTopSongsResponse.self, from: data)
        
        return response.songs ?? []
    }
    
    /// 获取歌手专辑
    /// - Parameters:
    ///   - id: 歌手ID
    ///   - limit: 数量
    ///   - offset: 偏移
    func getArtistAlbums(id: Int, limit: Int = 30, offset: Int = 0) async throws -> [AlbumDetail] {
        guard let url = URL(string: "\(APIConfig.baseURL)/artist/album?id=\(id)&limit=\(limit)&offset=\(offset)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
        let response = try decoder.decode(ArtistAlbumsResponse.self, from: data)
        
        return response.hotAlbums ?? []
    }
    
    // MARK: - 专辑 API
    
    /// 获取专辑详情（带缓存 + 请求去重）
    /// - Parameter id: 专辑ID
    func getAlbumDetail(id: Int) async throws -> (album: AlbumDetail?, songs: [Track]) {
        let cacheKey = "albumDetail_\(id)"
        return try await APICache.shared.deduplicated(cacheKey, ttl: 10 * 60) { [self] in
            guard let url = URL(string: "\(APIConfig.baseURL)/album?id=\(id)") else {
                throw NetworkError.invalidURL
            }
            let (data, _) = try await network.requestWithCookie(url: url, method: "GET")
            let response = try JSONDecoder().decode(AlbumDetailResponse.self, from: data)
            return (response.album, response.songs ?? []) as (album: AlbumDetail?, songs: [Track])
        }
    }
    
    // MARK: - 云端音乐 API
    
    /// 获取歌单歌曲列表（云端）
    /// - Parameter playlistId: 歌单ID
    func getPlaylistTracks(playlistId: Int) async throws -> [CloudTrack] {
        guard let url = URL(string: "\(APIConfig.baseURL)/playlist/detail?id=\(playlistId)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        let response = try JSONDecoder().decode(CloudPlaylistDetailResponse.self, from: data)
        
        return response.playlist?.tracks ?? []
    }
    
    /// 获取专辑歌曲列表（云端）
    /// - Parameter albumId: 专辑ID
    func getAlbumTracks(albumId: Int) async throws -> [CloudTrack] {
        guard let url = URL(string: "\(APIConfig.baseURL)/album?id=\(albumId)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        let response = try JSONDecoder().decode(CloudAlbumDetailResponse.self, from: data)
        
        return response.songs ?? []
    }
    
    // MARK: - 私人FM API
    
    /// 获取私人FM歌曲
    func getPersonalFM() async throws -> [Track] {
        guard let url = URL(string: "\(APIConfig.baseURL)/personal_fm") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        let response = try JSONDecoder().decode(PersonalFMResponse.self, from: data)
        
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取私人FM失败")
        }
        
        return response.data?.map { $0.toTrack() } ?? []
    }
    
    /// 将歌曲丢进FM垃圾桶（不再推荐）
    func fmTrash(id: Int) async throws {
        guard let url = URL(string: "\(APIConfig.baseURL)/fm_trash?id=\(id)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "POST")
        let response = try JSONDecoder().decode(FMTrashResponse.self, from: data)
        
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "操作失败")
        }
    }
    
    // MARK: - 搜索建议 API
    
    /// 获取搜索建议
    func getSearchSuggest(keyword: String) async throws -> SearchSuggestResult? {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let response: SearchSuggestResponse = try await fetch("search/suggest?keywords=\(encoded)")
        return response.result
    }
    
    // MARK: - 云盘 API
    
    /// 获取云盘歌曲列表
    /// - Parameters:
    ///   - limit: 每页数量
    ///   - offset: 偏移量
    func getCloudDisk(limit: Int = 50, offset: Int = 0) async throws -> CloudDiskResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/user/cloud?limit=\(limit)&offset=\(offset)") else {
            throw NetworkError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        return try JSONDecoder().decode(CloudDiskResponse.self, from: data)
    }
}

// MARK: - Apple Music Token 管理器（优化版）
class AppleMusicTokenManager {
    static let shared = AppleMusicTokenManager()

    private var cachedToken: String?
    private var tokenExpiry: Date?
    private var fetchTask: Task<String?, Never>?  // 避免重复请求
    private let session: URLSession
    private var failureCount: Int = 0
    private let maxFailureCount: Int = 3  // 连续失败3次后停止重试
    private var lastFailureTime: Date?

    private init() {
        // 配置合理的超时时间
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15  // 增加到15秒
        config.timeoutIntervalForResource = 30  // 增加到30秒
        self.session = URLSession(configuration: config)
    }

    /// App 启动时预热 Token（静默失败，不影响主流程）
    func warmUp() {
        Task(priority: .background) {
            _ = await getToken()
        }
    }

    /// 重置失败计数（可在网络恢复时调用）
    func resetFailureCount() {
        failureCount = 0
        lastFailureTime = nil
    }

    /// 获取 Token（自动缓存 1 小时，避免重复请求）
    func getToken() async -> String? {
        // 检查缓存是否有效
        if let token = cachedToken,
           let expiry = tokenExpiry,
           Date() < expiry {
            return token
        }

        // 如果连续失败次数过多，暂时停止尝试（指数退避）
        if failureCount >= maxFailureCount {
            let backoffSeconds = min(300.0, pow(2.0, Double(failureCount - maxFailureCount)) * 60)
            if let lastFailure = lastFailureTime,
               Date().timeIntervalSince(lastFailure) < backoffSeconds {
                #if DEBUG
                print(" Apple Music Token 获取暂停（连续失败\(failureCount)次，等待\(Int(backoffSeconds))秒）")
                #endif
                return nil
            } else {
                // 超过退避时间，重置计数器
                failureCount = 0
                lastFailureTime = nil
            }
        }

        // 如果已有请求在进行中，等待它完成
        if let task = fetchTask {
            return await task.value
        }

        // 创建新的请求任务
        let task = Task<String?, Never> {
            return await fetchTokenFromAppleMusic()
        }
        fetchTask = task

        let newToken = await task.value
        fetchTask = nil

        if let token = newToken {
            cachedToken = token
            tokenExpiry = Date().addingTimeInterval(60 * 60) // 缓存 1 小时
            failureCount = 0  // 成功后重置失败计数
        } else {
            failureCount += 1
            lastFailureTime = Date()
        }

        return newToken
    }

    /// 从 Apple Music 网站获取 Token
    private func fetchTokenFromAppleMusic() async -> String? {
        do {
            guard let browseUrl = URL(string: "https://music.apple.com/us/browse") else {
                return nil
            }

            #if DEBUG
            print(" 正在获取 Apple Music Token...")
            #endif
            
            // 创建带 User-Agent 的请求
            var browseRequest = URLRequest(url: browseUrl)
            browseRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            
            let (htmlData, _) = try await session.data(for: browseRequest)
            guard let html = String(data: htmlData, encoding: .utf8) else {
                return nil
            }

            // 从 HTML 中提取 JS 文件路径
            let jsPattern = #"/assets/index[^"'\s]*\.js"#
            guard let jsRegex = try? NSRegularExpression(pattern: jsPattern),
                  let jsMatch = jsRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let jsRange = Range(jsMatch.range, in: html) else {
                #if DEBUG
                print(" 未找到 JS 文件路径")
                #endif
                return nil
            }

            let jsPath = String(html[jsRange])
            let jsUrl = "https://music.apple.com\(jsPath)"

            guard let jsURL = URL(string: jsUrl) else {
                return nil
            }

            var jsRequest = URLRequest(url: jsURL)
            jsRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            
            let (jsData, _) = try await session.data(for: jsRequest)
            guard let jsContent = String(data: jsData, encoding: .utf8) else {
                return nil
            }

            // 用正则提取 JWT
            let tokenPattern = #"eyJhbGciOiJFUzI1Ni[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#
            guard let tokenRegex = try? NSRegularExpression(pattern: tokenPattern),
                  let tokenMatch = tokenRegex.firstMatch(in: jsContent, range: NSRange(jsContent.startIndex..., in: jsContent)),
                  let tokenRange = Range(tokenMatch.range, in: jsContent) else {
                #if DEBUG
                print(" 未找到 Token")
                #endif
                return nil
            }

            let token = String(jsContent[tokenRange])
            #if DEBUG
            print(" 成功获取 Apple Music Token")
            #endif
            return token

        } catch {
            #if DEBUG
            print(" 获取 Apple Music Token 失败: \(error)")
            #endif
            return nil
        }
    }
}
