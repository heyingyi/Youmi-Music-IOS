import Foundation

/// API 配置
struct APIConfig {
    /// 兼容旧的 NeteaseCloudMusicApi 路径前缀。
    /// 实际请求由 KumoneMusicClient 用 kumone weapi/eapi 直连 music.163.com。
    static var baseURL: String = "https://youmimusicapi.preview.aliyun-zeabur.cn"
    
    /// 设置自定义服务器地址
    static func setBaseURL(_ url: String) {
        baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
    }
}

/// API 端点
enum APIEndpoint {
    // 登录相关
    case loginCellphone              // 手机号登录
    case loginQRKey                  // 获取二维码 key
    case loginQRCreate               // 生成二维码
    case loginQRCheck                // 检查二维码扫码状态
    case loginStatus                 // 登录状态
    case logout                      // 退出登录
    case captchaSent                 // 发送验证码
    case captchaVerify               // 验证验证码
    
    // 用户相关
    case userAccount                 // 获取账号信息
    case userDetail(uid: Int)        // 获取用户详情
    case userPlaylist(uid: Int)      // 获取用户歌单
    case likelist(uid: Int)          // 获取喜欢的音乐ID列表
    case like(id: Int, like: Bool)   // 喜欢/取消喜欢歌曲
    case albumSublist                // 获取收藏的专辑
    case playlistDetail(id: Int)     // 获取歌单详情

    var path: String {
        switch self {
        case .loginCellphone:
            return "/login/cellphone"
        case .loginQRKey:
            return "/login/qr/key"
        case .loginQRCreate:
            return "/login/qr/create"
        case .loginQRCheck:
            return "/login/qr/check"
        case .loginStatus:
            return "/login/status"
        case .logout:
            return "/logout"
        case .captchaSent:
            return "/captcha/sent"
        case .captchaVerify:
            return "/captcha/verify"
        case .userAccount:
            return "/user/account"
        case .userDetail(let uid):
            return "/user/detail?uid=\(uid)"
        case .userPlaylist(let uid):
            return "/user/playlist?uid=\(uid)"
        case .likelist(let uid):
            return "/likelist?uid=\(uid)"
        case .like(let id, let like):
            return "/like?id=\(id)&like=\(like)"
        case .albumSublist:
            return "/album/sublist"
        case .playlistDetail(let id):
            return "/playlist/detail?id=\(id)"
        }
    }
    
    var url: URL? {
        return URL(string: APIConfig.baseURL + path)
    }
}
