import SwiftUI

// MARK: - Apple Music 液态玻璃风格发现页
struct DiscoverView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var playlists: [RecommendPlaylist] = []
    @State private var banners: [Banner] = []
    @State private var isLoading = true
    @State private var currentBannerIndex = 0
    @State private var errorMessage: String?
    @State private var selectedPlaylistId: Int?
    @State private var navigateToPlaylist = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showQuickMenu = false
    @State private var recentlyPlayed: [Track] = []
    @State private var newAlbums: [NewAlbum] = []
    @State private var topArtists: [SearchArtistResult] = []
    
    private let musicService = MusicService.shared
    private let storageService = LocalStorageService.shared
    
    /// iPad regular 宽度下使用更多列
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
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
                VStack(spacing: 28) {
                    if isLoading && banners.isEmpty {
                        BannerSkeletonView()
                            .padding(.top, 12)
                    } else if !banners.isEmpty {
                        liquidGlassBannerView
                            .padding(.top, 12)
                            .staggeredEntrance(index: 0)
                    }

                    quickAccessSection
                        .staggeredEntrance(index: 1)

                    liquidGlassPlaylistSection
                        .staggeredEntrance(index: 2)

                    newAlbumsSection
                        .staggeredEntrance(index: 3)

                    recommendedArtistsSection
                        .staggeredEntrance(index: 4)

                    if isLoading && recentlyPlayed.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(spacing: 8) {
                                SkeletonBlock(width: 18, height: 18, cornerRadius: 4)
                                SkeletonBlock(width: 80, height: 20, cornerRadius: 4)
                            }
                            .padding(.horizontal, 20)
                            HorizontalCardSkeletonView(count: 4)
                        }
                    } else {
                        recentlyPlayedSection
                            .staggeredEntrance(index: 5)
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                QuickMenuButton(showMenu: $showQuickMenu)
            }
        }
        .overlay {
            if showQuickMenu {
                QuickAccessMenu(isPresented: $showQuickMenu)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
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
                LiquidGlassBackground()
            case .strangerThings:
                StrangerThingsBackground()
            }
        }
    }
    
    // MARK: - 液态玻璃 Banner 视图
    private var liquidGlassBannerView: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(banners, id: \.targetId) { banner in
                        AppleMusicBannerCard(
                            title: banner.typeTitle ?? "",
                            subtitle: bannerSubtitle(for: banner.typeTitle ?? ""),
                            gradientColors: themedBannerGradient(for: banner.typeTitle ?? "")
                        ) {
                            handleBannerTap(banner)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationDestination(isPresented: $navigateToPlaylist) {
                if let playlistId = selectedPlaylistId {
                    PlaylistDetailView(
                        playlistId: playlistId,
                        playlistName: "",
                        coverUrl: nil
                    )
                }
            }
        }
    }
    
    // MARK: - 快捷入口区域
    private var quickAccessSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                NavigationLink(destination: FeaturedArtistsView()) {
                    QuickAccessCard(
                        icon: "star.fill",
                        title: "专属推荐",
                        gradient: [Color(red: 0.9, green: 0.7, blue: 0.3), Color(red: 0.8, green: 0.2, blue: 0.3)]
                    )
                }
                
                NavigationLink(destination: PersonalFMView()) {
                    QuickAccessCard(
                        icon: "radio",
                        title: "私人FM",
                        gradient: [.green, .mint]
                    )
                }
                
                NavigationLink(destination: HeartbeatModeView()) {
                    QuickAccessCard(
                        icon: "heart.circle.fill",
                        title: "心动模式",
                        gradient: [.pink, .red]
                    )
                }
                
                NavigationLink(destination: RadarPlaylistView()) {
                    QuickAccessCard(
                        icon: "dot.radiowaves.left.and.right",
                        title: "雷达歌单",
                        gradient: [.blue, .cyan]
                    )
                }
                
                NavigationLink(destination: ToplistView()) {
                    QuickAccessCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "排行榜",
                        gradient: [.purple, .indigo]
                    )
                }
                
                NavigationLink(destination: CoverFlow3DView()) {
                    QuickAccessCard(
                        icon: "square.stack.3d.up",
                        title: "3D专辑",
                        gradient: [.orange, .yellow]
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 主题感知 Banner 渐变
    private func themedBannerGradient(for title: String) -> [Color] {
        if themeManager.themeStyle == .strangerThings {
            // 怪奇物语风格渐变
            switch title {
            case "独家放送":
                return [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]
            case "新歌首发":
                return [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.1, green: 0.4, blue: 0.8)]
            case "热门推荐":
                return [Color(red: 0.8, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.1, blue: 0.6)]
            default:
                return [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 1.0)]
            }
        } else {
            return bannerGradient(for: title)
        }
    }
    
    private func bannerSubtitle(for title: String) -> String {
        switch title {
        case "热歌榜": return "热门推荐\n最热门的歌曲"
        case "飙升榜": return "热度上升\n最近最火的歌曲"
        case "新歌榜": return "新歌首发\n最新的音乐作品"
        default: return "发现好音乐"
        }
    }
    
    private func bannerGradient(for title: String) -> [Color] {
        switch title {
        case "热歌榜": return [Color(red: 0.8, green: 0.4, blue: 0.2), Color(red: 0.95, green: 0.6, blue: 0.3)]
        case "飙升榜": return [Color(red: 0.4, green: 0.6, blue: 0.3), Color(red: 0.6, green: 0.8, blue: 0.5)]
        case "新歌榜": return [Color(red: 0.3, green: 0.5, blue: 0.7), Color(red: 0.5, green: 0.7, blue: 0.9)]
        default: return [Color.blue, Color.purple]
        }
    }
    
    // MARK: - 处理Banner点击
    private func handleBannerTap(_ banner: Banner) {
        guard let targetId = banner.targetId else { return }
        withAnimation(.spring(response: 0.3)) {
            selectedPlaylistId = targetId
            navigateToPlaylist = true
        }
    }
    
    // MARK: - 最近播放区域
    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("最近播放")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // 最近播放内容
            if recentlyPlayed.isEmpty {
                emptyRecentlyPlayedView
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(recentlyPlayed.prefix(10), id: \.id) { track in
                            Button(action: {
                                HapticFeedback.light()
                                Task {
                                    await AudioPlayer.shared.play(track: track)
                                }
                            }) {
                                RecentlyPlayedCard(
                                    imageUrl: track.coverUrl.flatMap { URL(string: $0) },
                                    title: track.name,
                                    artist: track.artistName
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    // 空状态视图
    private var emptyRecentlyPlayedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("暂无播放历史")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - 液态玻璃推荐歌单区域
    private var liquidGlassPlaylistSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("推荐歌单")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                LiquidGlassPillButton(title: "换一批", icon: "arrow.triangle.2.circlepath") {
                    Task {
                        do {
                            let randomOffset = Int.random(in: 0...200)
                            let newPlaylists = try await musicService.getHotPlaylist(cat: "全部", limit: 12, offset: randomOffset)
                            withAnimation(.spring(response: 0.4)) {
                                playlists = newPlaylists
                            }
                        } catch {
                            #if DEBUG
                            print("Refresh error: \(error)")
                            #endif
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // 歌单内容 - iPad 网格 / iPhone 横向滚动
            if isLoading {
                liquidGlassLoadingView
            } else if let error = errorMessage {
                liquidGlassErrorView(error)
            } else if playlists.isEmpty {
                liquidGlassEmptyView
            } else if isWideLayout {
                // iPad: 网格布局，一次展示更多歌单
                let iPadColumns = [
                    GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
                ]
                LazyVGrid(columns: iPadColumns, spacing: 20) {
                    ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                        NavigationLink(destination: PlaylistDetailView(
                            playlistId: playlist.id,
                            playlistName: playlist.name,
                            coverUrl: playlist.coverUrl
                        )) {
                            AppleMusicPlaylistCard(
                                imageUrl: playlist.coverUrl.flatMap { URL(string: $0) },
                                title: playlist.name,
                                subtitle: playlist.playCountText
                            )
                        }
                        .buttonStyle(LiquidGlassButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                            NavigationLink(destination: PlaylistDetailView(
                                playlistId: playlist.id,
                                playlistName: playlist.name,
                                coverUrl: playlist.coverUrl
                            )) {
                                AppleMusicPlaylistCard(
                                    imageUrl: playlist.coverUrl.flatMap { URL(string: $0) },
                                    title: playlist.name,
                                    subtitle: playlist.playCountText
                                )
                                .staggeredEntrance(index: index, baseDelay: 0.05)
                            }
                            .buttonStyle(LiquidGlassButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var newAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("新碟上线")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)

            if isLoading && newAlbums.isEmpty {
                HorizontalCardSkeletonView(count: 4)
            } else if !newAlbums.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(newAlbums.prefix(12), id: \.id) { album in
                            NavigationLink(destination: AlbumDetailView(
                                albumId: album.id,
                                albumName: album.name
                            )) {
                                AppleMusicPlaylistCard(
                                    imageUrl: album.picUrl.flatMap { URL(string: $0) },
                                    title: album.name,
                                    subtitle: album.artistName
                                )
                            }
                            .buttonStyle(LiquidGlassButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var recommendedArtistsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("歌手")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)

            if isLoading && topArtists.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(0..<6, id: \.self) { _ in
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 72, height: 72)
                                SkeletonBlock(width: 56, height: 12, cornerRadius: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else if !topArtists.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(topArtists.prefix(16), id: \.id) { artist in
                            NavigationLink(destination: ArtistDetailView(
                                artistId: artist.id,
                                artistName: artist.name
                            )) {
                                RecommendedArtistCard(artist: artist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    // MARK: - 液态玻璃加载视图
    private var liquidGlassLoadingView: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(0..<6, id: \.self) { _ in
                    LiquidGlassSkeletonCard()
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - 液态玻璃错误视图
    private func liquidGlassErrorView(_ error: String) -> some View {
        LiquidGlassCard(cornerRadius: 24, padding: 32) {
            VStack(spacing: 20) {
                LiquidGlassIconButton(icon: "wifi.exclamationmark", color: .gray, size: 80, iconSize: 36) {}
                    .disabled(true)
                
                VStack(spacing: 8) {
                    Text("网络出了点问题")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: {
                    Task { await loadData() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                        Text("重新加载")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .shadow(color: .pink.opacity(0.3), radius: 15, x: 0, y: 8)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 液态玻璃空视图
    private var liquidGlassEmptyView: some View {
        LiquidGlassCard(cornerRadius: 24, padding: 32) {
            VStack(spacing: 16) {
                LiquidGlassIconButton(icon: "music.note.list", color: .gray, size: 80, iconSize: 32) {}
                    .disabled(true)
                
                Text("暂无推荐歌单")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - 静态 Banner 数据
    private var staticBanners: [Banner] {
        [
            Banner(
                pic: nil,
                imageUrl: nil,
                targetId: 3778678,
                targetType: 1000,
                titleColor: nil,
                typeTitle: "热歌榜",
                url: nil
            ),
            Banner(
                pic: nil,
                imageUrl: nil,
                targetId: 19723756,
                targetType: 1000,
                titleColor: nil,
                typeTitle: "飙升榜",
                url: nil
            ),
            Banner(
                pic: nil,
                imageUrl: nil,
                targetId: 3779629,
                targetType: 1000,
                titleColor: nil,
                typeTitle: "新歌榜",
                url: nil
            )
        ]
    }
    
    // MARK: - 加载数据
    private func loadData() async {
        isLoading = true
        errorMessage = nil
        
        banners = staticBanners
        recentlyPlayed = storageService.getHistory()

        async let playlistsTask = musicService.getPersonalized(limit: 12)
        async let albumsTask = musicService.getNewAlbums(area: "ALL", limit: 12)
        async let artistsTask = musicService.getTopArtists(limit: 16)

        do {
            playlists = try await playlistsTask
        } catch {
            #if DEBUG
            print("Load playlists error: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }

        newAlbums = (try? await albumsTask) ?? []
        topArtists = (try? await artistsTask) ?? []

        #if DEBUG
        print("Loaded \(playlists.count) playlists, \(newAlbums.count) albums, \(topArtists.count) artists, \(recentlyPlayed.count) history")
        #endif

        isLoading = false
    }
}

// MARK: - 液态玻璃骨架屏卡片
struct LiquidGlassSkeletonCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    private var imageSize: CGFloat {
        min((UIScreen.main.bounds.width - 56) / 2, 180)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 封面骨架
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                .frame(width: imageSize, height: imageSize)
                .shimmer(speed: 1.4)
            
            // 标题骨架
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: imageSize * 0.85, height: 14)
                SkeletonBlock(width: imageSize * 0.6, height: 14)
            }
        }
    }
}

// MARK: - Apple Music 风格 Banner 卡片
struct AppleMusicBannerCard: View {
    let title: String
    let subtitle: String
    let gradientColors: [Color]
    let action: () -> Void
    
    private var cardWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.75, 380)
    }
    
    private var cardHeight: CGFloat {
        cardWidth * 0.6
    }
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            ZStack(alignment: .topTrailing) {
                // 渐变背景
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Youmi Music 标志
                HStack(spacing: 4) {
                    Image(systemName: "cat.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Youmi Music")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 12)
                .padding(.trailing, 16)
                
                // 标题和副标题
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(width: cardWidth, height: cardHeight)
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 最近播放卡片
struct RecentlyPlayedCard: View {
    let imageUrl: URL?
    let title: String
    let artist: String
    @Environment(\.colorScheme) var colorScheme
    
    private var cardWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.38, 180)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                // 封面
                if let url = imageUrl {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        coverPlaceholder
                            .overlay {
                                ProgressView()
                                    .tint(.secondary)
                            }
                    }
                    .frame(width: cardWidth, height: cardWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    coverPlaceholder
                        .frame(width: cardWidth, height: cardWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // 歌曲名
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .frame(width: cardWidth, alignment: .leading)
                
            // 艺术家
            Text(artist)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
        }
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
            
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

struct RecommendedArtistCard: View {
    let artist: SearchArtistResult

    var body: some View {
        VStack(spacing: 8) {
            if let urlString = artist.avatarUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 72, height: 72)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color(.systemGray5))
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundColor(.secondary)
                    }
            }

            Text(artist.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(width: 76)
        }
    }
}

// MARK: - Apple Music 风格歌单卡片
struct AppleMusicPlaylistCard: View {
    let imageUrl: URL?
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var cardWidth: CGFloat {
        // iPad regular 宽度下使用固定尺寸，iPhone 按比例
        if horizontalSizeClass == .regular {
            return 170
        }
        return min(UIScreen.main.bounds.width * 0.38, 180)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面
            if let url = imageUrl {
                CachedAsyncImage(url: url, targetSize: CGSize(width: cardWidth, height: cardWidth)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    coverPlaceholder
                        .overlay {
                            ProgressView()
                                .tint(.secondary)
                        }
                }
                .frame(width: cardWidth, height: cardWidth)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                coverPlaceholder
                    .frame(width: cardWidth, height: cardWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // 标题
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(width: cardWidth, alignment: .leading)
            
            // 副标题
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: cardWidth, alignment: .leading)
            }
        }
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
            
            Image(systemName: "music.note")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - 快捷入口卡片
struct QuickAccessCard: View {
    let icon: String
    let title: String
    let gradient: [Color]
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(gradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12))
                )
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
        .frame(width: 80)
    }
}

// MARK: - 快捷菜单按钮
struct QuickMenuButton: View {
    @Binding var showMenu: Bool
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {}) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.primary)
                .scaleEffect(isPressed ? 0.9 : 1.0)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    HapticFeedback.medium()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showMenu = true
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - 快捷菜单弹窗
struct QuickAccessMenu: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPresented = false
                    }
                }
            
            // 菜单卡片
            VStack(spacing: 0) {
                // 标题
                HStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("快捷入口")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                
                Divider()
                
                // 快捷选项
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    NavigationLink(destination: PersonalFMView()) {
                        QuickMenuItemLabel(
                            icon: "radio",
                            title: "私人FM",
                            color: .green
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        isPresented = false
                    })
                    
                    NavigationLink(destination: CoverFlow3DView()) {
                        QuickMenuItemLabel(
                            icon: "square.stack.3d.up",
                            title: "3D专辑",
                            color: .orange
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        isPresented = false
                    })
                    
                    NavigationLink(destination: ToplistView()) {
                        QuickMenuItemLabel(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "排行榜",
                            color: .purple
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        isPresented = false
                    })
                    
                    NavigationLink(destination: HeartbeatModeView()) {
                        QuickMenuItemLabel(
                            icon: "heart.circle",
                            title: "心动模式",
                            color: .pink
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        isPresented = false
                    })
                    
                    NavigationLink(destination: RadarPlaylistView()) {
                        QuickMenuItemLabel(
                            icon: "dot.radiowaves.left.and.right",
                            title: "雷达歌单",
                            color: .blue
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        isPresented = false
                    })
                }
                .padding(20)
            }
            .frame(width: min(UIScreen.main.bounds.width * 0.85, 420))
            .glassEffectRounded(cornerRadius: 24)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
    }
}

// MARK: - 快捷菜单项
struct QuickMenuItem: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.15))
                    
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(color)
                }
                .frame(width: 64, height: 64)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 快捷菜单项标签（用于 NavigationLink）
struct QuickMenuItemLabel: View {
    let icon: String
    let title: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.15))
                
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: 64, height: 64)
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    NavigationView {
        DiscoverView()
    }
}
