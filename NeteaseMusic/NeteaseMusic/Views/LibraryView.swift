import SwiftUI

// MARK: - Apple Music 液态玻璃风格音乐库页
struct LibraryView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var localStorage = LocalStorageService.shared
    @ObservedObject private var localMusicService = LocalMusicService.shared
    @State private var showLogin = false
    @State private var cloudPlaylists: [CloudPlaylist] = []
    @State private var cloudAlbums: [CloudAlbum] = []
    @State private var cloudPodcasts: [CloudDJRadio] = []
    @State private var createdPodcasts: [CloudDJRadio] = []
    @State private var collectedPrograms: [CloudDJProgram] = []
    @State private var likedSongIds: [Int] = []
    @State private var cloudDiskCount: Int?
    @State private var isLoadingCloud = false
    @State private var hasAttemptedCloudLoad = false
    
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
        .navigationDestination(for: LibraryPushRoute.self) { route in
            libraryDestination(for: route)
        }
        .immersiveNavigationChrome()
        .navigationTitle("我的")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(value: LibraryPushRoute.settings) {
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
        .task(id: authViewModel.currentUser?.userId ?? 0) {
            CrashLogStore.shared.breadcrumb("LibraryView.task loggedIn=\(authViewModel.isLoggedIn) uid=\(authViewModel.currentUser?.userId ?? 0)")
            guard authViewModel.isLoggedIn else { return }
            if authViewModel.currentUser == nil {
                await authViewModel.fetchCurrentUser()
                return
            }
            await loadCloudData()
        }
        .onChangeCompat(of: authViewModel.isLoggedIn) { _, isLoggedIn in
            if !isLoggedIn {
                cloudPlaylists = []
                cloudAlbums = []
                cloudPodcasts = []
                createdPodcasts = []
                collectedPrograms = []
                likedSongIds = []
                cloudDiskCount = nil
                isLoadingCloud = false
                hasAttemptedCloudLoad = false
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
            hasAttemptedCloudLoad = true
            CrashLogStore.shared.breadcrumb("loadCloudData skip no-uid")
            return
        }
        guard !isLoadingCloud else { return }
        isLoadingCloud = true
        hasAttemptedCloudLoad = true
        CrashLogStore.shared.breadcrumb("loadCloudData begin uid=\(userId)")

        let loadedPlaylists = await optionalLoad { try await userService.getUserPlaylists(uid: userId) } ?? []
        CrashLogStore.shared.breadcrumb("cloud playlists=\(loadedPlaylists.count)")
        cloudPlaylists = loadedPlaylists
        isLoadingCloud = false

        let loadedLikeIds = await optionalLoad { try await userService.getLikeList(uid: userId) } ?? []
        CrashLogStore.shared.breadcrumb("cloud likes=\(loadedLikeIds.count)")
        likedSongIds = loadedLikeIds

        let loadedAlbums = await optionalLoad { try await userService.getAlbumSublist() } ?? []
        CrashLogStore.shared.breadcrumb("cloud albums=\(loadedAlbums.count)")
        cloudAlbums = loadedAlbums
        CrashLogStore.shared.breadcrumb("loadCloudData core done")
    }

    private func optionalLoad<T>(_ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch {
            CrashLogStore.shared.breadcrumb("optionalLoad error=\(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - 液态玻璃用户区域
    private var liquidGlassUserSection: some View {
        VStack(spacing: 0) {
            if authViewModel.isLoggedIn {
                NavigationLink(value: LibraryPushRoute.profile) {
                    LiquidGlassUserCard(
                        avatarUrl: authViewModel.currentUser?.avatarUrl.flatMap { URL(string: $0) },
                        nickname: {
                            if let name = authViewModel.currentUser?.nickname, !name.isEmpty {
                                return name
                            }
                            return authViewModel.currentUser == nil ? "正在加载资料" : "网易云用户"
                        }(),
                        level: authViewModel.currentUser?.level
                    )
                }
                .buttonStyle(.plain)
                .disabled(authViewModel.currentUser == nil)
            } else {
                Button(action: { showLogin = true }) {
                    LiquidGlassLoginCard()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - 网易Max 云端音乐区域
    private var cloudMusicSection: some View {
        LiquidGlassSection(title: "网易Max") {
            if isLoadingCloud && cloudPlaylists.isEmpty && !hasAttemptedCloudLoad {
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
                    NavigationLink(value: LibraryPushRoute.likedMusic) { likedMusicCard }
                        .buttonStyle(.plain)
                    NavigationLink(value: LibraryPushRoute.playlists) {
                        CloudFeatureCard(
                            icon: "music.note.list",
                            iconColor: .red,
                            title: "我的歌单",
                            count: cloudPlaylists.filter { !$0.isLikedPlaylist }.count
                        )
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: LibraryPushRoute.albums) {
                        CloudFeatureCard(
                            icon: "square.stack",
                            iconColor: .purple,
                            title: "收藏专辑",
                            count: cloudAlbums.count
                        )
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: LibraryPushRoute.collectedPrograms) {
                        CloudFeatureCard(
                            icon: "bookmark.fill",
                            iconColor: .teal,
                            title: "收藏的单集",
                            count: collectedPrograms.count
                        )
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: LibraryPushRoute.podcasts) {
                        CloudFeatureCard(
                            icon: "mic.fill",
                            iconColor: .orange,
                            title: "播客",
                            count: createdPodcasts.count + followedPodcasts.count
                        )
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: LibraryPushRoute.cloudDisk) {
                        CloudFeatureCard(
                            icon: "cloud.fill",
                            iconColor: .blue,
                            title: "我的云盘",
                            count: cloudDiskCount
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
    }

    private var likedMusicCard: some View {
        CloudFeatureCard(
            icon: "heart.fill",
            iconColor: .pink,
            title: "喜欢的音乐",
            count: likedSongIds.count
        )
    }

    private var followedPodcasts: [CloudDJRadio] {
        let createdIds = Set(createdPodcasts.map(\.id))
        return cloudPodcasts.filter { !createdIds.contains($0.id) }
    }

    @ViewBuilder
    private func libraryDestination(for route: LibraryPushRoute) -> some View {
        switch route {
        case .settings:
            SettingsView()
                .environmentObject(themeManager)
        case .profile:
            ProfileCardView()
                .environmentObject(authViewModel)
                .environmentObject(themeManager)
        case .likedMusic:
            LikedMusicDestination(
                playlist: cloudPlaylists.first(where: { $0.isLikedPlaylist }),
                songCount: likedSongIds.count
            )
        case .playlists:
            CloudPlaylistsView(playlists: cloudPlaylists.filter { !$0.isLikedPlaylist })
                .environmentObject(themeManager)
        case .albums:
            CloudAlbumsView(albums: cloudAlbums)
                .environmentObject(themeManager)
        case .collectedPrograms:
            CloudCollectedProgramsView(programs: [])
        case .podcasts:
            CloudPodcastHubView(created: [], followed: [])
                .environmentObject(authViewModel)
        case .cloudDisk:
            CloudDiskView()
                .environmentObject(themeManager)
        case .localSongs:
            LocalMusicView()
                .environmentObject(themeManager)
        case .localFavorites:
            FavoritesView()
                .environmentObject(themeManager)
        case .playHistory:
            PlayHistoryView()
                .environmentObject(themeManager)
        }
    }

    // MARK: - 液态玻璃收藏库内容
    private var liquidGlassLibraryContent: some View {
        VStack(spacing: 20) {
            // 本地音乐库
            LiquidGlassSection(title: "本地音乐库") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 16) {
                    NavigationLink(value: LibraryPushRoute.localSongs) {
                        CloudFeatureCard(
                            icon: "music.note.house.fill",
                            iconColor: .green,
                            title: "本地歌曲",
                            count: localMusicService.localTracks.count
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: LibraryPushRoute.localFavorites) {
                        CloudFeatureCard(
                            icon: "heart.fill",
                            iconColor: .red,
                            title: "我喜欢的音乐",
                            count: localStorage.favoritesCount
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: LibraryPushRoute.playHistory) {
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

private enum LibraryPushRoute: Hashable {
    case settings
    case profile
    case likedMusic
    case playlists
    case albums
    case collectedPrograms
    case podcasts
    case cloudDisk
    case localSongs
    case localFavorites
    case playHistory
}

private struct LikedMusicDestination: View {
    let playlist: CloudPlaylist?
    let songCount: Int

    var body: some View {
        if let playlist {
            CloudLikedSongsView(playlist: playlist, songCount: songCount)
        } else {
            ZStack {
                ThemedBackground()
                    .environmentObject(ThemeManager.shared)
                VStack(spacing: 10) {
                    Image(systemName: "heart")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("还没有喜欢的音乐")
                        .foregroundColor(.secondary)
                }
            }
            .immersiveNavigationChrome()
            .navigationTitle("喜欢的音乐")
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
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var sortMode: PlaylistSortMode = .original
    @State private var showDownloadSheet = false
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @EnvironmentObject var authViewModel: AuthViewModel

    private var displayedTracks: [CloudTrack] {
        PlaylistTrackFilter.cloud(tracks, search: searchText, sort: sortMode)
    }

    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(ThemeManager.shared)
            ScrollView {
                VStack(spacing: 0) {
                    PlaylistPullSearchSensor(isSearching: $isSearching)
                    if isSearching {
                        PlaylistInlineSearchBar(text: $searchText, placeholder: "搜索歌单内歌曲") {
                            isSearching = false
                            searchText = ""
                        }
                    } else {
                        PlaylistPageHeader(
                            title: playlist.name,
                            coverUrl: playlist.coverUrl,
                            avatarUrl: authViewModel.currentUser?.avatarUrl,
                            nickname: authViewModel.currentUser?.nickname ?? "",
                            trackCount: tracks.count > 0 ? tracks.count : (playlist.trackCount ?? 0),
                            playCount: playlist.playCount
                        )
                        PlaylistPlayAllBar(
                            count: displayedTracks.count,
                            onPlayAll: playAll,
                            onDownloadAll: downloadAll
                        )
                    }

                    if isLoading {
                        ProgressView().padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                                CloudTrackRow(track: track, index: index + 1) {
                                    playTrack(track, index: index)
                                }
                                if index < displayedTracks.count - 1 {
                                    Divider().padding(.leading, 86)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100)
            }
            .coordinateSpace(name: "playlistPull")
        }
        .immersiveNavigationChrome()
        .navigationTitle(isSearching ? "搜索歌单内歌曲" : playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isSearching {
                PlaylistMoreToolbar(sortMode: $sortMode, onFind: {
                    isSearching = true
                })
            }
        }
        .sheet(isPresented: $showDownloadSheet) {
            PlaylistDownloadSheet(tracks: displayedTracks.map { $0.toTrack() })
        }
        .task { await loadTracks() }
    }

    private func downloadAll() {
        showDownloadSheet = true
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
        let playerTracks = displayedTracks.map { $0.toTrack() }
        audioPlayer.setPlaylist(playerTracks, startAt: index)
    }
    
    private func playAll() {
        guard !displayedTracks.isEmpty else { return }
        let playerTracks = displayedTracks.map { $0.toTrack() }
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
    let playlist: CloudPlaylist
    let songCount: Int
    @ObservedObject private var likedStore = LikedSongsStore.shared
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var sortMode: PlaylistSortMode = .original
    @State private var showDownloadSheet = false

    private var playlistId: Int { playlist.id }
    private var displayedTracks: [Track] {
        PlaylistTrackFilter.tracks(tracks, search: searchText, sort: sortMode)
    }

    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            ScrollView {
                VStack(spacing: 0) {
                    PlaylistPullSearchSensor(isSearching: $isSearching)
                    if isSearching {
                        PlaylistInlineSearchBar(text: $searchText, placeholder: "搜索歌单内歌曲") {
                            isSearching = false
                            searchText = ""
                        }
                    } else {
                        PlaylistPageHeader(
                            title: playlist.name,
                            coverUrl: playlist.coverUrl,
                            avatarUrl: authViewModel.currentUser?.avatarUrl,
                            nickname: authViewModel.currentUser?.nickname ?? "",
                            trackCount: tracks.count > 0 ? tracks.count : songCount,
                            playCount: playlist.playCount
                        )
                        PlaylistPlayAllBar(
                            count: displayedTracks.count,
                            onPlayAll: playAll,
                            onDownloadAll: downloadAll
                        )
                    }

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
                            ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                                LikedTrackRow(track: track, index: index + 1) {
                                    playTrack(track, index: index)
                                }
                                if index < displayedTracks.count - 1 {
                                    Divider().padding(.leading, 86)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100)
            }
            .coordinateSpace(name: "playlistPull")
        }
        .immersiveNavigationChrome()
        .navigationTitle(isSearching ? "搜索歌单内歌曲" : "喜欢的音乐")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isSearching {
                PlaylistMoreToolbar(sortMode: $sortMode, onFind: {
                    isSearching = true
                })
            }
        }
        .sheet(isPresented: $showDownloadSheet) {
            PlaylistDownloadSheet(tracks: displayedTracks)
        }
        .onAppear {
            likedStore.ensureLoaded(playlistId: playlistId, songCount: songCount)
        }
        .onReceive(NotificationCenter.default.publisher(for: .likedSongsChanged)) { _ in
            likedStore.refresh(playlistId: playlistId, songCount: songCount)
        }
    }

    private func playTrack(_ track: Track, index: Int) {
        audioPlayer.setPlaylist(displayedTracks, startAt: index)
    }

    private func playAll() {
        guard !displayedTracks.isEmpty else { return }
        audioPlayer.setPlaylist(displayedTracks, startAt: 0)
    }

    private func downloadAll() {
        showDownloadSheet = true
    }

    private var tracks: [Track] { likedStore.tracks }
    private var isLoading: Bool { likedStore.isLoading }
    private var loadingProgress: String { likedStore.loadingProgress }
}

// MARK: - 收藏的专辑页面
struct CloudAlbumsView: View {
    let albums: [CloudAlbum]
    @State private var loaded: [CloudAlbum] = []
    @EnvironmentObject var themeManager: ThemeManager

    private var items: [CloudAlbum] {
        loaded.isEmpty ? albums : loaded
    }
    
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
                    ForEach(items) { album in
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
        .task {
            if albums.isEmpty {
                loaded = (try? await UserService.shared.getAlbumSublist()) ?? []
            }
        }
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
                    HStack(spacing: 6) {
                        Text(track.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isPlaying ? .red : .primary)
                            .lineLimit(1)
                        if track.isVIP {
                            VIPBadge()
                        }
                    }

                    Text(track.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isPlaying {
                    playingWaveform
                } else {
                    Text(track.durationText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var playingWaveform: some View {
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
                    HStack(spacing: 6) {
                        Text(track.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isPlaying ? .red : .primary)
                            .lineLimit(1)
                        if track.isVIP {
                            VIPBadge()
                        }
                    }
                    
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
                } else {
                    Text(track.durationText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistPageHeader: View {
    let title: String
    let coverUrl: String?
    let avatarUrl: String?
    let nickname: String
    let trackCount: Int
    let playCount: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if let coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.2))
                    }
                } else {
                    LinearGradient(colors: [.pink, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(
                            Image(systemName: "heart.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.white)
                        )
                }
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.2))
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                    }
                    Text(nickname)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(metaText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var metaText: String {
        if let playCount, playCount > 0 {
            return "\(trackCount) 首 · \(Self.formatPlayCount(playCount))次播放"
        }
        return "\(trackCount) 首"
    }

    private static func formatPlayCount(_ count: Int) -> String {
        if count >= 100000000 {
            return String(format: "%.1f亿", Double(count) / 100000000)
        }
        if count >= 10000 {
            return String(format: "%.1f万", Double(count) / 10000)
        }
        return "\(count) "
    }
}

struct PlaylistPlayAllBar: View {
    let count: Int
    let onPlayAll: () -> Void
    let onDownloadAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlayAll) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("播放全部")
                    Text("(\(count))").foregroundColor(.white.opacity(0.85))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.red.opacity(0.95), .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
            }
            .disabled(count == 0)

            Button(action: onDownloadAll) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .disabled(count == 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

struct VIPBadge: View {
    var body: some View {
        Text("VIP")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.red)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.red.opacity(0.85), lineWidth: 1)
            )
    }
}

enum PlaylistSortMode: String, CaseIterable {
    case original
    case name
    case artist
    case album
    case duration

    var title: String {
        switch self {
        case .original: return "默认排序"
        case .name: return "歌曲名"
        case .artist: return "歌手名"
        case .album: return "专辑名"
        case .duration: return "时长"
        }
    }
}

enum PlaylistTrackFilter {
    static func tracks(_ tracks: [Track], search: String, sort: PlaylistSortMode) -> [Track] {
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = keyword.isEmpty
            ? tracks
            : tracks.filter {
                $0.name.lowercased().contains(keyword) || $0.artistName.lowercased().contains(keyword)
            }
        switch sort {
        case .original: return filtered
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .artist: return filtered.sorted { $0.artistName.localizedStandardCompare($1.artistName) == .orderedAscending }
        case .album: return filtered.sorted { $0.albumName.localizedStandardCompare($1.albumName) == .orderedAscending }
        case .duration: return filtered.sorted { $0.durationSeconds < $1.durationSeconds }
        }
    }

    static func cloud(_ tracks: [CloudTrack], search: String, sort: PlaylistSortMode) -> [CloudTrack] {
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = keyword.isEmpty
            ? tracks
            : tracks.filter {
                $0.name.lowercased().contains(keyword) || $0.artistName.lowercased().contains(keyword)
            }
        switch sort {
        case .original: return filtered
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .artist: return filtered.sorted { $0.artistName.localizedStandardCompare($1.artistName) == .orderedAscending }
        case .album: return filtered.sorted { $0.albumName.localizedStandardCompare($1.albumName) == .orderedAscending }
        case .duration: return filtered.sorted { $0.durationSeconds < $1.durationSeconds }
        }
    }

    static func programs(_ programs: [CloudDJProgram], search: String, sort: PlaylistSortMode) -> [CloudDJProgram] {
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = keyword.isEmpty
            ? programs
            : programs.filter {
                $0.name.lowercased().contains(keyword)
                    || ($0.radio?.name ?? "").lowercased().contains(keyword)
            }
        switch sort {
        case .original: return filtered
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .artist: return filtered.sorted {
            ($0.radio?.name ?? "").localizedStandardCompare($1.radio?.name ?? "") == .orderedAscending
        }
        case .album: return filtered.sorted {
            ($0.radio?.name ?? "").localizedStandardCompare($1.radio?.name ?? "") == .orderedAscending
        }
        case .duration: return filtered.sorted { $0.durationMS < $1.durationMS }
        }
    }
}

struct PodcastCoverImage: View {
    let url: String?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                CachedAsyncImage(url: parsed, targetSize: CGSize(width: size * 2, height: size * 2)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 50 ? 8 : 6))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.18))
            .overlay(
                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.32))
                    .foregroundColor(.secondary)
            )
    }
}

struct PlaylistPullSearchSensor: View {
    @Binding var isSearching: Bool
    @State private var armed = false
    @State private var baseline: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("playlistPull")).minY
            Color.clear
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        baseline = minY
                        armed = true
                    }
                }
                .onChangeCompat(of: minY) { _, value in
                    guard armed, !isSearching else { return }
                    if baseline == nil {
                        baseline = value
                    }
                    if let base = baseline, value - base > 72 {
                        isSearching = true
                    }
                }
        }
        .frame(height: 0)
        .allowsHitTesting(false)
    }
}

struct PlaylistInlineSearchBar: View {
    @Binding var text: String
    var placeholder: String
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06), in: Capsule())

            Button("取消", action: onCancel)
                .font(.system(size: 15))
                .foregroundColor(.red)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct PlaylistDownloadSheet: View {
    let tracks: [Track]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuality: MusicQuality = MusicSourceConfig.shared.quality
    @State private var selectedIds: Set<Int> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                qualityPicker
                Divider()
                selectionBar
                trackList
            }
            .navigationTitle("下载歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("下载") { startDownload() }
                        .disabled(selectedIds.isEmpty)
                }
            }
            .onAppear {
                selectedIds = Set(tracks.map(\.id))
            }
        }
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("下载音质")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MusicQuality.allCases) { quality in
                        Button {
                            selectedQuality = quality
                        } label: {
                            Text(quality.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedQuality == quality ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selectedQuality == quality ? Color.red : Color.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var selectionBar: some View {
        HStack {
            Button(selectedIds.count == tracks.count ? "取消全选" : "全选") {
                if selectedIds.count == tracks.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(tracks.map(\.id))
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.red)
            Spacer()
            Text("已选 \(selectedIds.count)/\(tracks.count) 首")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var trackList: some View {
        List {
            ForEach(tracks) { track in
                Button {
                    if selectedIds.contains(track.id) {
                        selectedIds.remove(track.id)
                    } else {
                        selectedIds.insert(track.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedIds.contains(track.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedIds.contains(track.id) ? .red : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(track.name)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if track.isVIP {
                                    VIPBadge()
                                }
                            }
                            Text(track.artistName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func startDownload() {
        let chosen = tracks.filter { selectedIds.contains($0.id) }
        SongDownloadService.shared.downloadBatch(tracks: chosen, quality: selectedQuality.rawValue)
        dismiss()
    }
}

struct PlaylistMoreToolbar: ToolbarContent {
    @Binding var sortMode: PlaylistSortMode
    var onFind: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    onFind()
                } label: {
                    Label("查找", systemImage: "magnifyingglass")
                }
                Menu {
                    ForEach(PlaylistSortMode.allCases, id: \.self) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            if sortMode == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                } label: {
                    Label("排序", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
            }
        }
    }
}

struct CloudCollectedProgramsView: View {
    let programs: [CloudDJProgram]
    @State private var loaded: [CloudDJProgram] = []
    @State private var isLoading = true
    @ObservedObject private var audioPlayer = AudioPlayer.shared

    private var items: [CloudDJProgram] {
        loaded.isEmpty ? programs : loaded
    }

    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(ThemeManager.shared)
            if isLoading && items.isEmpty {
                ProgressView()
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("还没有收藏的单集")
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, program in
                            Button {
                                play(program, index: index)
                            } label: {
                                HStack(spacing: 14) {
                                    PodcastCoverImage(url: program.artworkUrl, size: 56)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(program.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                        Text("\(program.radio?.name ?? "") · \(program.durationText)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < items.count - 1 {
                                Divider().padding(.leading, 82)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("收藏的单集")
        .task { await reload() }
    }

    private func reload() async {
        loaded = (try? await UserService.shared.getDJProgramSublist()) ?? programs
        isLoading = false
    }

    private func play(_ program: CloudDJProgram, index: Int) {
        let tracks = items.map { $0.toTrack(fallbackCover: $0.radio?.picUrl) }
        guard !tracks.isEmpty else { return }
        audioPlayer.setPlaylist(tracks, startAt: index)
    }
}

struct CloudPodcastHubView: View {
    let created: [CloudDJRadio]
    let followed: [CloudDJRadio]
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var loadedCreated: [CloudDJRadio] = []
    @State private var loadedFollowed: [CloudDJRadio] = []
    @State private var isLoading = true

    private var createdItems: [CloudDJRadio] {
        loadedCreated.isEmpty ? created : loadedCreated
    }

    private var followedItems: [CloudDJRadio] {
        loadedFollowed.isEmpty ? followed : loadedFollowed
    }

    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(ThemeManager.shared)
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink {
                        CloudPodcastsView(radios: createdItems, title: "我创建的播客")
                    } label: {
                        CloudFeatureCard(
                            icon: "mic.fill",
                            iconColor: .orange,
                            title: "我创建的播客",
                            count: isLoading && createdItems.isEmpty ? nil : createdItems.count
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CloudPodcastsView(radios: followedItems, title: "我关注的播客")
                    } label: {
                        CloudFeatureCard(
                            icon: "antenna.radiowaves.left.and.right",
                            iconColor: .teal,
                            title: "我关注的播客",
                            count: isLoading && followedItems.isEmpty ? nil : followedItems.count
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("播客")
        .navigationBarTitleDisplayMode(.large)
        .task {
            CrashLogStore.shared.breadcrumb("podcast hub load uid=\(authViewModel.currentUser?.userId ?? 0)")
            let uid = authViewModel.currentUser?.userId ?? 0
            if uid != 0 {
                loadedCreated = (try? await UserService.shared.getCreatedDJRadios(uid: uid)) ?? created
                CrashLogStore.shared.breadcrumb("podcast created=\(loadedCreated.count)")
            }
            loadedFollowed = (try? await UserService.shared.getDJSublist()) ?? followed
            CrashLogStore.shared.breadcrumb("podcast followed=\(loadedFollowed.count)")
            isLoading = false
        }
    }
}

struct CloudPodcastsView: View {
    let radios: [CloudDJRadio]
    var title: String = "我的播客"

    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(ThemeManager.shared)
            if radios.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "mic")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("还没有播客")
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(radios) { radio in
                            NavigationLink {
                                CloudPodcastDetailView(radio: radio)
                            } label: {
                                HStack(spacing: 14) {
                                    PodcastCoverImage(url: radio.coverUrl, size: 60)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(radio.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Text("\(radio.programCount ?? 0) 期 · \(radio.creatorName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .glassEffectRounded(cornerRadius: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle(title)
    }
}

struct CloudPodcastDetailView: View {
    let radio: CloudDJRadio
    @State private var programs: [CloudDJProgram] = []
    @State private var createdRadios: [CloudDJRadio] = []
    @State private var isLoading = true
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var sortMode: PlaylistSortMode = .original
    @State private var showDownloadSheet = false
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @EnvironmentObject var authViewModel: AuthViewModel

    private var displayedPrograms: [CloudDJProgram] {
        PlaylistTrackFilter.programs(programs, search: searchText, sort: sortMode)
    }

    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(ThemeManager.shared)
            ScrollView {
                VStack(spacing: 0) {
                    PlaylistPullSearchSensor(isSearching: $isSearching)
                    if isSearching {
                        PlaylistInlineSearchBar(text: $searchText, placeholder: "搜索节目") {
                            isSearching = false
                            searchText = ""
                        }
                    } else {
                        PlaylistPageHeader(
                            title: radio.name,
                            coverUrl: radio.coverUrl,
                            avatarUrl: radio.coverUrl,
                            nickname: radio.creatorName,
                            trackCount: programs.count > 0 ? programs.count : (radio.programCount ?? 0),
                            playCount: radio.playCount
                        )
                        PlaylistPlayAllBar(
                            count: displayedPrograms.count,
                            onPlayAll: playAll,
                            onDownloadAll: { showDownloadSheet = true }
                        )
                    }
                    if isLoading {
                        ProgressView().padding(.top, 40)
                    } else if displayedPrograms.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "mic")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(programs.isEmpty ? "暂无节目" : "没有找到相关节目")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(displayedPrograms.enumerated()), id: \.offset) { index, program in
                                HStack(spacing: 12) {
                                    Button {
                                        play(program, index: index)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text("\(index + 1)")
                                                .font(.system(size: 14))
                                                .foregroundColor(.secondary)
                                                .frame(width: 30)
                                            PodcastCoverImage(
                                                url: program.artworkUrl ?? radio.coverUrl,
                                                size: 44
                                            )
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(program.name)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(2)
                                                Text(program.durationText)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    programActionMenu(program)
                                }
                                .padding(.vertical, 10)
                                .contextMenu {
                                    programActionButtons(program)
                                }
                                if index < displayedPrograms.count - 1 {
                                    Divider().padding(.leading, 86)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 100)
            }
            .coordinateSpace(name: "playlistPull")
        }
        .immersiveNavigationChrome()
        .navigationTitle(isSearching ? "搜索节目" : radio.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isSearching {
                PlaylistMoreToolbar(sortMode: $sortMode, onFind: {
                    isSearching = true
                })
            }
        }
        .sheet(isPresented: $showDownloadSheet) {
            PlaylistDownloadSheet(tracks: displayedPrograms.map { $0.toTrack(fallbackCover: radio.coverUrl) })
        }
        .task { await loadPrograms() }
    }

    @ViewBuilder
    private func programActionMenu(_ program: CloudDJProgram) -> some View {
        Menu {
            programActionButtons(program)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func programActionButtons(_ program: CloudDJProgram) -> some View {
        Button {
            Task { await collectProgram(program) }
        } label: {
            Label("收藏到单集", systemImage: "bookmark")
        }
        if !createdRadios.isEmpty {
            Menu {
                ForEach(createdRadios) { mine in
                    Button(mine.name) {
                        Task { await addProgram(program, to: mine) }
                    }
                }
            } label: {
                Label("加入自建播客", systemImage: "plus.circle")
            }
        }
    }

    private func loadPrograms() async {
        do {
            programs = try await UserService.shared.getDJPrograms(rid: radio.id)
        } catch {
            #if DEBUG
            print("加载播客失败: \(error)")
            #endif
        }
        if let uid = authViewModel.currentUser?.userId {
            createdRadios = (try? await UserService.shared.getCreatedDJRadios(uid: uid)) ?? []
        }
        isLoading = false
    }

    private func collectProgram(_ program: CloudDJProgram) async {
        do {
            try await UserService.shared.subscribeDJProgram(id: program.id, sub: true)
            AppToast.show("已收藏到单集")
        } catch {
            AppToast.show(error.localizedDescription)
        }
    }

    private func addProgram(_ program: CloudDJProgram, to radio: CloudDJRadio) async {
        do {
            try await UserService.shared.addDJProgram(program.id, toRadio: radio.id)
            AppToast.show("已加入 \(radio.name)")
        } catch {
            AppToast.show(error.localizedDescription)
        }
    }

    private func play(_ program: CloudDJProgram, index: Int) {
        let tracks = displayedPrograms.map { $0.toTrack(fallbackCover: radio.coverUrl) }
        guard !tracks.isEmpty else { return }
        audioPlayer.setPlaylist(tracks, startAt: index)
    }

    private func playAll() {
        let tracks = displayedPrograms.map { $0.toTrack(fallbackCover: radio.coverUrl) }
        guard !tracks.isEmpty else { return }
        audioPlayer.setPlaylist(tracks, startAt: 0)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(AuthViewModel())
    }
}
