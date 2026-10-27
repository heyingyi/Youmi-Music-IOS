import Foundation

/// 网络错误
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case serverError(Int, String?)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .noData:
            return "没有返回数据"
        case .decodingError(let error):
            return "数据解析错误: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "服务器错误(\(code)): \(message ?? "未知错误")"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

/// 网络服务
class NetworkService {
    static let shared = NetworkService()
    
    private let session: URLSession
    private var cookie: String?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }
    
    /// 设置 Cookie
    func setCookie(_ cookie: String?) {
        self.cookie = cookie
        if let cookie = cookie, !cookie.isEmpty {
            UserDefaults.standard.set(cookie, forKey: "netease_cookie")
            KumoneMusicClient.shared.importCookieString(cookie)
        } else {
            UserDefaults.standard.removeObject(forKey: "netease_cookie")
            KumoneMusicClient.shared.clearCookies()
        }
    }
    
    /// 获取存储的 Cookie
    func getSavedCookie() -> String? {
        let kumone = KumoneMusicClient.shared.cookieHeaderString()
        if !kumone.isEmpty { return kumone }
        return UserDefaults.standard.string(forKey: "netease_cookie")
    }
    
    /// 加载已存储的 Cookie
    func loadSavedCookie() {
        self.cookie = getSavedCookie()
        if let cookie = self.cookie, !cookie.isEmpty {
            KumoneMusicClient.shared.importCookieString(cookie)
        }
    }
    
    /// GET 请求
    func get<T: Decodable>(endpoint: APIEndpoint) async throws -> T {
        guard let url = endpoint.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 确保加载 Cookie
        let effectiveCookie = cookie ?? getSavedCookie()
        if let cookie = effectiveCookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
            #if DEBUG
            print("GET \(endpoint.path) with cookie: \(cookie.prefix(50))...")
            #endif
        }
        
        return try await performRequest(request)
    }
    
    /// POST 请求
    func post<T: Decodable>(endpoint: APIEndpoint, params: [String: Any]) async throws -> T {
        guard let url = endpoint.url else {
            throw NetworkError.invalidURL
        }
        
        // 将参数添加到 URL query string
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: "\(value)"))
        }
        // 添加时间戳防止缓存
        queryItems.append(URLQueryItem(name: "timestamp", value: "\(Int(Date().timeIntervalSince1970 * 1000))"))
        components.queryItems = queryItems
        
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let cookie = cookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        
        return try await performRequest(request)
    }
    
    /// 执行请求
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.noData
            }
            
            // 打印调试信息
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Response (\(httpResponse.statusCode)): \(jsonString.prefix(500))")
            }
            #endif
            
            let decoder = JSONDecoder()
            do {
                let result = try decoder.decode(T.self, from: data)
                return result
            } catch {
                throw NetworkError.decodingError(error)
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.networkError(error)
        }
    }
    
    /// 带 Cookie 的原始请求（返回 Data）
    func requestWithCookie(url: URL, method: String = "GET", params: [String: Any]? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let effectiveCookie = cookie ?? getSavedCookie()
        if let cookie = effectiveCookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        
        return try await data(for: request)
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let url = request.url, KumoneMusicClient.shared.shouldHandle(url: url) {
            return try await KumoneMusicClient.shared.proxy(url: url)
        }
        return try await session.data(for: request)
    }
}
