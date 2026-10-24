import SwiftUI

// MARK: - Apple Music 风格搜索页面
struct PlaylistSquareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var themeManager: ThemeManager
    
    // 上次所在 Tab 索引（用于显示对应图标）
    var previousTabIndex: Int = 0
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }
    
    // Tab 图标配置
    private static let tabIcons = ["house.fill", "square.grid.2x2", "person.fill", "gearshape.fill"]
    
    // 搜索状态
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var hasSearched = false
    @FocusState private var isSearchFieldFocused: Bool
    
    // 搜索结果
    @State private var searchResults: [Track] = []
    @State private var artistResults: [SearchArtistResult] = []
    @State private var albumResults: [SearchAlbumResult] = []
    @State private var selectedSearchType: SearchResultType = .song
    
    // 分页
    @State private var isLoadingMore = false
    @State private var hasMoreSongs = true
    @State private var hasMoreArtists = true
    @State private var hasMoreAlbums = true
    
    private let musicService = MusicService.shared
    
    // 歌单分类数据（真实分类）
    private let playlistCategories: [PlaylistCategoryItem] = [
        PlaylistCategoryItem(title: "华语", apiTag: "华语", gradientColors: [Color(red: 0.9, green: 0.4, blue: 0.5), Color(red: 0.95, green: 0.5, blue: 0.6)]),
        PlaylistCategoryItem(title: "流行", apiTag: "流行", gradientColors: [Color(red: 0.8, green: 0.2, blue: 0.3), Color(red: 0.9, green: 0.3, blue: 0.4)]),
        PlaylistCategoryItem(title: "摇滚", apiTag: "摇滚", gradientColors: [Color(red: 0.9, green: 0.4, blue: 0.5), Color(red: 0.95, green: 0.5, blue: 0.6)]),
        PlaylistCategoryItem(title: "电子", apiTag: "电子", gradientColors: [Color(red: 0.8, green: 0.2, blue: 0.3), Color(red: 0.9, green: 0.3, blue: 0.4)]),
        PlaylistCategoryItem(title: "民谣", apiTag: "民谣", gradientColors: [Color(red: 0.4, green: 0.7, blue: 0.9), Color(red: 0.6, green: 0.8, blue: 0.95)]),
        PlaylistCategoryItem(title: "说唱", apiTag: "说唱", gradientColors: [Color(red: 0.55, green: 0.6, blue: 0.35), Color(red: 0.65, green: 0.7, blue: 0.45)]),
        PlaylistCategoryItem(title: "爵士", apiTag: "爵士", gradientColors: [Color(red: 0.3, green: 0.55, blue: 0.65), Color(red: 0.4, green: 0.65, blue: 0.75)]),
        PlaylistCategoryItem(title: "轻音乐", apiTag: "轻音乐", gradientColors: [Color(red: 0.55, green: 0.6, blue: 0.35), Color(red: 0.65, green: 0.7, blue: 0.45)]),
        PlaylistCategoryItem(title: "粤语", apiTag: "粤语", gradientColors: [Color(red: 0.9, green: 0.4, blue: 0.5), Color(red: 0.95, green: 0.5, blue: 0.6)]),
        PlaylistCategoryItem(title: "ACG", apiTag: "ACG", gradientColors: [Color(red: 0.9, green: 0.4, blue: 0.5), Color(red: 0.95, green: 0.5, blue: 0.6)]),
        PlaylistCategoryItem(title: "影视原声", apiTag: "影视原声", gradientColors: [Color(red: 0.35, green: 0.45, blue: 0.75), Color(red: 0.45, green: 0.55, blue: 0.85)]),
        PlaylistCategoryItem(title: "古典", apiTag: "古典", gradientColors: [Color(red: 0.55, green: 0.35, blue: 0.65), Color(red: 0.65, green: 0.45, blue: 0.75)])
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // 主内容
            if hasSearched {
                searchResultsContent
            } else {
                categoriesContent
            }
            
            // 底部搜索栏
            bottomSearchBar
        }
        .background {
            ThemedBackground()
                .environmentObject(themeManager)
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - 分类内容
    private var categoriesContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)
            ], spacing: 12) {
                ForEach(playlistCategories) { category in
                    NavigationLink {
                        CategoryPlaylistListView(category: category.apiTag, title: category.title)
                    } label: {
                        PlaylistCategoryCard(category: category)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - 搜索结果内容
    private var searchResultsContent: some View {
        VStack(spacing: 0) {
            if isSearching {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(isStrangerTheme ? accentColor : nil)
                Text("搜索中...")
                    .font(.system(size: 14))
                    .foregroundColor(secondaryTextColor)
                    .padding(.top, 12)
                Spacer()
            } else {
                // 分类选择器
                searchTypeSelector
                
                // 结果列表
                TabView(selection: $selectedSearchType) {
                    songResultsList.tag(SearchResultType.song)
                    artistResultsList.tag(SearchResultType.artist)
                    albumResultsList.tag(SearchResultType.album)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }
    
    // MARK: - 搜索类型选择器
    private var searchTypeSelector: some View {
        HStack(spacing: 0) {
            ForEach(SearchResultType.allCases, id: \.self) { type in
                let count = countFor(type)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSearchType = type
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(type.title)
                                .font(.system(size: 15, weight: selectedSearchType == type ? .semibold : .regular))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11))
                                    .foregroundColor(secondaryTextColor)
                            }
                        }
                        .foregroundColor(selectedSearchType == type ? textColor : secondaryTextColor)
                        
                        Rectangle()
                            .fill(selectedSearchType == type ? accentColor : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - 歌曲结果列表
    private var songResultsList: some View {
        Group {
            if searchResults.isEmpty {
                emptyResultView("未找到相关歌曲")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, track in
                            SearchTrackRow(track: track, isPlaying: AudioPlayer.shared.currentTrack?.id == track.id, isStrangerTheme: isStrangerTheme)
                                .onTapGesture {
                                    AudioPlayer.shared.setPlaylist(searchResults, startAt: index)
                                }
                                .onAppear {
                                    if index == searchResults.count - 5 && hasMoreSongs {
                                        Task { await loadMoreSongs() }
                                    }
                                }
                            
                            if index < searchResults.count - 1 {
                                Divider().padding(.leading, 76)
                            }
                        }
                        
                        loadingIndicator(isLoadingMore && selectedSearchType == .song, hasMore: hasMoreSongs)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - 歌手结果列表
    private var artistResultsList: some View {
        Group {
            if artistResults.isEmpty {
                emptyResultView("未找到相关歌手")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(artistResults.enumerated()), id: \.element.id) { index, artist in
                            NavigationLink {
                                ArtistDetailView(artistId: artist.id, artistName: artist.name)
                            } label: {
                                SearchArtistRow(artist: artist, isStrangerTheme: isStrangerTheme)
                            }
                            .onAppear {
                                if index == artistResults.count - 3 && hasMoreArtists {
                                    Task { await loadMoreArtists() }
                                }
                            }
                            
                            if index < artistResults.count - 1 {
                                Divider().padding(.leading, 76)
                            }
                        }
                        
                        loadingIndicator(isLoadingMore && selectedSearchType == .artist, hasMore: hasMoreArtists)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - 专辑结果列表
    private var albumResultsList: some View {
        Group {
            if albumResults.isEmpty {
                emptyResultView("未找到相关专辑")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(albumResults.enumerated()), id: \.element.id) { index, album in
                            NavigationLink {
                                AlbumDetailView(albumId: album.id, albumName: album.name)
                            } label: {
                                SearchAlbumRow(album: album, isStrangerTheme: isStrangerTheme)
                            }
                            .onAppear {
                                if index == albumResults.count - 3 && hasMoreAlbums {
                                    Task { await loadMoreAlbums() }
                                }
                            }
                            
                            if index < albumResults.count - 1 {
                                Divider().padding(.leading, 76)
                            }
                        }
                        
                        loadingIndicator(isLoadingMore && selectedSearchType == .album, hasMore: hasMoreAlbums)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - 底部搜索栏（Apple Music 风格）
    private var bottomSearchBar: some View {
        HStack(spacing: 12) {
            // 左边返回按钮（显示上次所在 Tab 的图标）
            Button {
                HapticFeedback.light()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : (colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95)))
                    
                    Image(systemName: Self.tabIcons[previousTabIndex])
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(accentColor)
                }
                .frame(width: 48, height: 48)
                .shadow(color: isStrangerTheme ? accentColor.opacity(0.2) : .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
            
            // 搜索框
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                
                TextField("艺人、歌曲、歌词以及更多内容", text: $searchText)
                    .font(.system(size: 16))
                    .foregroundColor(textColor)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await performSearch() }
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        hasSearched = false
                        searchResults = []
                        artistResults = []
                        albumResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(secondaryTextColor)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : (colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.96)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isStrangerTheme ? accentColor.opacity(0.3) : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)), lineWidth: 1)
            )
            .shadow(color: isStrangerTheme ? accentColor.opacity(0.1) : .black.opacity(0.08), radius: 8, x: 0, y: 4)
            
            // 麦克风按钮
            Button {
                HapticFeedback.light()
                // TODO: 语音搜索
            } label: {
                ZStack {
                    Circle()
                        .fill(isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : (colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95)))
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isStrangerTheme ? accentColor : .primary)
                }
                .frame(width: 48, height: 48)
                .shadow(color: isStrangerTheme ? accentColor.opacity(0.2) : .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Group {
                if isStrangerTheme {
                    Rectangle()
                        .fill(Color(red: 0.05, green: 0.02, blue: 0.08).opacity(0.95))
                        .ignoresSafeArea()
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                }
            }
        )
    }
    
    // MARK: - 辅助视图
    private func emptyResultView(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(secondaryTextColor)
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func loadingIndicator(_ isLoading: Bool, hasMore: Bool) -> some View {
        Group {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(isStrangerTheme ? accentColor : nil)
                        .padding()
                    Spacer()
                }
            } else if !hasMore {
                Text("已加载全部")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    private func countFor(_ type: SearchResultType) -> Int {
        switch type {
        case .song: return searchResults.count
        case .artist: return artistResults.count
        case .album: return albumResults.count
        }
    }
    
    // MARK: - 搜索逻辑
    private func performSearch() async {
        guard !searchText.isEmpty else { return }
        
        isSearchFieldFocused = false
        isSearching = true
        hasSearched = true
        hasMoreSongs = true
        hasMoreArtists = true
        hasMoreAlbums = true
        
        async let songsTask = searchSongs(offset: 0)
        async let artistsTask = musicService.searchArtists(keyword: searchText, limit: 20, offset: 0)
        async let albumsTask = musicService.searchAlbums(keyword: searchText, limit: 20, offset: 0)
        
        do {
            let (songs, artists, albums) = try await (songsTask, artistsTask, albumsTask)
            
            await MainActor.run {
                searchResults = songs
                artistResults = artists
                albumResults = albums
                isSearching = false
                
                // 智能切换到有结果的类型
                if songs.isEmpty && !artists.isEmpty {
                    selectedSearchType = .artist
                } else if songs.isEmpty && artists.isEmpty && !albums.isEmpty {
                    selectedSearchType = .album
                } else {
                    selectedSearchType = .song
                }
            }
        } catch {
            #if DEBUG
            print("搜索出错: \(error)")
            #endif
            await MainActor.run { isSearching = false }
        }
    }
    
    private func searchSongs(offset: Int) async throws -> [Track] {
        let songs = try await musicService.search(keyword: searchText, limit: 30, offset: offset)
        let ids = songs.map { $0.id }
        if !ids.isEmpty {
            return try await musicService.getSongDetail(ids: ids)
        }
        return []
    }
    
    private func loadMoreSongs() async {
        guard !isLoadingMore && hasMoreSongs else { return }
        isLoadingMore = true
        
        do {
            let more = try await searchSongs(offset: searchResults.count)
            await MainActor.run {
                if more.isEmpty { hasMoreSongs = false }
                else { searchResults.append(contentsOf: more) }
                isLoadingMore = false
            }
        } catch {
            await MainActor.run { isLoadingMore = false }
        }
    }
    
    private func loadMoreArtists() async {
        guard !isLoadingMore && hasMoreArtists else { return }
        isLoadingMore = true
        
        do {
            let more = try await musicService.searchArtists(keyword: searchText, limit: 20, offset: artistResults.count)
            await MainActor.run {
                if more.isEmpty { hasMoreArtists = false }
                else { artistResults.append(contentsOf: more) }
                isLoadingMore = false
            }
        } catch {
            await MainActor.run { isLoadingMore = false }
        }
    }
    
    private func loadMoreAlbums() async {
        guard !isLoadingMore && hasMoreAlbums else { return }
        isLoadingMore = true
        
        do {
            let more = try await musicService.searchAlbums(keyword: searchText, limit: 20, offset: albumResults.count)
            await MainActor.run {
                if more.isEmpty { hasMoreAlbums = false }
                else { albumResults.append(contentsOf: more) }
                isLoadingMore = false
            }
        } catch {
            await MainActor.run { isLoadingMore = false }
        }
    }
}

// MARK: - 搜索结果类型
enum SearchResultType: CaseIterable {
    case song, artist, album
    
    var title: String {
        switch self {
        case .song: return "歌曲"
        case .artist: return "歌手"
        case .album: return "专辑"
        }
    }
}

// MARK: - 歌单分类模型
struct PlaylistCategoryItem: Identifiable {
    let id = UUID()
    let title: String
    let apiTag: String  // API 请求用的标签
    let gradientColors: [Color]
}

// MARK: - 歌单分类卡片
struct PlaylistCategoryCard: View {
    let category: PlaylistCategoryItem
    
    private var cardHeight: CGFloat {
        min((UIScreen.main.bounds.width - 44) / 2 * 0.6, 180)
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: category.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Text(category.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(12)
        }
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 分类歌单列表页面
struct CategoryPlaylistListView: View {
    let category: String
    let title: String
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var playlists: [RecommendPlaylist] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var offset = 0
    
    private let musicService = MusicService.shared
    private let limit = 30
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.themeStyle == .strangerThings }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }
    
    var body: some View {
        Group {
            if isLoading && playlists.isEmpty {
                ProgressView()
                    .tint(isStrangerTheme ? accentColor : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)
                    ], spacing: 20) {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(
                                    playlistId: playlist.id,
                                    playlistName: playlist.name,
                                    coverUrl: playlist.coverUrl
                                )
                            } label: {
                                CategoryPlaylistCard(playlist: playlist, isStrangerTheme: isStrangerTheme)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onAppear {
                                if playlist.id == playlists.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 100)
                    
                    if isLoadingMore {
                        ProgressView()
                            .tint(isStrangerTheme ? accentColor : nil)
                            .padding(.bottom, 20)
                    }
                }
                .refreshable {
                    offset = 0
                    await loadPlaylists()
                }
            }
        }
        .background {
            ThemedBackground()
                .environmentObject(themeManager)
        }
        .immersiveNavigationChrome()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadPlaylists()
        }
    }
    
    private func loadPlaylists() async {
        isLoading = true
        do {
            playlists = try await musicService.getHotPlaylist(cat: category, limit: limit, offset: 0)
            offset = limit
        } catch {
            #if DEBUG
            print("加载歌单失败: \(error)")
            #endif
        }
        isLoading = false
    }
    
    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let more = try await musicService.getHotPlaylist(cat: category, limit: limit, offset: offset)
            playlists.append(contentsOf: more)
            offset += limit
        } catch {
            #if DEBUG
            print("加载更多失败: \(error)")
            #endif
        }
        isLoadingMore = false
    }
}

// MARK: - 分类歌单卡片
struct CategoryPlaylistCard: View {
    let playlist: RecommendPlaylist
    var isStrangerTheme: Bool = false
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var placeholderBackground: Color { isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : Color(.systemGray5) }
    
    private var imageSize: CGFloat {
        min((UIScreen.main.bounds.width - 46) / 2, 220)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let picUrl = playlist.coverUrl, let url = URL(string: picUrl) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: imageSize, height: imageSize)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(placeholderBackground)
                    }
                } else {
                    Rectangle().fill(placeholderBackground)
                }
                
                if !playlist.playCountText.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "headphones").font(.system(size: 10))
                        Text(playlist.playCountText).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(8)
                }
            }
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.2) : .black.opacity(0.12), radius: 10, x: 0, y: 5)
            
            Text(playlist.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(textColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - 搜索结果歌曲行
struct SearchTrackRow: View {
    let track: Track
    let isPlaying: Bool
    var isStrangerTheme: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            ZStack {
                if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 52, height: 52)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        coverPlaceholder
                    }
                } else {
                    coverPlaceholder
                }
                
                if isPlaying {
                    Circle().fill(.black.opacity(0.5))
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.system(size: 15, weight: isPlaying ? .semibold : .regular))
                    .foregroundColor(isPlaying ? accentColor : textColor)
                    .lineLimit(1)
                
                Text("\(track.artistName) · \(track.albumName)")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(secondaryTextColor)
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : (colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)))
            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundColor(secondaryTextColor.opacity(0.5))
        }
    }
}

#Preview {
    NavigationStack {
        PlaylistSquareView()
    }
}
