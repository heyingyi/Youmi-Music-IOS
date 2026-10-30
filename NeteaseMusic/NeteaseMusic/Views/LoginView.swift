import SwiftUI

// MARK: - 触觉反馈工具类
enum HapticFeedback {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    static func light() {
        lightGenerator.impactOccurred()
    }

    static func medium() {
        mediumGenerator.impactOccurred()
    }
}

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showMainView = false
    @State private var animateGradient = false
    @State private var showContent = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 动态渐变背景
                animatedBackground
                
                // 主内容
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: geometry.size.height * 0.08)
                        
                        // Logo 区域
                        logoSection
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : -30)
                        
                        Spacer(minLength: 40)
                        
                        // 登录卡片
                        loginCard
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 30)
                        
                        Spacer(minLength: 30)
                        
                        // 跳过登录
                        skipButton
                            .opacity(showContent ? 1 : 0)
                        
                        Spacer(minLength: geometry.safeAreaInsets.bottom + 20)
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.2)) {
                showContent = true
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { authViewModel.isLoggedIn || showMainView },
            set: { _ in }
        )) {
            MainTabView()
                .environmentObject(authViewModel)
        }
    }
    
    // MARK: - 动态渐变背景
    @ViewBuilder
    private var animatedBackground: some View {
        if themeManager.showsCustomWallpaper {
            CustomWallpaperLayer()
        } else {
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.1, green: 0.05, blue: 0.15), Color(red: 0.05, green: 0.02, blue: 0.1)]
                        : [Color(red: 1, green: 0.95, blue: 0.97), Color(red: 0.98, green: 0.94, blue: 0.96)],
                    startPoint: animateGradient ? .topLeading : .bottomLeading,
                    endPoint: animateGradient ? .bottomTrailing : .topTrailing
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red.opacity(0.3), Color.red.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: animateGradient ? 100 : -100, y: animateGradient ? -200 : -150)
                    .blur(radius: 60)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.pink.opacity(0.25), Color.pink.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .offset(x: animateGradient ? -80 : 80, y: animateGradient ? 300 : 350)
                    .blur(radius: 50)
            }
        }
    }
    
    // MARK: - Logo 区域
    private var logoSection: some View {
        VStack(spacing: 16) {
            // 音符动画 Logo
            ZStack {
                // 光晕背景
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red.opacity(0.4), Color.red.opacity(0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 20)
                
                // Logo 圆形背景
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.red.opacity(0.5), radius: 20, y: 10)
                
                Image(systemName: "music.note")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // App 名称
            Text("网易云音乐")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("畅享音乐，尽在指尖")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 登录卡片
    private var loginCard: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 8) {
                 Text("欢迎登录")
                     .font(.title2)
                     .fontWeight(.bold)
                 
                            Text("扫码、验证码或 Cookie 登录网易云账号")
                     .font(.subheadline)
                     .foregroundColor(.secondary)
             }
             
             KumoneLoginPanel(viewModel: authViewModel)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.2 : 0.8),
                                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.1), radius: 30, y: 15)
        )
        .padding(.horizontal, 24)
    }
    
    // MARK: - 跳过按钮
    private var skipButton: some View {
        Button(action: {
            HapticFeedback.light()
            showMainView = true
        }) {
            HStack(spacing: 6) {
                Text("暂不登录，先看看")
                Image(systemName: "arrow.right")
                    .font(.caption)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - 二维码图片视图
struct QRCodeImageView: View {
    let qrImage: String

    var body: some View {
        Group {
            if qrImage.hasPrefix("data:image"),
               let uiImage = decodeBase64Image(qrImage) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                AsyncImage(url: URL(string: qrImage)) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
            }
        }
        .frame(width: 200, height: 200)
    }

    private func decodeBase64Image(_ base64String: String) -> UIImage? {
        let base64Data = base64String.replacingOccurrences(of: "data:image/png;base64,", with: "")
        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return UIImage(data: data)
    }
}

private enum KumoneLoginMode: String, CaseIterable, Identifiable {
    case qr = "扫码登录"
    case sms = "手机验证码"
    case cookie = "Cookie"

    var id: String { rawValue }
}

struct KumoneLoginPanel: View {
    @ObservedObject var viewModel: AuthViewModel
    var onSuccess: (() -> Void)? = nil
    @State private var mode: KumoneLoginMode = .qr
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Picker("", selection: $mode) {
                ForEach(KumoneLoginMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .qr:
                QRLoginForm(viewModel: viewModel, onSuccess: onSuccess)
            case .sms:
                CaptchaLoginForm(viewModel: viewModel, onSuccess: onSuccess)
            case .cookie:
                ModernCookieLoginForm(viewModel: viewModel, onSuccess: onSuccess)
            }
        }
        .onChangeCompat(of: mode) { _, newMode in
            if newMode == .qr {
                Task { await viewModel.startQRLogin() }
            } else {
                viewModel.stopQRStatusCheck()
            }
        }
        .onChangeCompat(of: viewModel.currentUser) { _, user in
            if user != nil {
                onSuccess?()
            }
        }
    }
}

struct QRLoginForm: View {
    @ObservedObject var viewModel: AuthViewModel
    var onSuccess: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Text("使用网易云音乐 App 扫码登录")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 220, height: 220)
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)

                if let qrImage = viewModel.qrImage {
                    QRCodeImageView(qrImage: qrImage)
                        .frame(width: 188, height: 188)
                        .blur(radius: overlayVisible ? 3 : 0)
                } else {
                    ProgressView()
                }

                if overlayVisible {
                    VStack(spacing: 10) {
                        switch viewModel.qrStatus {
                        case .expired:
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.red)
                            Text("二维码已失效")
                                .font(.system(size: 13, weight: .medium))
                            Button("刷新") {
                                Task { await viewModel.startQRLogin() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                        case .scanned:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.green)
                            Text("已扫码")
                                .font(.system(size: 13, weight: .semibold))
                            Text("请在手机上确认")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        default:
                            EmptyView()
                        }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            Group {
                switch viewModel.qrStatus {
                case .waiting:
                    Text(viewModel.qrImage == nil ? "正在获取二维码…" : "打开网易云音乐 App，扫一扫登录")
                case .scanned:
                    Text("等待手机确认…")
                case .authorizing:
                    Text("正在获取资料…")
                case .expired:
                    Text("二维码已失效，请刷新")
                case .confirmed:
                    Text("登录成功")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if let error = viewModel.errorMessage, viewModel.qrStatus != .confirmed {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Text("只有一台设备时，可截图二维码，到网易云音乐 App 扫一扫里选择相册识别")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .task {
            await viewModel.startQRLogin()
        }
        .onDisappear {
            if viewModel.currentUser == nil,
               viewModel.qrStatus != .confirmed,
               viewModel.qrStatus != .authorizing {
                viewModel.stopQRStatusCheck()
            }
        }
        .onChangeCompat(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.resumeQRLoginIfNeeded() }
        }
        .onChangeCompat(of: viewModel.currentUser) { _, user in
            if user != nil {
                onSuccess?()
            }
        }
    }

    private var overlayVisible: Bool {
        viewModel.qrStatus == .expired || viewModel.qrStatus == .scanned
    }
}

// MARK: - 动画输入框
struct AnimatedInputField: View {
    let placeholder: String
    let icon: String
    @Binding var text: String
    var isSecure: Bool = false
    
    @FocusState private var isFocused: Bool
    
    private var shouldFloat: Bool {
        isFocused || !text.isEmpty
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.red : Color.clear, lineWidth: 2)
                )
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(isFocused ? .red : .gray)
                    .frame(width: 20)
                
                ZStack(alignment: .leading) {
                    Text(placeholder)
                        .foregroundColor(shouldFloat ? .red : .gray)
                        .font(shouldFloat ? .caption : .body)
                        .offset(y: shouldFloat ? -12 : 0)
                    
                    if isSecure {
                        SecureField("", text: $text)
                            .focused($isFocused)
                            .offset(y: shouldFloat ? 6 : 0)
                    } else {
                        TextField("", text: $text)
                            .keyboardType(.phonePad)
                            .focused($isFocused)
                            .offset(y: shouldFloat ? 6 : 0)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 56)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onTapGesture {
            isFocused = true
        }
    }
}

// MARK: - 旧版底部导航栏 (iOS 26 以下)
struct LegacyCustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var isSearchMode: Bool
    var animation: Namespace.ID
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showPlayer = false
    @State private var showMoodRecommend = false

    // iPad 适配
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // Tab 配置数据
    private static let tabItems: [(icon: String, title: String)] = [
        ("house.fill", "主页"),
        ("square.grid.2x2", "新发现"),
        ("apple.logo", "Apple"),
        ("person.fill", "我的")
    ]
    
    // 主题颜色
    private var tabColors: ThemedTabColors {
        ThemedTabColors(themeStyle: themeManager.themeStyle)
    }

    var body: some View {
        VStack(spacing: 0) {
            // MiniPlayer 独立组件，避免 AudioPlayer 状态变化影响整个 TabBar
            MiniPlayerContainer(showPlayer: $showPlayer, isIPad: isIPad)

            // 底部 Tab 栏 - 完全静态，不依赖 AudioPlayer
            tabBarContent
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
        .fullScreenCover(isPresented: $showMoodRecommend) {
            MoodRecommendView()
        }
    }

    // MARK: - Tab 栏内容
    private var tabBarContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(Self.tabItems.enumerated()), id: \.offset) { index, item in
                    ThemedTabButton(
                        icon: item.icon,
                        title: item.title,
                        isSelected: selectedTab == index,
                        isIPad: isIPad,
                        tabColors: tabColors
                    ) {
                        selectTab(index)
                    }
                }
            }
            .frame(maxWidth: isIPad ? 400 : .infinity)
            .padding(.leading, isIPad ? 0 : 16)
            .padding(.vertical, isIPad ? 10 : 8)
            .background(
                ThemedTabBarBackground(cornerRadius: 32)
            )

            // 深夜电台按钮 - 移除永久动画，改用静态渐变
            Button(action: {
                HapticFeedback.medium()
                showMoodRecommend = true
            }) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    themeManager.themeStyle == .strangerThings 
                                        ? Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.3)
                                        : Color.purple.opacity(0.3),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: isIPad ? 32 : 28
                            )
                        )
                        .frame(width: isIPad ? 64 : 56, height: isIPad ? 64 : 56)

                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: isIPad ? 22 : 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: themeManager.themeStyle == .strangerThings
                                    ? [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 1.0)]
                                    : [Color.purple.opacity(0.9), Color.indigo.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isIPad ? 64 : 56, height: isIPad ? 64 : 56)
                }
            }
            .background(
                ThemedCircleBackground()
            )
            .buttonStyle(LiquidButtonStyle())
            .padding(.leading, isIPad ? 12 : 8)

            // 搜索按钮（悬浮圆形）
            Button(action: {
                HapticFeedback.light()
                isSearchMode = true
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: isIPad ? 22 : 20, weight: .medium))
                    .foregroundColor(tabColors.unselectedColor)
                    .frame(width: isIPad ? 64 : 56, height: isIPad ? 64 : 56)
            }
            .background(
                ThemedCircleBackground()
            )
            .buttonStyle(LiquidButtonStyle())
            .padding(.leading, isIPad ? 12 : 8)
        }
        .frame(maxWidth: isIPad ? 650 : .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, isIPad ? 8 : 4)
    }

    private func selectTab(_ index: Int) {
        HapticFeedback.light()
        selectedTab = index
    }
}

// MARK: - 主题感知 Tab 按钮 (旧版)
struct ThemedTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var isIPad: Bool = false
    let tabColors: ThemedTabColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: isIPad ? 6 : 4) {
                Image(systemName: icon)
                    .font(.system(size: isIPad ? 24 : 22, weight: .medium))
                    .foregroundColor(isSelected ? tabColors.selectedColor : tabColors.unselectedColor)
                    // 只对图标颜色变化添加动画
                    .animation(.easeOut(duration: 0.15), value: isSelected)

                Text(title)
                    .font(.system(size: isIPad ? 11 : 10, weight: .medium))
                    .foregroundColor(isSelected ? tabColors.selectedColor : tabColors.secondaryColor)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .padding(.vertical, isIPad ? 6 : 4)
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - Apple Music 风格 Tab 按钮（保留兼容）
struct AppleMusicTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var isIPad: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: isIPad ? 6 : 4) {
                Image(systemName: icon)
                    .font(.system(size: isIPad ? 24 : 22, weight: .medium))
                    .foregroundColor(isSelected ? .red : .primary)

                Text(title)
                    .font(.system(size: isIPad ? 11 : 10, weight: .medium))
                    .foregroundColor(isSelected ? .red : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isIPad ? 6 : 4)
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - 增强版液态玻璃背景（圆角矩形）
struct EnhancedLiquidGlassBackground: View {
    var cornerRadius: CGFloat = 32
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // 层 1: 模糊材质
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
            
            // 层 2: 半透明背景
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.1).opacity(0.7)
                        : Color(white: 0.98).opacity(0.75)
                )
            
            // 层 3: 顶部高光渐变
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.18), Color.white.opacity(0.03), .clear]
                            : [Color.white.opacity(0.9), Color.white.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .mask(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
                )
            
            // 层 4: 边缘高光描边
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.4), Color.white.opacity(0.12), Color.white.opacity(0.05)]
                            : [Color.white.opacity(1.0), Color.white.opacity(0.6), Color.white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // 层 5: 内边框发光
            RoundedRectangle(cornerRadius: cornerRadius - 1.5)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.06)
                        : Color.white.opacity(0.35),
                    lineWidth: 0.5
                )
                .padding(1.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 25, x: 0, y: 12)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 10, x: 0, y: 5)
    }
}

// MARK: - 增强版液态玻璃背景（圆形）
struct EnhancedLiquidGlassCircleBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // 模糊材质
            Circle()
                .fill(.ultraThinMaterial)
            
            // 半透明背景
            Circle()
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.1).opacity(0.7)
                        : Color(white: 0.98).opacity(0.75)
                )
            
            // 顶部高光
            Circle()
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.25), .clear]
                            : [Color.white.opacity(0.9), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            // 边缘高光
            Circle()
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.4), Color.white.opacity(0.1)]
                            : [Color.white.opacity(1.0), Color.white.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // 内发光
            Circle()
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.06)
                        : Color.white.opacity(0.3),
                    lineWidth: 0.5
                )
                .padding(1.5)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 15, x: 0, y: 8)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 5, x: 0, y: 3)
    }
}

// MARK: - MiniPlayer 容器（隔离 AudioPlayer 订阅）
/// 关键优化：只订阅 currentTrack 的变化，不订阅整个 AudioPlayer
private struct MiniPlayerContainer: View {
    @Binding var showPlayer: Bool
    let isIPad: Bool
    
    // 只订阅是否有歌曲在播放
    @State private var hasTrack: Bool = false
    
    var body: some View {
        Group {
            if hasTrack {
                MiniPlayerBar(showPlayer: $showPlayer)
                    .frame(maxWidth: isIPad ? 600 : .infinity)
            }
        }
        .onReceive(AudioPlayer.shared.$currentTrack.map { $0 != nil }.removeDuplicates()) { has in
            hasTrack = has
        }
    }
}

// MARK: - 迷你播放器条
struct MiniPlayerBar: View {
    @Binding var showPlayer: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    // 只订阅需要的属性，避免不必要的重绘
    @State private var currentTrack: Track?
    @State private var isPlaying: Bool = false
    
    private var textColor: Color {
        themeManager.themeStyle == .strangerThings ? .white : .primary
    }
    
    private var secondaryTextColor: Color {
        themeManager.themeStyle == .strangerThings ? .white.opacity(0.6) : .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            // 封面和歌曲信息区域 - 使用 Button 确保点击可靠
            Button {
                HapticFeedback.light()
                showPlayer = true
            } label: {
                HStack(spacing: 10) {
                    // 封面
                    miniPlayerCover
                    
                    // 歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentTrack?.name ?? "未播放")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(textColor)
                            .lineLimit(1)
                        
                        Text(currentTrack?.artistName ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MiniPlayerTapStyle())
            
            // 播放按钮
            Button {
                HapticFeedback.light()
                AudioPlayer.shared.togglePlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(textColor)
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MiniPlayerTapStyle())
            
            // 下一首按钮
            Button {
                HapticFeedback.light()
                AudioPlayer.shared.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(textColor)
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MiniPlayerTapStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 72)
        .background(miniPlayerBackground)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onReceive(AudioPlayer.shared.$currentTrack.removeDuplicates(by: { lhs, rhs in
            lhs?.id == rhs?.id && lhs?.coverUrl == rhs?.coverUrl
        })) { track in
            currentTrack = track
        }
        .onReceive(AudioPlayer.shared.$isPlaying.removeDuplicates()) { playing in
            isPlaying = playing
        }
    }
    
    // MARK: - 封面视图
    @ViewBuilder
    private var miniPlayerCover: some View {
        Group {
            if let coverUrl = currentTrack?.coverUrl,
               let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    coverPlaceholder
                }
                .id(coverUrl)
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    themeManager.themeStyle == .strangerThings
                        ? Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.5)
                        : Color.white.opacity(colorScheme == .dark ? 0.15 : 0.3),
                    lineWidth: 0.5
                )
        )
    }
    
    private var coverPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            )
    }
    
    @ViewBuilder
    private var miniPlayerBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular)
                .allowsHitTesting(false)
        } else {
            ThemedCapsuleMiniPlayerBackground()
        }
    }
}

// MARK: - 迷你播放器按钮样式
private struct MiniPlayerTapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 迷你播放器控制按钮样式
struct MiniPlayerControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 首页按钮（支持长按弹出搜索）
struct LiquidGlassHomeButtonWithSearch: View {
    let isSelected: Bool
    @Binding var showSearchPopup: Bool
    let action: () -> Void
    let onSearchTap: () -> Void
    
    var body: some View {
        ZStack(alignment: .top) {
            // 搜索弹窗
            if showSearchPopup {
                SearchPopupButton(onTap: onSearchTap)
                    .offset(y: -60)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.5, anchor: .bottom).combined(with: .opacity)
                    ))
            }
            
            // 首页按钮
            Button(action: {
                HapticFeedback.light()
                action()
            }) {
                Image(systemName: isSelected ? "house.fill" : "house")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 52, height: 52)
                    .liquidGlassCircle()
            }
            .buttonStyle(LiquidButtonStyle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        HapticFeedback.medium()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showSearchPopup.toggle()
                        }
                    }
            )
        }
    }
}

// MARK: - 搜索弹窗按钮
struct SearchPopupButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticFeedback.light()
            onTap()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                Text("搜索")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlassCapsule()
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - 紧凑版搜索框
struct LiquidGlassSearchBarCompact: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("搜索")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .liquidGlassCapsule()
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - 导航按钮
struct LiquidGlassNavButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isSelected ? .pink : .primary)
                .frame(width: 46, height: 46)
                .liquidGlassCircle()
        }
        .buttonStyle(LiquidButtonStyle())
    }
}

// MARK: - 液体玻璃按钮样式
struct LiquidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 缩放按钮样式
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 共享登录表单组件
struct LoginForm: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var phone = ""
    @State private var password = ""
    var onSuccess: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            // 手机号输入
            AnimatedInputField(
                placeholder: "手机号",
                icon: "phone",
                text: $phone
            )
            .padding(.horizontal, 30)
            
            // 密码输入
            AnimatedInputField(
                placeholder: "密码",
                icon: "lock",
                text: $password,
                isSecure: true
            )
            .padding(.horizontal, 30)
            
            // 错误信息
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 30)
            }
            
            // 登录按钮
            Button(action: {
                Task {
                    await viewModel.loginWithPhone(phone: phone, password: password)
                    if viewModel.isLoggedIn {
                        onSuccess?()
                    }
                }
            }) {
                ZStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("登录")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(27)
                .shadow(color: Color.red.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
            .disabled(phone.isEmpty || password.isEmpty || viewModel.isLoading)
            .opacity(phone.isEmpty || password.isEmpty ? 0.6 : 1)
            .scaleEffect(viewModel.isLoading ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.isLoading)
            
            // 提示
            Text("请确保已部署 API 服务")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.top, 5)
        }
    }
}

// MARK: - 验证码登录表单组件
struct CaptchaLoginForm: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var phone = ""
    @State private var captcha = ""
    var onSuccess: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                Text("可能被网易云风控拦截，推荐使用扫码登录")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.leading)
            }
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            AnimatedInputField(
                placeholder: "手机号",
                icon: "phone",
                text: $phone
            )

            HStack(spacing: 12) {
                AnimatedInputField(
                    placeholder: "验证码",
                    icon: "number",
                    text: $captcha
                )

                Button(action: {
                    Task {
                        await viewModel.sendCaptcha(phone: phone)
                    }
                }) {
                    Text(viewModel.captchaCountdown > 0 ? "\(viewModel.captchaCountdown)s" : "获取验证码")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(canSendCaptcha ? .white : .gray)
                        .frame(width: 100, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canSendCaptcha ? Color.red : Color(.systemGray5))
                        )
                }
                .disabled(!canSendCaptcha || viewModel.isLoading)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // 登录按钮
            Button(action: {
                Task {
                    await viewModel.loginWithCaptcha(phone: phone, captcha: captcha)
                    if viewModel.isLoggedIn {
                        onSuccess?()
                    }
                }
            }) {
                ZStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("登录")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(27)
                .shadow(color: Color.red.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.top, 4)
            .disabled(phone.isEmpty || captcha.isEmpty || viewModel.isLoading)
            .opacity(phone.isEmpty || captcha.isEmpty ? 0.6 : 1)
            .scaleEffect(viewModel.isLoading ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: viewModel.isLoading)

            Text("验证码将发送到您的手机")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private var canSendCaptcha: Bool {
        phone.count >= 11 && viewModel.captchaCountdown == 0
    }
}

// MARK: - 现代化 Cookie 登录表单
struct ModernCookieLoginForm: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var cookie = ""
    @State private var showHelpSheet = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    var onSuccess: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            // Cookie 输入区域
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("MUSIC_U Cookie", systemImage: "key.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        HapticFeedback.light()
                        showHelpSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle.fill")
                            Text("如何获取")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                
                // 现代化输入框
                ZStack(alignment: .topLeading) {
                    if cookie.isEmpty {
                        Text("粘贴您的 MUSIC_U Cookie...")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    
                    TextEditor(text: $cookie)
                        .font(.system(.subheadline, design: .monospaced))
                        .focused($isInputFocused)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    isInputFocused ? Color.red.opacity(0.5) : Color.clear,
                                    lineWidth: 2
                                )
                        )
                )
                .animation(.easeOut(duration: 0.2), value: isInputFocused)
            }
            
            // 错误信息
            if let error = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.red)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red.opacity(0.1))
                )
            }
            
            // 登录按钮
            Button(action: {
                HapticFeedback.medium()
                isInputFocused = false
                Task {
                    await viewModel.loginWithCookie(cookie: cookie.trimmingCharacters(in: .whitespacesAndNewlines))
                    if viewModel.isLoggedIn {
                        onSuccess?()
                    }
                }
            }) {
                ZStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        HStack(spacing: 8) {
                            Text("登录")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                                .font(.subheadline.bold())
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Group {
                        if cookie.isEmpty {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.secondary.opacity(0.2))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color.red.opacity(0.4), radius: 15, y: 8)
                        }
                    }
                )
                .foregroundColor(cookie.isEmpty ? .secondary : .white)
            }
            .disabled(cookie.isEmpty || viewModel.isLoading)
            .scaleEffect(viewModel.isLoading ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isLoading)
            .buttonStyle(ScaleButtonStyle())
        }
        .sheet(isPresented: $showHelpSheet) {
            CookieHelpSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Cookie 获取帮助弹窗
struct CookieHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private let steps = [
        ("打开网易云音乐网页版", "在电脑浏览器访问 music.163.com 并登录账号", "globe"),
        ("打开开发者工具", "按 F12 或右键选择「检查」", "hammer.fill"),
        ("找到 Cookies", "点击 Application → Cookies → music.163.com", "folder.fill"),
        ("复制 MUSIC_U", "找到名为 MUSIC_U 的条目，复制其值", "doc.on.doc.fill")
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 头部图标
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.2), Color.orange.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "key.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.red, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.top, 20)
                    
                    Text("如何获取 Cookie")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // 步骤列表
                    VStack(spacing: 16) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HelpStepCard(
                                step: index + 1,
                                title: step.0,
                                detail: step.1,
                                icon: step.2
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // 提示卡片
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("小提示")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("只需复制 MUSIC_U 的值即可，无需全部 Cookie")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 帮助步骤卡片
struct HelpStepCard: View {
    let step: Int
    let title: String
    let detail: String
    let icon: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // 步骤编号
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Text("\(step)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
}

// MARK: - 兼容旧版 CookieLoginForm
struct CookieLoginForm: View {
    @ObservedObject var viewModel: AuthViewModel
    var onSuccess: (() -> Void)? = nil
    
    var body: some View {
        ModernCookieLoginForm(viewModel: viewModel, onSuccess: onSuccess)
    }
}

// MARK: - 登录弹窗
struct LoginSheetView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                if themeManager.showsCustomWallpaper {
                    CustomWallpaperLayer()
                } else {
                    Color(UIColor.systemGroupedBackground)
                        .ignoresSafeArea()
                }

                ScrollView {
                    VStack(spacing: 28) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red, Color.red.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.red.opacity(0.4), radius: 15, y: 8)

                            Image(systemName: "music.note")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 30)

                        VStack(spacing: 8) {
                            Text("欢迎登录")
                                .font(.title2)
                                .fontWeight(.bold)

                 Text("扫码、验证码或 Cookie 登录网易云账号")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        KumoneLoginPanel(viewModel: authViewModel) {
                            dismiss()
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.horizontal, 20)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChangeCompat(of: authViewModel.currentUser) { _, user in
                if user != nil {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
