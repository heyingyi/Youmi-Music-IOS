import SwiftUI
import WebKit

@main
struct NeteaseMusicApp: App {
    init() {
        // 配置 API 服务器地址
        APIConfig.setBaseURL("https://youmimusicapi.preview.aliyun-zeabur.cn")
        // 预热网络连接（避免首次请求卡顿）
        MusicService.shared.warmup()
        // 预热 WebView（在后台启动 WebKit 进程，避免首次使用时 3-7 秒的冷启动延迟）
        Self.startWebViewWarmup()
        // 预热 Apple Music Token（后台获取，避免首次加载动态封面时等待）
        AppleMusicTokenManager.shared.warmUp()
        // 请求通知权限并记录打开时间
        NotificationService.shared.requestAuthorization()
        NotificationService.shared.recordAppOpen()
    }

    @StateObject private var themeManager = ThemeManager.shared

    /// 预热 WebView - 在 App 启动时提前启动 WebKit 进程
    private static func startWebViewWarmup() {
        DispatchQueue.main.async {
            // 触发 WebViewPool 的预热（会创建 WebView 并保持在池中）
            WebViewPool.shared.warmUp()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(themeManager)
        }
    }
}

// MARK: - App 根视图（用于响应主题切换）
struct AppRootView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var authViewModel = AuthViewModel()
    @State private var showSplash = true
    
    // 颜倒世界主题强制使用深色模式，否则文字会看不见
    private var effectiveColorScheme: ColorScheme? {
        if themeManager.themeStyle == .strangerThings {
            return .dark
        }
        return themeManager.appearanceMode.colorScheme
    }
    
    var body: some View {
        ZStack {
            MainTabView()
                .environmentObject(authViewModel)
                .preferredColorScheme(effectiveColorScheme)
                .id("\(themeManager.appearanceMode)-\(themeManager.themeStyle)")  // 响应主题和外观变化
            
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            // 1.5秒后隐藏启动页
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}

// MARK: - 启动页
struct SplashView: View {
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Image("SplashBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.2),
                    Color.black.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Logo
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color.red.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.red.opacity(0.4), radius: 20)

                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(.white)
                }

                // 应用名称
                VStack(spacing: 8) {
                    Text("Youmi Music")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("发现美妙音乐")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .opacity(opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 1.0
            }
        }
    }
}
