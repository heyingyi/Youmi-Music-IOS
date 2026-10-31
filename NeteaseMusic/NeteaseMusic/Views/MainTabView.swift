import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selectedTab: TabSelection = .home
    @State private var showLogin = false
    @State private var searchAutoFocus = false
    @Namespace private var animation
    
    // 记录已访问过的 tab，用于懒加载
    @State private var loadedTabs: Set<TabSelection> = [.home, .discover]
    
    // 搜索模式（旧版使用）
    @State private var isSearchMode = false
    @State private var previousTab: TabSelection = .home
    
    // 播放器状态
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @State private var showPlayer = false
    @State private var showMoodRecommend = false
    
    // 键盘预热 - 使用 AppStorage 避免主题切换时重置
    @AppStorage("keyboard_warmed_up") private var keyboardWarmedUp = false
    
    // Tab 枚举
    enum TabSelection: Int, Hashable {
        case home = 0
        case discover = 1
        case appleMusic = 2
        case library = 3
        case search = 4
    }
    
    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                ios26TabView
            } else {
                legacyTabView
            }
        }
        .task {
            await preWarmData()
        }
        .fullScreenCover(isPresented: $showLogin) {
            LoginSheetView()
                .environmentObject(authViewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLoginSheet)) { _ in
            guard !authViewModel.isLoggedIn else { return }
            selectedTab = .library
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showLogin = true
            }
        }
    }
    
    // MARK: - iOS 26 原生 TabView
    @available(iOS 26.0, *)
    private var ios26TabView: some View {
        TabView(selection: $selectedTab) {
            Tab("主页", systemImage: "house.fill", value: .home) {
                NavigationStack {
                    DiscoverView()
                }
            }
            .customizationID("com.youmi.home")
            
            Tab("发现", systemImage: "square.grid.2x2", value: .discover) {
                NavigationStack {
                    NewDiscoveryView()
                }
            }
            .customizationID("com.youmi.discover")
            
            Tab("Apple", systemImage: "apple.logo", value: .appleMusic) {
                NavigationStack {
                    AppleMusicView()
                }
            }
            .customizationID("com.youmi.appleMusic")
            
            Tab("我的", systemImage: "person.fill", value: .library) {
                NavigationStack {
                    LibraryView()
                }
            }
            .customizationID("com.youmi.library")
            
            Tab(value: .search, role: .search) {
                NavigationStack {
                    iOS26SearchView(showPlayer: $showPlayer)
                }
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            HStack(spacing: 8) {
                Image(systemName: "cat.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Youmi Music")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
        }
        .tabViewSidebarFooter {
            if audioPlayer.currentTrack != nil {
                iPadSidebarMiniPlayer
            }
        }
        .tabViewBottomAccessory {
            if audioPlayer.currentTrack != nil {
                iOS26FloatingMiniPlayer(showPlayer: $showPlayer, showMoodRecommend: $showMoodRecommend)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .background {
            CustomWallpaperLayer()
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
        .fullScreenCover(isPresented: $showMoodRecommend) {
            MoodRecommendView()
        }
        .overlay {
            if !keyboardWarmedUp {
                KeyboardWarmer(didWarmUp: $keyboardWarmedUp)
            }
        }
    }
    
    // MARK: - iPad 侧边栏迷你播放器
    @available(iOS 26.0, *)
    private var iPadSidebarMiniPlayer: some View {
        Button {
            HapticFeedback.light()
            showPlayer = true
        } label: {
            HStack(spacing: 10) {
                // 封面
                if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                   let url = URL(string: coverUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                    }
                    .id(coverUrl)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(audioPlayer.currentTrack?.name ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(audioPlayer.currentTrack?.artistName ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // 播放/暂停
                Button {
                    HapticFeedback.light()
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                // 下一首
                Button {
                    HapticFeedback.light()
                    audioPlayer.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 旧版 TabView (iOS 26 以下)
    private var legacyTabView: some View {
        ZStack {
            CustomWallpaperLayer()
            themedMainBackground
            TabContentContainer(selectedTab: selectedTab, loadedTabs: $loadedTabs)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    LegacyCustomTabBar(
                        selectedTab: Binding(
                            get: { selectedTab.rawValue },
                            set: { selectedTab = TabSelection(rawValue: $0) ?? .home }
                        ),
                        isSearchMode: $isSearchMode,
                        animation: animation
                    )
                }
        }
        .overlay {
            // 隐藏的键盘预热 TextField
            if !keyboardWarmedUp {
                KeyboardWarmer(didWarmUp: $keyboardWarmedUp)
            }
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $isSearchMode) {
            FullScreenSearchView(
                isSearchMode: $isSearchMode,
                previousTabIcon: ["house.fill", "square.grid.2x2", "apple.logo", "person.fill"][min(selectedTab.rawValue, 3)]
            )
        }
        .onChangeCompat(of: isSearchMode) { _, newValue in
            if newValue {
                previousTab = selectedTab
            } else {
                selectedTab = previousTab
            }
        }
    }
    
    // MARK: - 主题感知主背景
    @ViewBuilder
    private var themedMainBackground: some View {
        if themeManager.showsCustomWallpaper {
            Color.clear
        } else if themeManager.themeStyle == .strangerThings {
            StrangerThingsBackground()
        } else {
            LiquidGlassBackground()
        }
    }
    
    // MARK: - 预热数据
    private func preWarmData() async {
        async let hotSearch: () = Task.detached(priority: .utility) {
            _ = try? await MusicService.shared.getHotSearch()
        }.value
        
        async let banners: () = Task.detached(priority: .utility) {
            _ = try? await MusicService.shared.getBanners()
        }.value
        
        async let personalized: () = Task.detached(priority: .utility) {
            _ = try? await MusicService.shared.getPersonalized()
        }.value
        
        _ = await (hotSearch, banners, personalized)
    }
}

// MARK: - iOS 18+ 侧边栏迷你播放器
@available(iOS 18.0, *)
struct iOS18SidebarMiniPlayer: View {
    @Binding var showPlayer: Bool
    @Binding var showMoodRecommend: Bool
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        VStack(spacing: 8) {
            // 迷你播放器
            Button {
                HapticFeedback.light()
                showPlayer = true
            } label: {
                HStack(spacing: 10) {
                    if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                       let url = URL(string: coverUrl) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                        }
                        .id(coverUrl)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioPlayer.currentTrack?.name ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(audioPlayer.currentTrack?.artistName ?? "")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                    
                    Button {
                        HapticFeedback.light()
                        audioPlayer.togglePlayPause()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        HapticFeedback.light()
                        audioPlayer.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            // 深夜电台
            Button {
                HapticFeedback.medium()
                showMoodRecommend = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.9), Color.indigo.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("深夜电台")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - iOS 26 浮动迷你播放器
@available(iOS 26.0, *)
struct iOS26FloatingMiniPlayer: View {
    @Binding var showPlayer: Bool
    @Binding var showMoodRecommend: Bool
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        HStack(spacing: 10) {
            // 深夜电台
            Button {
                HapticFeedback.medium()
                showMoodRecommend = true
            } label: {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.9), Color.indigo.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            
            Button {
                HapticFeedback.light()
                showPlayer = true
            } label: {
                HStack(spacing: 10) {
                    // 封面
                    if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                       let url = URL(string: coverUrl) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                        }
                        .id(coverUrl)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioPlayer.currentTrack?.name ?? "未播放")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(audioPlayer.currentTrack?.artistName ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 播放/暂停
            Button {
                HapticFeedback.light()
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            
            // 下一首
            Button {
                HapticFeedback.light()
                audioPlayer.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - iOS 26 简化版迷你播放器（备用）
@available(iOS 26.0, *)
struct iOS26SimpleMiniPlayer: View {
    @Binding var showPlayer: Bool
    @Binding var showMoodRecommend: Bool
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // 深夜电台
            Button(action: {
                HapticFeedback.medium()
                showMoodRecommend = true
            }) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.9), Color.indigo.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
            }
            
            // 封面 + 歌曲信息 - 点击打开播放器
            Button(action: {
                HapticFeedback.light()
                showPlayer = true
            }) {
                HStack(spacing: 10) {
                    // 封面
                    if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                       let url = URL(string: coverUrl) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                        }
                        .id(coverUrl)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    // 歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioPlayer.currentTrack?.name ?? "未播放")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(audioPlayer.currentTrack?.artistName ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                }
            }
            
            // 播放/暂停
            Button(action: {
                HapticFeedback.light()
                audioPlayer.togglePlayPause()
            }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
            }
            
            // 下一首
            Button(action: {
                HapticFeedback.light()
                audioPlayer.playNext()
            }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
            }
        }
        .buttonStyle(BorderlessButtonStyle()) // 关键：使用 BorderlessButtonStyle
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - iOS 26 迷你播放器 Overlay 版本（备用）
@available(iOS 26.0, *)
struct iOS26MiniPlayerOverlay: View {
    @Binding var showPlayer: Bool
    @Binding var showMoodRecommend: Bool
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        HStack(spacing: 10) {
            // 深夜电台按钮
            Button {
                HapticFeedback.medium()
                showMoodRecommend = true
            } label: {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.9), Color.indigo.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            
            // 播放器信息区域
            Button {
                HapticFeedback.light()
                showPlayer = true
            } label: {
                HStack(spacing: 10) {
                    // 封面
                    Group {
                        if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                           let url = URL(string: coverUrl) {
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.systemGray5))
                            }
                            .id(coverUrl)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // 歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioPlayer.currentTrack?.name ?? "未播放")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(audioPlayer.currentTrack?.artistName ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            
            // 播放/暂停按钮
            Button {
                HapticFeedback.light()
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            
            // 下一首按钮
            Button {
                HapticFeedback.light()
                audioPlayer.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.clear)
                .glassEffect(.regular)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - iOS 26 迷你播放器（作为 TabView 底部附件 - 备用）
@available(iOS 26.0, *)
struct iOS26MiniPlayer: View {
    @Binding var showPlayer: Bool
    @Binding var showMoodRecommend: Bool
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        HStack(spacing: 8) {
            // 深夜电台按钮
            miniPlayerButton(
                systemImage: "moon.stars.fill",
                size: 18,
                frameSize: 48,
                gradient: LinearGradient(
                    colors: [Color.purple.opacity(0.9), Color.indigo.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ) {
                HapticFeedback.medium()
                showMoodRecommend = true
            }
            
            // 播放器信息区域
            miniPlayerInfoButton
            
            // 播放/暂停按钮
            miniPlayerButton(
                systemImage: audioPlayer.isPlaying ? "pause.fill" : "play.fill",
                size: 22,
                frameSize: 52
            ) {
                HapticFeedback.light()
                audioPlayer.togglePlayPause()
            }
            
            // 下一首按钮
            miniPlayerButton(
                systemImage: "forward.fill",
                size: 18,
                frameSize: 52
            ) {
                HapticFeedback.light()
                audioPlayer.playNext()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    // MARK: - 播放器信息按钮
    private var miniPlayerInfoButton: some View {
        Button(action: {
            HapticFeedback.light()
            showPlayer = true
        }) {
            HStack(spacing: 10) {
                // 封面
                Group {
                    if let coverUrl = audioPlayer.currentTrack?.coverUrl,
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
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // 歌曲信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(audioPlayer.currentTrack?.name ?? "未播放")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(audioPlayer.currentTrack?.artistName ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(iOS26MiniPlayerButtonStyle())
    }
    
    // MARK: - 封面占位图
    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            )
    }
    
    // MARK: - 通用按钮
    private func miniPlayerButton(
        systemImage: String,
        size: CGFloat,
        frameSize: CGFloat,
        gradient: LinearGradient? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let gradient = gradient {
                    Image(systemName: systemImage)
                        .font(.system(size: size, weight: .medium))
                        .foregroundStyle(gradient)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: size, weight: .bold))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: frameSize, height: frameSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(iOS26MiniPlayerButtonStyle())
    }
}

// MARK: - iOS 26 迷你播放器按钮样式
@available(iOS 26.0, *)
struct iOS26MiniPlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 键盘预热器
private struct KeyboardWarmer: View {
    @Binding var didWarmUp: Bool
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextField("", text: .constant(""))
            .focused($isFocused)
            .frame(width: 0, height: 0)
            .opacity(0)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isFocused = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFocused = false
                        didWarmUp = true
                    }
                }
            }
    }
}

// MARK: - iOS 26 原生搜索视图
@available(iOS 26.0, *)
struct iOS26SearchView: View {
    @Binding var showPlayer: Bool
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var hasSearched = false
    
    // 搜索结果
    @State private var songResults: [SearchSong] = []
    @State private var artistResults: [SearchArtistResult] = []
    @State private var albumResults: [SearchAlbumResult] = []
    @State private var songDetailsCache: [Int: Track] = [:]
    @State private var errorMessage: String?
    
    // 热搜和历史
    @StateObject private var historyManager = SearchHistoryManager.shared
    @State private var hotSearches: [HotSearch] = []
    
    // 分类选择
    @State private var selectedCategory: SearchCategory = .best
    
    var body: some View {
        NavigationStack {
            Group {
                if hasSearched {
                    searchResultsContent
                } else {
                    searchHomeContent
                }
            }
            .background {
                ThemedBackground()
                    .environmentObject(ThemeManager.shared)
            }
            .immersiveNavigationChrome()
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "艺人、歌曲、歌词以及更多内容")
            .onSubmit(of: .search) {
                performSearch()
            }
            .navigationDestination(for: ArtistDestination.self) { dest in
                ArtistDetailView(artistId: dest.id, artistName: dest.name)
            }
            .navigationDestination(for: AlbumDestination.self) { dest in
                AlbumDetailView(albumId: dest.id, albumName: dest.name)
            }
        }
        .onChangeCompat(of: searchText) { _, newValue in
            if newValue.isEmpty {
                hasSearched = false
                songResults = []
                artistResults = []
                albumResults = []
            }
        }
        .task {
            await loadHotSearches()
        }
    }
    
    // MARK: - 搜索首页内容
    private var searchHomeContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // 搜索历史
                if !historyManager.history.isEmpty {
                    searchHistorySection
                }
                
                // 热搜榜
                if !hotSearches.isEmpty {
                    hotSearchSection
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }
    
    // MARK: - 搜索历史区域
    private var searchHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近搜索")
                    .font(.system(size: 20, weight: .bold))
                
                Spacer()
                
                Button("清除") {
                    withAnimation {
                        historyManager.clearHistory()
                    }
                }
                .font(.system(size: 15))
                .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(historyManager.history) { entry in
                        Button {
                            searchText = entry.keyword
                            performSearch()
                        } label: {
                            Text(entry.keyword)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemGray5))
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - 热搜榜区域
    private var hotSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
                        )
                    Text("热搜榜")
                        .font(.system(size: 20, weight: .bold))
                }
                
                Spacer()
                
                Text("实时更新")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray6))
                    )
            }
            .padding(.horizontal, 16)
            
            LazyVStack(spacing: 0) {
                ForEach(Array(hotSearches.enumerated()), id: \.element.id) { index, item in
                    Button {
                        searchText = item.searchWord
                        performSearch()
                    } label: {
                        iOS26HotSearchRow(index: index + 1, item: item)
                    }
                    .buttonStyle(.plain)
                    
                    if index < hotSearches.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - 搜索结果内容
    private var searchResultsContent: some View {
        VStack(spacing: 0) {
            if isSearching {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("搜索中...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 分类标签栏
                categoryTabBar
                
                // 搜索结果
                searchResultsList
            }
        }
    }
    
    // MARK: - 分类标签栏
    private var categoryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SearchCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.rawValue)
                            .font(.system(size: 15, weight: selectedCategory == category ? .semibold : .regular))
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedCategory == category ? Color.red : Color(.systemGray5))
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - 搜索结果列表
    private var searchResultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                switch selectedCategory {
                case .best:
                    bestResultsContent
                case .artist:
                    artistResultsContent
                case .album:
                    albumResultsContent
                case .song:
                    songResultsContent
                }
            }
            .padding(.bottom, 120)
        }
    }
    
    // MARK: - 最佳结果
    @ViewBuilder
    private var bestResultsContent: some View {
        // 艺人结果（显示第一个匹配的艺人）
        if let firstArtist = artistResults.first {
            NavigationLink(value: ArtistDestination(id: firstArtist.id, name: firstArtist.name)) {
                iOS26ArtistRow(artist: firstArtist, isTopResult: true)
            }
            .buttonStyle(.plain)
        }
        
        // 歌曲结果
        ForEach(songResults) { song in
            iOS26SongRow(song: song, coverUrl: getCoverUrl(for: song)) {
                playSong(song)
            }
        }
        
        if songResults.isEmpty && artistResults.isEmpty {
            emptyResultView
        }
    }
    
    // MARK: - 艺人结果
    @ViewBuilder
    private var artistResultsContent: some View {
        if artistResults.isEmpty {
            emptyResultView
        } else {
            ForEach(artistResults) { artist in
                NavigationLink(value: ArtistDestination(id: artist.id, name: artist.name)) {
                    iOS26ArtistRow(artist: artist, isTopResult: false)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - 专辑结果
    @ViewBuilder
    private var albumResultsContent: some View {
        if albumResults.isEmpty {
            emptyResultView
        } else {
            ForEach(albumResults) { album in
                NavigationLink(value: AlbumDestination(id: album.id, name: album.name)) {
                    iOS26AlbumRow(album: album)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - 歌曲结果
    @ViewBuilder
    private var songResultsContent: some View {
        if songResults.isEmpty {
            emptyResultView
        } else {
            ForEach(songResults) { song in
                iOS26SongRow(song: song, coverUrl: getCoverUrl(for: song)) {
                    playSong(song)
                }
            }
        }
    }
    
    // MARK: - 空结果视图
    private var emptyResultView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("未找到\"\(searchText)\"的相关结果")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - 加载热搜
    private func loadHotSearches() async {
        do {
            let results = try await MusicService.shared.getHotSearch()
            await MainActor.run {
                hotSearches = Array(results.prefix(10))
            }
        } catch {
            #if DEBUG
            print("加载热搜失败: \(error)")
            #endif
        }
    }
    
    // MARK: - 执行搜索
    private func performSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        
        historyManager.addSearch(keyword: keyword)
        
        isSearching = true
        hasSearched = true
        errorMessage = nil
        selectedCategory = .best
        
        Task {
            do {
                async let songsTask = MusicService.shared.search(keyword: keyword, limit: 30)
                async let artistsTask = MusicService.shared.searchArtists(keyword: keyword, limit: 10)
                async let albumsTask = MusicService.shared.searchAlbums(keyword: keyword, limit: 10)
                
                let (songRes, artistRes, albumRes) = try await (songsTask, artistsTask, albumsTask)
                
                await MainActor.run {
                    songResults = songRes
                    artistResults = artistRes
                    albumResults = albumRes
                    isSearching = false
                }
                
                // 异步获取歌曲详情（包含封面）
                if !songRes.isEmpty {
                    let ids = songRes.map { $0.id }
                    if let details = try? await MusicService.shared.getSongDetail(ids: ids) {
                        var cache: [Int: Track] = [:]
                        for track in details {
                            cache[track.id] = track
                        }
                        await MainActor.run {
                            songDetailsCache = cache
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "搜索失败，请重试"
                    isSearching = false
                }
            }
        }
    }
    
    // 获取歌曲封面
    private func getCoverUrl(for song: SearchSong) -> String? {
        if let cached = songDetailsCache[song.id], let cover = cached.coverUrl {
            return cover
        }
        return song.coverUrl
    }
    
    // MARK: - 播放歌曲
    private func playSong(_ song: SearchSong) {
        let tracks = songResults.map { s in
            s.toTrack(withCoverUrl: getCoverUrl(for: s))
        }
        
        if let index = songResults.firstIndex(where: { $0.id == song.id }) {
            AudioPlayer.shared.setPlaylist(tracks, startAt: index)
        } else if !tracks.isEmpty {
            AudioPlayer.shared.setPlaylist(tracks, startAt: 0)
        }
        HapticFeedback.light()
    }
}

// MARK: - iOS 26 热搜行
@available(iOS 26.0, *)
struct iOS26HotSearchRow: View {
    let index: Int
    let item: HotSearch
    
    private var indexColor: Color {
        switch index {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 16, weight: index <= 3 ? .bold : .medium))
                .foregroundColor(indexColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.searchWord)
                        .font(.system(size: 16, weight: index <= 3 ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let iconType = item.iconType {
                        iOS26HotSearchTag(iconType: iconType)
                    }
                }
                
                if let content = item.content, !content.isEmpty {
                    Text(content)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let score = item.score {
                Text(formatScore(score))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    
    private func formatScore(_ score: Int) -> String {
        if score >= 10000 {
            return String(format: "%.1f万", Double(score) / 10000)
        }
        return "\(score)"
    }
}

// MARK: - iOS 26 热搜标签
@available(iOS 26.0, *)
struct iOS26HotSearchTag: View {
    let iconType: Int
    
    private var tagInfo: (text: String, color: Color) {
        switch iconType {
        case 1: return ("热", .red)
        case 2: return ("新", .blue)
        case 3: return ("飙", .orange)
        case 5: return ("荐", .purple)
        default: return ("", .clear)
        }
    }
    
    var body: some View {
        if !tagInfo.text.isEmpty {
            Text(tagInfo.text)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(tagInfo.color)
                .cornerRadius(4)
        }
    }
}

// MARK: - iOS 26 歌曲行
@available(iOS 26.0, *)
struct iOS26SongRow: View {
    let song: SearchSong
    var coverUrl: String?
    let onTap: () -> Void
    
    private var displayCoverUrl: String? {
        coverUrl ?? song.coverUrl
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let coverUrl = displayCoverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.secondary)
                    )
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(song.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(song.artistName) - \(song.albumName)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 更多按钮
            Menu {
                Button {
                    AudioPlayer.shared.playNext(track: song.toTrack())
                    HapticFeedback.light()
                } label: {
                    Label("播放下一首", systemImage: "text.insert")
                }
                
                Button {
                    AudioPlayer.shared.addToQueue(track: song.toTrack())
                    HapticFeedback.light()
                } label: {
                    Label("添加到播放列表", systemImage: "text.append")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - iOS 26 艺人行
@available(iOS 26.0, *)
struct iOS26ArtistRow: View {
    let artist: SearchArtistResult
    var isTopResult: Bool = false
    
    var body: some View {
        HStack(spacing: 14) {
            // 艺人头像
            if let avatarUrl = artist.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color(.systemGray5))
                }
                .frame(width: isTopResult ? 60 : 50, height: isTopResult ? 60 : 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: isTopResult ? 60 : 50, height: isTopResult ? 60 : 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: isTopResult ? 24 : 20))
                            .foregroundColor(.secondary)
                    )
            }
            
            // 艺人信息
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.system(size: isTopResult ? 17 : 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("艺人")
                        .font(.system(size: isTopResult ? 14 : 13))
                        .foregroundColor(.secondary)
                    
                    if let albumSize = artist.albumSize, albumSize > 0 {
                        Text("\(albumSize)张专辑")
                            .font(.system(size: isTopResult ? 14 : 13))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isTopResult ? 12 : 10)
        .contentShape(Rectangle())
    }
}

// MARK: - iOS 26 专辑行
@available(iOS 26.0, *)
struct iOS26AlbumRow: View {
    let album: SearchAlbumResult
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let picUrl = album.picUrl, let url = URL(string: picUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "square.stack")
                            .foregroundColor(.secondary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("专辑 · \(album.artistName)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Tab 内容容器（零卡顿切换核心）
/// 使用 UIKit 的 UIViewController 容器实现真正的视图缓存
/// Apple Music 就是用类似的方式实现丝滑切换
private struct TabContentContainer: View {
    let selectedTab: MainTabView.TabSelection
    @Binding var loadedTabs: Set<MainTabView.TabSelection>
    
    var body: some View {
        // 使用 ZStack + 固定 zIndex 确保视图层级稳定
        ZStack {
            // 预先创建所有 tab 的容器，使用 id 保持稳定
            TabPage(tab: .home, isSelected: selectedTab == .home, shouldLoad: loadedTabs.contains(.home)) {
                NavigationStack {
                    DiscoverView()
                }
                .background(Color.clear)
            }
            .zIndex(selectedTab == .home ? 1 : 0)
            
            TabPage(tab: .discover, isSelected: selectedTab == .discover, shouldLoad: loadedTabs.contains(.discover)) {
                NavigationStack {
                    NewDiscoveryView()
                }
                .background(Color.clear)
            }
            .zIndex(selectedTab == .discover ? 1 : 0)
            
            TabPage(tab: .appleMusic, isSelected: selectedTab == .appleMusic, shouldLoad: loadedTabs.contains(.appleMusic)) {
                NavigationStack {
                    AppleMusicView()
                }
                .background(Color.clear)
            }
            .zIndex(selectedTab == .appleMusic ? 1 : 0)
            
            TabPage(tab: .library, isSelected: selectedTab == .library, shouldLoad: loadedTabs.contains(.library)) {
                NavigationStack {
                    LibraryView()
                }
                .background(Color.clear)
            }
            .zIndex(selectedTab == .library ? 1 : 0)
        }
        .onChangeCompat(of: selectedTab) { _, newTab in
            loadedTabs.insert(newTab)
        }
    }
}

// MARK: - 单个 Tab 页面容器
/// 关键优化：使用 @ViewBuilder 延迟构建 + 稳定的视图标识
private struct TabPage<Content: View>: View {
    let tab: MainTabView.TabSelection
    let isSelected: Bool
    let shouldLoad: Bool
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        Group {
            if shouldLoad {
                content()
                    // 使用 transaction 禁用切换时的隐式动画，避免卡顿
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            } else {
                Color.clear
            }
        }
        // 关键：使用 opacity 而非条件渲染，保持视图树稳定
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        // 稳定的视图标识，防止 SwiftUI diff 算法重建视图
        .id(tab)
    }
}

// MARK: - 性能优化扩展
extension View {
    /// 禁用视图的隐式动画，用于 tab 切换场景
    func disableAnimationsOnChange() -> some View {
        self.transaction { $0.animation = nil }
    }
}
