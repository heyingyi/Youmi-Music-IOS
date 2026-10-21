import Foundation

/// 音质选项
enum MusicQuality: String, CaseIterable, Identifiable {
    case standard = "standard"      // 标准音质
    case exhigh = "exhigh"          // 极高音质
    case lossless = "lossless"      // 无损音质
    case hires = "hires"            // Hi-Res
    case jyeffect = "jyeffect"      // 高清环绕声
    case sky = "sky"                // 沉浸环绕声 (SVIP)
    case jymaster = "jymaster"      // 超清母带 (SVIP)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "标准音质"
        case .exhigh: return "极高音质"
        case .lossless: return "无损音质"
        case .hires: return "Hi-Res"
        case .jyeffect: return "高清环绕声"
        case .sky: return "沉浸环绕声"
        case .jymaster: return "超清母带"
        }
    }

    var shortName: String {
        switch self {
        case .standard: return "标准"
        case .exhigh: return "HQ"
        case .lossless: return "无损"
        case .hires: return "Hi-Res"
        case .jyeffect: return "环绕"
        case .sky: return "沉浸"
        case .jymaster: return "母带"
        }
    }

    /// 52 API 使用的比特率参数
    var bitrateForAPI: String {
        switch self {
        case .standard: return "standard"      // 128kbps
        case .exhigh: return "exhigh"          // 320kbps
        case .lossless: return "lossless"      // 无损 FLAC
        case .hires: return "hires"            // Hi-Res (需VIP)
        case .jyeffect: return "jyeffect"      // 高清环绕声 (需VIP)
        case .sky: return "sky"                // 沉浸环绕声 (需SVIP)
        case .jymaster: return "jymaster"      // 超清母带 (需SVIP)
        }
    }
}

/// 音源配置管理器
class MusicSourceConfig: ObservableObject {
    static let shared = MusicSourceConfig()
    
    private let userDefaults = UserDefaults.standard
    
    // UserDefaults Keys
    private enum Keys {
        static let apiKey = "music_api_key"
        static let cookie = "music_cookie"
        static let quality = "music_quality"
    }
    
    // 兼容旧播放地址字段；实际取流由 KumoneMusicClient 直连网易云
    let neteaseApiURL = "https://youmimusicapi.preview.aliyun-zeabur.cn/song/url"
    
    /// API Key
    @Published var apiKey: String {
        didSet {
            userDefaults.set(apiKey, forKey: Keys.apiKey)
        }
    }
    
    /// 网易云 Cookie (Base64 编码后存储)
    @Published var cookieBase64: String {
        didSet {
            userDefaults.set(cookieBase64, forKey: Keys.cookie)
        }
    }
    
    /// 音质变化回调
    var onQualityChanged: (() -> Void)?
    
    /// 网易云音质
    @Published var quality: MusicQuality {
        didSet {
            userDefaults.set(quality.rawValue, forKey: Keys.quality)
            onQualityChanged?()
        }
    }
    
    /// API URL
    var apiURL: String {
        return neteaseApiURL
    }
    
    private init() {
        // 默认 API Key
        let defaultKey = "53yicjE0pkNddTUKIVaRhtXpaB"
        
        // 默认 Cookie (Base64 编码)
        let defaultCookie = "X2l1cXhsZG16cl89MzI7IF9udGVzX25uaWQ9ZWFjMGM2NGFhNmQ4ZjkzZjZlZThiOTQ1ZjA1Y2Y0ZTYsMTc2OTAwNzQxMDYzMjsgX250ZXNfbnVpZD1lYWMwYzY0YWE2ZDhmOTNmNmVlOGI5NDVmMDVjZjRlNjsgTk1USUQ9MDBPVzlfU2s3dF9PNHRRbWthRmxqTVp6LU5qR19nQUFBR2I0UTd1MFE7IFdFVk5TTT0xLjAuMDsgV05NQ0lEPWhnaGN1Zy4xNzY5MDA3NDEzMDA5LjAxLjA7IHNEZXZpY2VJZD1ZRC1wNXJZTm1oeVBrSkVCMEJVUVVmSDM3d0NVTHBYSnpLZDsgTVVTSUNfVT0wMEE2MTkxQjE1NTZDQzQ0MzY5QjM2MUYzNkIzNjAzNEYyNTIzNjlGRTk2OEJGNzZGMEI1MjBBRTQ2RUUxOUQ1MjAzQTQ0RjFCNDA5NjA0OEU3OEM3QjVCMzZBQUI3QzdCMzBDMERERTE1NDAwMkVDNzMzRkQ2MTZDQjFEOTBCN0RBOUFBQzcyMjk2QUQzNkMwNjYzQzdBOEUzOTIxODY4MDZBQ0U0NkI5QUI1MUNFNzVFRkMwNUMwRUUwOUU4MDJGRkQ0RDBGNzVCMjQyRDNDOEQ5QkNERTk0NkIyNjUwREZDQUMzRUNCRDY1MzU1RDUzMEE2Q0MwMUY2RjRGN0NDMTQ4MTM0QjgzOTczRDI5OTRDQTk1ODM3NEM1MjMwMTM4QTJCQkI0Q0E1MTNCMURBODJBOTE1NDkzMTNBM0ZDMjNFOUVBMTM0ODJCMEEzMkFDM0EyMzhCMkVBODlBMDkwRDY4RERDMkIwQkQxRUYwNjNFMEY4QUIzRTQ0M0IzMzc3N0U2MkNGOTMzRTFCMUI3NEFGQ0NCMjYxMjc1NkNGNEEzRkJCNEUxRTU4RDZENjA5NDIyRUQ0QzBFNDQ5Nzc0OUIzRjM1NjA2OTA5NjIxQUQ2RUI0MjlDQ0Y0RDhFMTcwODM3QUUwQzMyQzY4N0RBMkIzNEIzNUE1RkRDRTU5QTRCNzc0NzMwQjYwN0ExMzYyNDUzQ0E2NkMzNjVGRjdFNERFNzVFMEQzMjY2QzhFODZFOTE0NDgzNURCMEI4RTA0MERCRENFNTkwNjY2OUYwRjA4NDQ1NkYwODZDMjVGRkVCQ0EzRDJFNzEzRDNBQTEzRjVBQ0Q2MEREMTM1RkNEOTkyM0EwMTkwNjlDRTM4NTcxRkZBRUFBN0IyQjZFNzM5QTE4NEJGNjJCMTBDNjhDOUVDNkMzRjI5NEE3RTMwQzlFNzAyODRDNDI2NUQ2NDVBOEJBN0UwRjEyRUI1ODM5RjI1QUI5M0E5QURBNDE4NkJFQTRCQjcyRjNCQTRBRjRGMjU5MkIxNDIxRkYxMzVBQjFGNTZENkFBN0QyNjVCQjEwOyBfX2NzcmY9ZWVhYjYyYzZhNTkxOTk4YWNmZmMzMDliNTk1ZDM2YzE7IG50ZXNfa2FvbGFfYWQ9MQ=="
        
        self.apiKey = userDefaults.string(forKey: Keys.apiKey) ?? defaultKey
        self.cookieBase64 = userDefaults.string(forKey: Keys.cookie) ?? defaultCookie
        
        // 默认网易云音质：无损
        if let qualityStr = userDefaults.string(forKey: Keys.quality),
           let quality = MusicQuality(rawValue: qualityStr) {
            self.quality = quality
        } else {
            self.quality = .lossless
        }
    }
    
    /// 重置为默认值
    func resetToDefaults() {
        apiKey = "53yicjE0pkNddTUKIVaRhtXpaB"
        quality = .lossless
    }
}
