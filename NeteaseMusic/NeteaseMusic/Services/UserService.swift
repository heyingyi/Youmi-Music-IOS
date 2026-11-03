import Foundation

/// 用户服务
class UserService {
    static let shared = UserService()
    private let network = NetworkService.shared
    
    private init() {}
    
    /// 获取用户账号信息
    func getUserAccount() async throws -> UserAccountResponse {
        return try await network.get(endpoint: .userAccount)
    }
    
    /// 获取用户详情
    /// - Parameter uid: 用户ID
    func getUserDetail(uid: Int) async throws -> UserDetailResponse {
        return try await network.get(endpoint: .userDetail(uid: uid))
    }
    
    /// 获取当前登录用户的完整资料
    func getCurrentUserProfile() async throws -> UserProfile {
        let accountResponse = try await getUserAccount()
        let account = accountResponse.account
        let fallback = accountResponse.profile

        if let uid = account?.id, uid != 0,
           let detail = try? await getUserDetail(uid: uid),
           let profile = detail.profile, profile.userId != 0 {
            return UserProfile(
                userId: profile.userId,
                nickname: profile.nickname.isEmpty ? (fallback?.nickname ?? profile.nickname) : profile.nickname,
                avatarUrl: profile.avatarUrl ?? fallback?.avatarUrl,
                backgroundUrl: profile.backgroundUrl ?? fallback?.backgroundUrl,
                signature: profile.signature ?? fallback?.signature,
                gender: profile.gender ?? fallback?.gender,
                birthday: profile.birthday ?? fallback?.birthday,
                city: profile.city ?? fallback?.city,
                province: profile.province ?? fallback?.province,
                followed: profile.followed ?? fallback?.followed,
                followeds: profile.followeds ?? fallback?.followeds,
                follows: profile.follows ?? fallback?.follows,
                playlistCount: profile.playlistCount ?? fallback?.playlistCount,
                eventCount: profile.eventCount ?? fallback?.eventCount,
                vipType: profile.vipType ?? fallback?.vipType,
                level: detail.level ?? profile.level ?? fallback?.level,
                listenSongs: detail.listenSongs ?? profile.listenSongs ?? fallback?.listenSongs
            )
        }

        if let fallback, fallback.userId != 0 {
            return fallback
        }
        if let account, account.id != 0 {
            return UserProfile(
                userId: account.id,
                nickname: account.userName ?? "网易云用户",
                vipType: account.vipType
            )
        }
        throw NetworkError.serverError(accountResponse.code, "获取账号信息失败")
    }
    
    // MARK: - 网易云歌单和收藏
    
    /// 获取用户歌单列表
    func getUserPlaylists(uid: Int) async throws -> [CloudPlaylist] {
        let response: UserPlaylistResponse = try await network.get(endpoint: .userPlaylist(uid: uid))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取歌单失败")
        }
        return response.playlist ?? []
    }
    
    /// 获取喜欢的音乐ID列表
    func getLikeList(uid: Int) async throws -> [Int] {
        let response: LikelistResponse = try await network.get(endpoint: .likelist(uid: uid))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取喜欢列表失败")
        }
        return response.ids ?? []
    }
    
    /// 获取收藏的专辑
    func getAlbumSublist() async throws -> [CloudAlbum] {
        let response: AlbumSublistResponse = try await network.get(endpoint: .albumSublist)
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取收藏专辑失败")
        }
        return response.data ?? []
    }
    
    /// 获取订阅的播客
    func getDJSublist() async throws -> [CloudDJRadio] {
        let response: DJSublistResponse = try await network.get(endpoint: .djSublist)
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取播客失败")
        }
        return (response.djRadios ?? []).filter { $0.id != 0 }
    }

    /// 获取自己创建的播客
    func getCreatedDJRadios(uid: Int) async throws -> [CloudDJRadio] {
        let response: DJSublistResponse = try await network.get(endpoint: .djCreated(uid: uid))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取自建播客失败")
        }
        return (response.djRadios ?? []).filter { $0.id != 0 }
    }

    /// 合并订阅与自建播客，自建在前
    func getAllDJRadios(uid: Int) async -> [CloudDJRadio] {
        async let created = getCreatedDJRadios(uid: uid)
        async let subed = getDJSublist()
        let mine = (try? await created) ?? []
        let others = (try? await subed) ?? []
        var seen = Set<Int>()
        var result: [CloudDJRadio] = []
        for radio in mine + others where seen.insert(radio.id).inserted {
            result.append(radio)
        }
        return result
    }

    /// 获取播客节目
    func getDJPrograms(rid: Int) async throws -> [CloudDJProgram] {
        let response: DJProgramListResponse = try await network.get(endpoint: .djProgram(rid: rid))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取节目失败")
        }
        return (response.programs ?? []).filter { $0.id != 0 }
    }

    /// 获取收藏的单集
    func getDJProgramSublist() async throws -> [CloudDJProgram] {
        let response: DJProgramListResponse = try await network.get(endpoint: .djProgramSublist)
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取收藏单集失败")
        }
        return (response.programs ?? []).filter { $0.id != 0 }
    }

    /// 收藏/取消收藏单集
    func subscribeDJProgram(id: Int, sub: Bool) async throws {
        let response: LikeResponse = try await network.get(endpoint: .djProgramSub(id: id, sub: sub))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, sub ? "收藏单集失败" : "取消收藏失败")
        }
    }

    /// 将节目加入自建播客
    func addDJProgram(_ programId: Int, toRadio radioId: Int) async throws {
        let response: LikeResponse = try await network.get(endpoint: .djProgramAdd(radioId: radioId, programId: programId))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "加入播客失败")
        }
    }

    /// 喜欢/取消喜欢歌曲
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - like: true 喜欢，false 取消喜欢
    func likeSong(id: Int, like: Bool) async throws -> Bool {
        let response: LikeResponse = try await network.get(endpoint: .like(id: id, like: like))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, like ? "喜欢失败" : "取消喜欢失败")
        }
        return true
    }
}
