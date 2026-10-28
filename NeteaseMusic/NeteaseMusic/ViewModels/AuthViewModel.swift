import Foundation
import SwiftUI
import Combine

/// 认证视图模型
@MainActor
class AuthViewModel: ObservableObject {
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentUser: UserProfile?
    
    // 验证码登录相关
    @Published var captchaSent = false
    @Published var captchaCountdown = 0
    private var countdownTimer: Timer?
    
    // 二维码登录相关
    @Published var qrKey: String?
    @Published var qrImage: String?
    @Published var qrStatus: QRStatus = .waiting
    
    enum QRStatus {
        case waiting    // 等待扫码
        case scanned    // 已扫码待确认
        case confirmed  // 已确认
        case expired    // 已过期
    }
    
    private let authService = AuthService.shared
    private let userService = UserService.shared
    private var qrCheckTimer: Timer?
    
    init() {
        // 恢复登录状态
        authService.restoreSession()
        isLoggedIn = authService.isLoggedIn()
    }
    
    /// 手机号密码登录
    func loginWithPhone(phone: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await authService.loginWithPhone(phone: phone, password: password)
            
            if response.code == 200 {
                isLoggedIn = true
                currentUser = response.profile
            } else {
                errorMessage = response.message ?? "登录失败，错误码: \(response.code)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// 验证码登录
    func loginWithCaptcha(phone: String, captcha: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await authService.loginWithCaptcha(phone: phone, captcha: captcha)
            
            if response.code == 200 {
                isLoggedIn = true
                currentUser = response.profile
                // 登录成功后重置状态
                captchaSent = false
                stopCaptchaCountdown()
            } else {
                errorMessage = response.message ?? "登录失败，错误码: \(response.code)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Cookie 登录
    func loginWithCookie(cookie: String) async {
        guard !cookie.isEmpty else {
            errorMessage = "请输入 Cookie"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // 确保 cookie 格式正确
        var formattedCookie = cookie
        if !cookie.contains("MUSIC_U=") {
            // 用户只输入了值，添加前缀
            formattedCookie = "MUSIC_U=\(cookie)"
        }
        
        // 保存 cookie
        authService.setCookie(formattedCookie)
        
        // 验证 cookie 是否有效
        do {
            let response = try await authService.getLoginStatus()
            if let data = response.data, data.code == 200, data.profile != nil {
                isLoggedIn = true
                // 获取完整的用户信息
                await fetchCurrentUser()
            } else {
                errorMessage = "Cookie 无效或已过期"
                authService.setCookie(nil)
            }
        } catch {
            errorMessage = "Cookie 验证失败: \(error.localizedDescription)"
            authService.setCookie(nil)
        }
        
        isLoading = false
    }
    
    /// 发送验证码
    func sendCaptcha(phone: String) async {
        guard !phone.isEmpty else {
            errorMessage = "请输入手机号"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await authService.sendCaptcha(phone: phone)
            
            if response.code == 200 {
                captchaSent = true
                startCaptchaCountdown()
            } else {
                errorMessage = response.message ?? "发送验证码失败"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// 开始验证码倒计时
    private func startCaptchaCountdown() {
        captchaCountdown = 60
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.captchaCountdown > 0 {
                    self.captchaCountdown -= 1
                } else {
                    self.stopCaptchaCountdown()
                }
            }
        }
    }
    
    /// 停止验证码倒计时
    func stopCaptchaCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        captchaCountdown = 0
    }
    
    /// 开始二维码登录
    func startQRLogin() async {
        if isLoggedIn, currentUser != nil { return }
        errorMessage = nil
        qrStatus = .waiting
        qrImage = nil
        stopQRStatusCheck()

        do {
            let key = try await authService.getQRKey()
            qrKey = key
            qrImage = try await authService.createQRCode(key: key)
            startQRStatusCheck()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 从网易云 App 返回后继续轮询同一张码，不重新申请 key
    func resumeQRLoginIfNeeded() async {
        if currentUser != nil { return }
        guard qrStatus != .confirmed else { return }
        if qrKey == nil || qrImage == nil {
            await startQRLogin()
            return
        }
        if qrCheckTimer == nil {
            startQRStatusCheck()
        }
        await checkQRStatus()
        if isLoggedIn || qrStatus == .confirmed {
            return
        }
        if authService.isLoggedIn() {
            await markQRLoginSucceeded()
        }
    }
    
    /// 开始轮询检查二维码状态
    private func startQRStatusCheck() {
        stopQRStatusCheck()
        
        qrCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkQRStatus()
            }
        }
    }
    
    /// 停止轮询
    func stopQRStatusCheck() {
        qrCheckTimer?.invalidate()
        qrCheckTimer = nil
    }
    
    /// 检查二维码状态
    private func checkQRStatus() async {
        guard let key = qrKey, qrStatus != .confirmed else { return }
        if currentUser != nil { return }
        
        do {
            let response = try await authService.checkQRStatus(key: key)
            
            switch response.code {
            case 800:
                if isLoggedIn || qrStatus == .confirmed || authService.isLoggedIn() {
                    await markQRLoginSucceeded()
                } else {
                    qrStatus = .expired
                    stopQRStatusCheck()
                }
            case 801:
                if qrStatus != .waiting {
                    qrStatus = .waiting
                }
            case 802:
                qrStatus = .scanned
            case 803:
                await markQRLoginSucceeded()
            default:
                break
            }
        } catch {
            if authService.isLoggedIn() {
                await markQRLoginSucceeded()
                return
            }
            #if DEBUG
            print("QR check error: \(error)")
            #endif
        }
    }

    private func markQRLoginSucceeded() async {
        qrStatus = .confirmed
        stopQRStatusCheck()
        await fetchCurrentUser()
        if currentUser != nil || authService.isLoggedIn() {
            isLoggedIn = true
        }
    }
    
    /// 获取当前用户信息
    func fetchCurrentUser() async {
        if let status = try? await authService.getLoginStatus() {
            if let profile = status.data?.profile, profile.userId != 0 {
                currentUser = profile
                let uid = status.data?.account?.id ?? profile.userId
                await mergeUserDetail(uid: uid, base: profile)
                return
            }
            if let account = status.data?.account, account.id != 0 {
                if let detail = try? await userService.getUserDetail(uid: account.id),
                   let profile = detail.profile, profile.userId != 0 {
                    currentUser = profile
                    await mergeUserDetail(uid: account.id, base: profile)
                    return
                }
                currentUser = UserProfile(
                    userId: account.id,
                    nickname: account.userName ?? "网易云用户",
                    vipType: account.vipType
                )
                return
            }
        }
        do {
            currentUser = try await userService.getCurrentUserProfile()
        } catch {
            #if DEBUG
            print("Fetch user error: \(error)")
            #endif
        }
    }

    private func mergeUserDetail(uid: Int, base: UserProfile) async {
        guard let detail = try? await userService.getUserDetail(uid: uid),
              let profile = detail.profile else { return }
        currentUser = UserProfile(
            userId: profile.userId,
            nickname: profile.nickname.isEmpty ? base.nickname : profile.nickname,
            avatarUrl: profile.avatarUrl ?? base.avatarUrl,
            backgroundUrl: profile.backgroundUrl ?? base.backgroundUrl,
            signature: profile.signature ?? base.signature,
            gender: profile.gender ?? base.gender,
            birthday: profile.birthday ?? base.birthday,
            city: profile.city ?? base.city,
            province: profile.province ?? base.province,
            followed: profile.followed ?? base.followed,
            followeds: profile.followeds ?? base.followeds,
            follows: profile.follows ?? base.follows,
            playlistCount: profile.playlistCount ?? base.playlistCount,
            eventCount: profile.eventCount ?? base.eventCount,
            vipType: profile.vipType ?? base.vipType,
            level: detail.level ?? profile.level ?? base.level,
            listenSongs: detail.listenSongs ?? profile.listenSongs ?? base.listenSongs
        )
    }
    
    /// 检查登录状态
    func checkLoginStatus() async {
        do {
            let response = try await authService.getLoginStatus()
            if let data = response.data, data.code == 200 {
                isLoggedIn = true
                currentUser = data.profile
            } else {
                isLoggedIn = false
                currentUser = nil
            }
        } catch {
            isLoggedIn = false
        }
    }
    
    /// 退出登录
    func logout() async {
        do {
            try await authService.logout()
        } catch {
            #if DEBUG
            print("Logout error: \(error)")
            #endif
        }
        isLoggedIn = false
        currentUser = nil
        qrKey = nil
        qrImage = nil
        qrStatus = .waiting
        stopQRStatusCheck()
    }
    
    deinit {
        qrCheckTimer?.invalidate()
    }
}
