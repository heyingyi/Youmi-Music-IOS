import SwiftUI

// MARK: - Apple Music 液态玻璃风格音乐库页
struct LibraryView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var localStorage = LocalStorageService.shared
    @StateObject private var localMusicService = LocalMusicService.shared
    @State private var showLogin = false
    @State private var cloudPlaylists: [CloudPlaylist] = []
    @State private var cloudAlbums: [CloudAlbum] = []
    @State private var likedSongIds: [Int] = []
    @State private var isLoadingCloud = false
    
    private let userService = UserService.shared
    
    // 主题颜色
    private var textColor: Color {
        themeManager.themeStyle == .strangerThings ? .white : .primary
    }
    
    private var secondaryTextColor: Color {
        themeManager.themeStyle == .strangerThings ? .white.opacity(0.6) : .secondary
    }
    
    var body: some View {
        ZStack {
            themedBackground
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    liquidGlassUserSection

                    if authViewModel.isLoggedIn {
                        cloudMusicSection
                    }

                    liquidGlassLibraryContent
                }
                .padding(.bottom, 120)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("我的")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .fullScreenCover(isPresented: $showLogin) {
            LoginSheetView()
                .environmentObject(authViewModel)
        }
        .task {
            if authViewModel.isLoggedIn {
                // 等待用户信息加载完成
                if authViewModel.currentUser == nil {
                    await authViewModel.fetchCurrentUser()
                }
                await loadCloudData()
            }
        }
        .onChangeCompat(of: authViewModel.currentUser) { _, newUser in
            if newUser != nil && cloudPlaylists.isEmpty {
                Task { await loadCloudData() }
            }
        }
        .onChangeCompat(of: authViewModel.isLoggedIn) { _, isLoggedIn in
            if !isLoggedIn {
                // 退出登录时清空数据
                cloudPlaylists = []
                cloudAlbums = []
                likedSongIds = []
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .likedSongsChanged)) { _ in
            Task { await loadCloudData() }
        }
    }
    
    // MARK: - 主题背景
    @ViewBuilder
    private var themedBackground: some View {
        if themeManager.showsCustomWallpaper {
            CustomWallpaperLayer()
        } else {
            switch themeManager.themeStyle {
            case .standard:
                LiquidGlassBackground(colors: [.blue.opacity(0.08), .purple.opacity(0.06), .pink.opacity(0.04)])
            case .strangerThings:
                StrangerThingsBackground()
            }
        }
    }
    
    // MARK: - 加载云端数据
    private func loadCloudData() async {
        guard let userId = authViewModel.currentUser?.userId else {
            #if DEBUG
            print("未获取到 userId")
            #endif
            return
        }
        guard !isLoadingCloud else { return }
        isLoadingCloud = true
        #if DEBUG
        print("开始加载云端数据, userId: \(userId)")
        #endif
        
        do {
            async let playlists = userService.getUserPlaylists(uid: userId)
            async let albums = userService.getAlbumSublist()
            async let likeIds = userService.getLikeList(uid: userId)
            
            cloudPlaylists = try await playlists
            cloudAlbums = try await albums
            likedSongIds = try await likeIds
        } catch {
            #if DEBUG
            print("加载云端数据失败: \(error)")
            #endif
        }

        isLoadingCloud = false
    }
    
    // MARK: - 液态玻璃用户区域
    private var liquidGlassUserSection: some View {
        VStack(spacing: 0) {
            if authViewModel.isLoggedIn, let profile = authViewModel.currentUser {
                // 已登录：显示用户卡片
                NavigationLink(destination: ProfileCardView().environmentObject(authViewModel)) {
                    LiquidGlassUserCard(
                        avatarUrl: profile.avatarUrl.flatMap { URL(string: $0) },
                        nickname: profile.nickname,
                        level: profile.level
                    )
                }
                .buttonStyle(LiquidGlassButtonStyle())
            } else {
                // 未登录：显示登录入口
                Button(action: { showLogin = true }) {
                    LiquidGlassLoginCard()
                }
                .buttonStyle(LiquidGlassButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .task {
            if authViewModel.isLoggedIn && authViewModel.currentUser == nil {
                await authViewModel.fetchCurrentUser()
            }
        }
    }
    
    // MARK: - 网易Max 云端音乐区域
    private var cloudMusicSection: some View {
        LiquidGlassSection(title: "网易Max", showsBackground: false) {
            if isLoadingCloud {
                GridSkeletonView(
                    count: 6,
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ]
                )
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 16) {
                    NavigationLink {
                        if let likedPlaylist = cloudPlaylists.first(where: { $0.isLikedPlaylist }) {
                            CloudLikedSongsView(playlistId: likedPlaylist.id, songCount: likedSongIds.count)
                        }
                    } label: {
                        CloudFeatureCard(
                            icon: "heart.fill",
                            iconColor: .pink,
                            title: "喜欢的音乐",
                            count: likedSongIds.count
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CloudPlaylistsView(playlists: cloudPlaylists.filter { !$0.isLikedPlaylist })
                    } label: {
                        CloudFeatureCard(
                            icon: "music.note.list",
                            iconColor: .red,
                            title: "我的歌单",
                            count: cloudPlaylists.filter { !$0.isLikedPlaylist }.count
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // 收藏的专辑
                    NavigationLink {
                        CloudAlbumsView(albums: cloudAlbums)
                    } label: {
                        CloudFeatureCard(
                            icon: "square.stack",
                            iconColor: .purple,
                            title: "收藏专辑",
                            count: cloudAlbums.count
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // 我的云盘
                    NavigationLink {
                        CloudDiskView()
                    } label: {
                        CloudFeatureCard(
                            icon: "cloud.fill",
                            iconColor: .blue,
                            title: "我的云盘",
                            count: nil
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - 液态玻璃收藏库内容
    private var liquidGlassLibraryContent: some View {
        VStack(spacing: 20) {
            // 本地音乐库
            LiquidGlassSection(title: "本地音乐库", showsBackground: false) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 16) {
                    NavigationLink {
                        LocalMusicView()
                    } label: {
                        CloudFeatureCard(
                            icon: "music.note.house.fill",
                            iconColor: .green,
                            title: "本地歌曲",
                            count: localMusicService.localTracks.count
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FavoritesView()
                    } label: {
                        CloudFeatureCard(
                            icon: "heart.fill",
                            iconColor: .red,
                            title: "我喜欢的音乐",
                            count: localStorage.favoritesCount
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PlayHistoryView()
                    } label: {
                        CloudFeatureCard(
                            icon: "clock.fill",
                            iconColor: .orange,
                            title: "最近播放",
                            count: localStorage.historyCount
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - 云端功能卡片
struct CloudFeatureCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let count: Int?
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.2), iconColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .frame(width: 50, height: 50)
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if let count = count {
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassEffectRounded(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.22), .clear]
                            : [.white.opacity(0.55), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .shadow(color: iconColor.opacity(themeManager.liquidGlassEnabled ? 0.12 : 0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 液态玻璃用户卡片
struct LiquidGlassUserCard: View {
    let avatarUrl: URL?
    let nickname: String
    let level: Int?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            // 头像
            LiquidGlassAvatar(imageUrl: avatarUrl, size: 56)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(nickname)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                if let level = level {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("Lv.\(level)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                    )
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .glassEffectRounded(cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.4), .white.opacity(0.1), .clear]
                            : [.white.opacity(0.55), .white.opacity(0.18), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 15, x: 0, y: 8)
    }
}

// MARK: - 液态玻璃登录卡片
struct LiquidGlassLoginCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            // 头像占位
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.7))
                
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white.opacity(0.4), .white.opacity(0.1), .clear]
                                : [.white.opacity(0.8), .white.opacity(0.3), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                
                Image(systemName: "person.circle")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
            }
            .frame(width: 56, height: 56)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("点击登录")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("登录后享受更多功能")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .glassEffectRounded(cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.4), .white.opacity(0.1), .clear]
                            : [.white.opacity(0.55), .white.opacity(0.18), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 15, x: 0, y: 8)
    }
}

// MARK: - 液态玻璃库列表行
struct LiquidGlassLibraryRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var count: Int? = nil
    var subtitle: String? = nil
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            // 液态玻璃图标
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                
                Circle()
                    .fill(iconColor.opacity(colorScheme == .dark ? 0.2 : 0.15))
                
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white.opacity(0.3), .white.opacity(0.1), .clear]
                                : [.white.opacity(0.6), .white.opacity(0.2), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .frame(width: 44, height: 44)
            .shadow(color: iconColor.opacity(0.2), radius: 6, x: 0, y: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let count = count {
                Text("\(count)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - 液态玻璃分割线
struct LiquidGlassDivider: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [.clear, .white.opacity(0.1), .clear]
                        : [.clear, .black.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.leading, 74)
    }
}

// MARK: - 云端歌单列表页面
struct CloudPlaylistsView: View {
    let playlists: [CloudPlaylist]
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            CloudPlaylistDetailView(playlist: playlist)
                        } label: {
                            PlaylistRowView(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("我的歌单")
    }
}

// MARK: - 歌单行视图
struct PlaylistRowView: View {
    let playlist: CloudPlaylist
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            if let coverUrl = playlist.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: "music.note.list").foregroundColor(.gray))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(playlist.trackCount ?? 0) 首")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .glassEffectRounded(cornerRadius: 12)
    }
}

// MARK: - 歌单详情页面
struct CloudPlaylistDetailView: View {
    let playlist: CloudPlaylist
    @State private var tracks: [CloudTrack] = []
    @State private var isLoading = true
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(ThemeManager.shared)
            ScrollView {
                VStack(spacing: 0) {
                    playlistHeader
                    playAllButton

                    if isLoading {
                        ProgressView().padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                CloudTrackRow(track: track, index: index + 1) {
                                    playTrack(track, index: index)
                                }
                                if index < tracks.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTracks() }
    }
    
    private var playlistHeader: some View {
        VStack(spacing: 12) {
            if let coverUrl = playlist.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: 180, height: 180)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            }
            
            if let desc = playlist.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 40)
            }
        }
        .padding(.vertical, 20)
    }
    
    private var playAllButton: some View {
        Button(action: playAll) {
            HStack {
                Image(systemName: "play.fill")
                Text("播放全部")
                Text("(\(tracks.count))").foregroundColor(.white.opacity(0.8))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(25)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
        .disabled(tracks.isEmpty)
    }
    
    private func loadTracks() async {
        do {
            tracks = try await MusicService.shared.getPlaylistTracks(playlistId: playlist.id)
        } catch {
            #if DEBUG
            print("加载歌曲失败: \(error)")
            #endif
        }
        isLoading = false
    }

    private func playTrack(_ track: CloudTrack, index: Int) {
        let playerTracks = tracks.map { $0.toTrack() }
        audioPlayer.setPlaylist(playerTracks, startAt: index)
    }
    
    private func playAll() {
        guard !tracks.isEmpty else { return }
        let playerTracks = tracks.map { $0.toTrack() }
        audioPlayer.setPlaylist(playerTracks, startAt: 0)
    }
}

// MARK: - 喜欢的音乐缓存
@MainActor
final class LikedSongsStore: ObservableObject {
    static let shared = LikedSongsStore()

    @Published var tracks: [Track] = []
    @Published var isLoading: Bool = false
    @Published var loadingProgress: String = ""

    private var loadTask: Task<Void, Never>?
    private var currentPlaylistId: Int?
    private var lastSongCount: Int?
    private var isDirty = false

    private init() {}

    func ensureLoaded(playlistId: Int, songCount: Int) {
        if currentPlaylistId == playlistId,
           !tracks.isEmpty,
           !isDirty,
           lastSongCount == songCount {
            return
        }
        refresh(playlistId: playlistId, songCount: songCount)
    }

    func refresh(playlistId: Int, songCount: Int) {
        if isLoading { return }
        tracks = []
        isDirty = false
        lastSongCount = songCount
        currentPlaylistId = playlistId
        isLoading = true
        loadingProgress = ""

        loadTask?.cancel()
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.loadAll(playlistId: playlistId, songCount: songCount)
        }
    }

    func markDirty() {
        isDirty = true
    }

    private func loadAll(playlistId: Int, songCount: Int) async {
        var allTracks: [Track] = []
        let pageSize = 500
        var offset = 0

        while true {
            if Task.isCancelled { return }
            await MainActor.run {
                self.loadingProgress = "正在加载 \(allTracks.count)/\(songCount)..."
            }

            do {
                let pageTracks = try await MusicService.shared.getPlaylistAllTracks(
                    id: playlistId,
                    limit: pageSize,
                    offset: offset
                )

                if pageTracks.isEmpty {
                    break
                }

                allTracks.append(contentsOf: pageTracks)
                offset += pageSize

                if pageTracks.count < pageSize {
                    break
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
                return
            }
        }

        await MainActor.run {
            self.tracks = allTracks
            self.isLoading = false
            self.loadingProgress = ""
        }
    }
}

// MARK: - 喜欢的音乐页面
struct CloudLikedSongsView: View {
    let playlistId: Int
    let songCount: Int
    @StateObject private var likedStore: LikedSongsStore = .shared
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            ScrollView {
                VStack(spacing: 0) {
                    likedHeader
                    playAllButton

                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView()
                            if !loadingProgress.isEmpty {
                                Text(loadingProgress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                LikedTrackRow(track: track, index: index + 1) {
                                    playTrack(track, index: index)
                                }
                                if index < tracks.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("喜欢的音乐")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            likedStore.ensureLoaded(playlistId: playlistId, songCount: songCount)
        }
        .onReceive(NotificationCenter.default.publisher(for: .likedSongsChanged)) { _ in
            likedStore.refresh(playlistId: playlistId, songCount: songCount)
        }
    }

    private var likedHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
            .frame(width: 180, height: 180)
            .cornerRadius(12)
            .shadow(color: .pink.opacity(0.3), radius: 10, x: 0, y: 5)
            
            Text("\(songCount) 首喜欢的歌曲")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private var playAllButton: some View {
        Button(action: playAll) {
            HStack {
                Image(systemName: "play.fill")
                Text("播放全部")
                Text("(\(tracks.count))").foregroundColor(.white.opacity(0.8))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.pink, .red], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(25)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
        .disabled(tracks.isEmpty)
    }

    private func playTrack(_ track: Track, index: Int) {
        audioPlayer.setPlaylist(tracks, startAt: index)
    }

    private func playAll() {
        guard !tracks.isEmpty else { return }
        audioPlayer.setPlaylist(tracks, startAt: 0)
    }

    private var tracks: [Track] { likedStore.tracks }
    private var isLoading: Bool { likedStore.isLoading }
    private var loadingProgress: String { likedStore.loadingProgress }
}

// MARK: - 收藏的专辑页面
struct CloudAlbumsView: View {
    let albums: [CloudAlbum]
    @EnvironmentObject var themeManager: ThemeManager
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink {
                            CloudAlbumDetailView(album: album)
                        } label: {
                            AlbumCardView(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("收藏的专辑")
    }
}

// MARK: - 专辑卡片视图
struct AlbumCardView: View {
    let album: CloudAlbum
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let coverUrl = album.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(height: 160)
                .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 160)
                    .overlay(
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(album.artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 专辑详情页面
struct CloudAlbumDetailView: View {
    let album: CloudAlbum
    @State private var tracks: [CloudTrack] = []
    @State private var isLoading = true
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(ThemeManager.shared)
            ScrollView {
                VStack(spacing: 0) {
                    albumHeader
                    playAllButton

                    if isLoading {
                        ProgressView().padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                CloudTrackRow(track: track, index: index + 1) {
                                    playTrack(track, index: index)
                                }
                                if index < tracks.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTracks() }
    }
    
    private var albumHeader: some View {
        VStack(spacing: 12) {
            if let coverUrl = album.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .frame(width: 180, height: 180)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            }
            
            Text(album.artistName)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private var playAllButton: some View {
        Button(action: playAll) {
            HStack {
                Image(systemName: "play.fill")
                Text("播放全部")
                Text("(\(tracks.count))").foregroundColor(.white.opacity(0.8))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.purple, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(25)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
        .disabled(tracks.isEmpty)
    }
    
    private func loadTracks() async {
        do {
            tracks = try await MusicService.shared.getAlbumTracks(albumId: album.id)
        } catch {
            #if DEBUG
            print("加载专辑歌曲失败: \(error)")
            #endif
        }
        isLoading = false
    }

    private func playTrack(_ track: CloudTrack, index: Int) {
        let playerTracks = tracks.map { $0.toTrack() }
        audioPlayer.setPlaylist(playerTracks, startAt: index)
    }

    private func playAll() {
        guard !tracks.isEmpty else { return }
        let playerTracks = tracks.map { $0.toTrack() }
        audioPlayer.setPlaylist(playerTracks, startAt: 0)
    }
}

// MARK: - 喜欢音乐歌曲行视图
struct LikedTrackRow: View {
    let track: Track
    let index: Int
    let onTap: () -> Void
    @ObservedObject private var audioPlayer = AudioPlayer.shared

    private var isPlaying: Bool {
        audioPlayer.currentTrack?.id == track.id
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 14))
                    .foregroundColor(isPlaying ? .red : .secondary)
                    .frame(width: 30)

                if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isPlaying ? .red : .primary)
                        .lineLimit(1)

                    Text(track.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isPlaying {
                    if #available(iOS 17.0, *) {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .symbolEffect(.variableColor.iterative)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 云端歌曲行视图
struct CloudTrackRow: View {
    let track: CloudTrack
    let index: Int
    let onTap: () -> Void
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    private var isPlaying: Bool {
        audioPlayer.currentTrack?.id == track.id
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(index)")
                    .font(.system(size: 14))
                    .foregroundColor(isPlaying ? .red : .secondary)
                    .frame(width: 30)
                
                if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isPlaying ? .red : .primary)
                        .lineLimit(1)
                    
                    Text(track.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isPlaying {
                    if #available(iOS 17.0, *) {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .symbolEffect(.variableColor.iterative)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(AuthViewModel())
    }
}
