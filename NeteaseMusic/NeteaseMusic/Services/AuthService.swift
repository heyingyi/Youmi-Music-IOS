import Foundation

/// 认证服务
class AuthService {
    static let shared = AuthService()
    private let network = NetworkService.shared

    private init() {}

    // MARK: - 私有辅助方法

    /// 通用 GET 请求（带时间戳和查询参数）
    private func request<T: Decodable>(
        endpoint: APIEndpoint,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        guard let url = endpoint.url else {
            throw NetworkError.invalidURL
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL
        }

        // 添加时间戳防止缓存
        var items = queryItems
        items.append(URLQueryItem(name: "timestamp", value: "\(Int(Date().timeIntervalSince1970 * 1000))"))
        components.queryItems = items

        guard let finalURL = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"

        let (data, _) = try await network.requestWithCookie(url: finalURL, method: "GET")
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - 手机号登录

    /// 手机号密码登录
    func loginWithPhone(phone: String, password: String) async throws -> LoginResponse {
        let params: [String: Any] = [
            "phone": phone,
            "password": password
        ]

        let response: LoginResponse = try await network.post(endpoint: .loginCellphone, params: params)

        if response.code == 200, let cookie = response.cookie {
            network.setCookie(cookie)
        }

        return response
    }

    /// 手机号验证码登录
    func loginWithCaptcha(phone: String, captcha: String) async throws -> LoginResponse {
        let params: [String: Any] = [
            "phone": phone,
            "captcha": captcha
        ]

        let response: LoginResponse = try await network.post(endpoint: .loginCellphone, params: params)

        if response.code == 200, let cookie = response.cookie {
            network.setCookie(cookie)
        }

        return response
    }

    /// 发送验证码
    func sendCaptcha(phone: String) async throws -> CaptchaSentResponse {
        let params: [String: Any] = ["phone": phone]
        return try await network.post(endpoint: .captchaSent, params: params)
    }

    /// 验证验证码是否正确
    func verifyCaptcha(phone: String, captcha: String) async throws -> CaptchaVerifyResponse {
        let params: [String: Any] = [
            "phone": phone,
            "captcha": captcha
        ]
        return try await network.post(endpoint: .captchaVerify, params: params)
    }

    // MARK: - 二维码登录

    /// 获取二维码 Key
    func getQRKey() async throws -> String {
        let response: QRKeyResponse = try await request(endpoint: .loginQRKey)

        guard response.code == 200, let unikey = response.data?.unikey else {
            throw NetworkError.serverError(response.code, "获取二维码Key失败")
        }
        return unikey
    }

    /// 生成二维码
    func createQRCode(key: String) async throws -> String {
        let response: QRCreateResponse = try await request(
            endpoint: .loginQRCreate,
            queryItems: [
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "qrimg", value: "true")
            ]
        )

        if let qrimg = response.data?.qrimg {
            return qrimg
        } else if let qrurl = response.data?.qrurl {
            return qrurl
        }

        throw NetworkError.serverError(response.code, "生成二维码失败")
    }

    /// 检查二维码扫码状态
    /// 返回码: 800-二维码过期, 801-等待扫码, 802-待确认, 803-登录成功
    func checkQRStatus(key: String) async throws -> QRCheckResponse {
        let response: QRCheckResponse = try await request(
            endpoint: .loginQRCheck,
            queryItems: [
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "noCookie", value: "true")
            ]
        )

        // 803 表示登录成功
        if response.code == 803, let cookie = response.cookie {
            network.setCookie(cookie)
        }

        return response
    }

    // MARK: - 登录状态管理

    /// 获取登录状态
    func getLoginStatus() async throws -> LoginStatusResponse {
        return try await network.get(endpoint: .loginStatus)
    }

    /// 退出登录
    func logout() async throws {
        let _: LogoutResponse = try await network.get(endpoint: .logout)
        network.setCookie(nil)
    }

    /// 检查是否已登录
    func isLoggedIn() -> Bool {
        return KumoneMusicClient.shared.hasLoginCookie() || network.getSavedCookie() != nil
    }

    /// 恢复登录状态
    func restoreSession() {
        network.loadSavedCookie()
    }

    /// 设置 Cookie
    func setCookie(_ cookie: String?) {
        network.setCookie(cookie)
    }
}
