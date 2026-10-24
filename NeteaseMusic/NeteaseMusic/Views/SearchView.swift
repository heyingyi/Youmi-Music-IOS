import SwiftUI

// MARK: - 音乐分类模型
struct MusicCategory: Identifiable {
    let id = UUID()
    let title: String
    let gradientColors: [Color]
    let imageName: String? = nil // 可以后期添加图片
}

// MARK: - 搜索类型
enum SearchType: String, CaseIterable {
    case song = "歌曲"
    case artist = "歌手"
    case album = "专辑"
    
    var icon: String {
        switch self {
        case .song: return "music.note"
        case .artist: return "person"
        case .album: return "square.stack"
        }
    }
}

// MARK: - 音乐分类数据（静态缓存，避免每次渲染重建）
private enum MusicCategoryData {
    static let standard: [MusicCategory] = [
        MusicCategory(title: "C-Pop", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        MusicCategory(title: "空间音频", gradientColors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.9, green: 0.4, blue: 0.4)]),
        MusicCategory(title: "国语流行", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        MusicCategory(title: "DJ 混音精选", gradientColors: [Color(red: 0.8, green: 0.3, blue: 0.3), Color(red: 0.9, green: 0.4, blue: 0.4)]),
        MusicCategory(title: "月度音乐回忆", gradientColors: [Color(red: 1.0, green: 0.8, blue: 0.4), Color(red: 0.6, green: 0.8, blue: 0.9)]),
        MusicCategory(title: "排行榜", gradientColors: [Color(red: 0.6, green: 0.65, blue: 0.4), Color(red: 0.65, green: 0.7, blue: 0.45)]),
        MusicCategory(title: "爵士乐", gradientColors: [Color(red: 0.4, green: 0.6, blue: 0.7), Color(red: 0.5, green: 0.7, blue: 0.8)]),
        MusicCategory(title: "创作与制作", gradientColors: [Color(red: 0.6, green: 0.65, blue: 0.4), Color(red: 0.65, green: 0.7, blue: 0.45)]),
        MusicCategory(title: "国际流行", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        MusicCategory(title: "粤语流行", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        MusicCategory(title: "嘻哈/说唱", gradientColors: [Color(red: 0.4, green: 0.5, blue: 0.8), Color(red: 0.5, green: 0.6, blue: 0.9)]),
        MusicCategory(title: "古典音乐", gradientColors: [Color(red: 0.6, green: 0.4, blue: 0.7), Color(red: 0.7, green: 0.5, blue: 0.8)])
    ]

    static let strangerThings: [MusicCategory] = [
        MusicCategory(title: "C-Pop", gradientColors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]),
        MusicCategory(title: "空间音频", gradientColors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.1, green: 0.4, blue: 0.8)]),
        MusicCategory(title: "国语流行", gradientColors: [Color(red: 0.8, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.1, blue: 0.6)]),
        MusicCategory(title: "DJ 混音精选", gradientColors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 1.0)]),
        MusicCategory(title: "月度音乐回忆", gradientColors: [Color(red: 0.8, green: 0.2, blue: 0.8), Color(red: 1.0, green: 0.2, blue: 0.3)]),
        MusicCategory(title: "排行榜", gradientColors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.8, green: 0.2, blue: 0.8)]),
        MusicCategory(title: "爵士乐", gradientColors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.1, green: 0.4, blue: 0.8)]),
        MusicCategory(title: "创作与制作", gradientColors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]),
        MusicCategory(title: "国际流行", gradientColors: [Color(red: 0.8, green: 0.2, blue: 0.8), Color(red: 0.6, green: 0.1, blue: 0.6)]),
        MusicCategory(title: "粤语流行", gradientColors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.2, blue: 0.8)]),
        MusicCategory(title: "嘻哈/说唱", gradientColors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 1.0, green: 0.2, blue: 0.3)]),
        MusicCategory(title: "古典音乐", gradientColors: [Color(red: 0.8, green: 0.2, blue: 0.8), Color(red: 0.2, green: 0.6, blue: 1.0)])
    ]
}

// MARK: - Apple Music 液态玻璃风格搜索页
struct SearchView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var searchResults: [Track] = []
    @State private var artistResults: [SearchArtistResult] = []
    @State private var albumResults: [SearchAlbumResult] = []
    @State private var hotSearches: [HotSearch] = []
    @State private var searchHistory: [String] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var isLoaded = false
    @State private var currentKeyword = ""
    @State private var selectedType: SearchType = .song
    @State private var isLoadingMore = false
    @State private var hasMoreSongs = true
    @State private var hasMoreArtists = true
    @State private var hasMoreAlbums = true
    
    // 新发现页面数据
    @State private var recommendPlaylists: [RecommendPlaylist] = [] // 快乐启蒙
    @State private var newSongs: [Track] = [] // 最新歌曲
    @State private var newAlbums: [RecommendPlaylist] = [] // 新近发布
    
    // 自动聚焦支持
    @Binding var shouldFocus: Bool
    
    init(shouldFocus: Binding<Bool> = .constant(false)) {
        self._shouldFocus = shouldFocus
    }
    
    private let musicService = MusicService.shared
    private let historyKey = "SearchHistory"
    
    // 音乐分类数据（使用静态缓存）
    private var musicCategories: [MusicCategory] {
        themeManager.isStrangerTheme ? MusicCategoryData.strangerThings : MusicCategoryData.standard
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 液态玻璃搜索栏
            LiquidGlassSearchBarView(
                shouldFocus: $shouldFocus,
                hasSearched: $hasSearched,
                onSearch: { keyword in
                    Task { await performSearch(keyword: keyword) }
                },
                onClear: {
                    hasSearched = false
                    searchResults = []
                    artistResults = []
                    albumResults = []
                    currentKeyword = ""
                }
            )
            
            if hasSearched {
                searchResultsView
            } else {
                musicCategoriesView
            }
        }
        .background {
            ThemedBackground(standardColors: [.cyan.opacity(0.06), .blue.opacity(0.05), .purple.opacity(0.04)])
                .environmentObject(themeManager)
        }
        .immersiveNavigationChrome()
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadSearchHistory()
        }
        .task {
            if !isLoaded {
                isLoaded = true
                Task.detached(priority: .utility) {
                    await loadHotSearch()
                }
            }
        }
    }
    
    // MARK: - 搜索历史管理
    private func loadSearchHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }
    
    private func saveSearchHistory(_ keyword: String) {
        var history = searchHistory
        history.removeAll { $0 == keyword }
        history.insert(keyword, at: 0)
        if history.count > 10 {
            history = Array(history.prefix(10))
        }
        searchHistory = history
        UserDefaults.standard.set(history, forKey: historyKey)
    }
    
    private func clearSearchHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
    
    // MARK: - 加载热搜
    @MainActor
    private func loadHotSearch() async {
        do {
            hotSearches = try await musicService.getHotSearch()
        } catch {
            #if DEBUG
            print("Load hot search error: \(error)")
            #endif
        }
    }
    
    // MARK: - 隐藏键盘
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    // MARK: - 搜索（并行搜索歌曲、歌手、专辑）
    private func performSearch(keyword: String) async {
        guard !keyword.isEmpty else { return }
        
        hideKeyboard()
        
        saveSearchHistory(keyword)
        currentKeyword = keyword
        isSearching = true
        hasSearched = true
        hasMoreSongs = true
        hasMoreArtists = true
        hasMoreAlbums = true
        
        await performNeteaseSearch(keyword: keyword)
    }
    
    // 网易云搜索
    private func performNeteaseSearch(keyword: String) async {
        async let songsTask = searchSongs(keyword: keyword, offset: 0)
        async let artistsTask = musicService.searchArtists(keyword: keyword, limit: 20, offset: 0)
        async let albumsTask = musicService.searchAlbums(keyword: keyword, limit: 20, offset: 0)
        
        do {
            let (songs, artists, albums) = try await (songsTask, artistsTask, albumsTask)
            
            await MainActor.run {
                searchResults = songs
                artistResults = artists
                albumResults = albums
                isSearching = false
                
                if songs.isEmpty && !artists.isEmpty {
                    selectedType = .artist
                } else if songs.isEmpty && artists.isEmpty && !albums.isEmpty {
                    selectedType = .album
                } else {
                    selectedType = .song
                }
            }
        } catch {
            #if DEBUG
            print("Netease search error: \(error)")
            #endif
            await MainActor.run {
                isSearching = false
            }
        }
    }
    
    // 搜索歌曲并获取详情
    private func searchSongs(keyword: String, offset: Int) async throws -> [Track] {
        let songs = try await musicService.search(keyword: keyword, limit: 30, offset: offset)
        let ids = songs.map { $0.id }
        if !ids.isEmpty {
            return try await musicService.getSongDetail(ids: ids)
        }
        return []
    }
    
    // 加载更多歌曲
    private func loadMoreSongs() async {
        guard !isLoadingMore && hasMoreSongs && !currentKeyword.isEmpty else { return }
        
        isLoadingMore = true
        
        do {
            let moreSongs = try await searchSongs(keyword: currentKeyword, offset: searchResults.count)
            await MainActor.run {
                if moreSongs.isEmpty {
                    hasMoreSongs = false
                } else {
                    searchResults.append(contentsOf: moreSongs)
                }
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
    
    // 加载更多歌手
    private func loadMoreArtists() async {
        guard !isLoadingMore && hasMoreArtists && !currentKeyword.isEmpty else { return }
        
        isLoadingMore = true
        
        do {
            let moreArtists = try await musicService.searchArtists(keyword: currentKeyword, limit: 20, offset: artistResults.count)
            await MainActor.run {
                if moreArtists.isEmpty {
                    hasMoreArtists = false
                } else {
                    artistResults.append(contentsOf: moreArtists)
                }
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
    
    // 加载更多专辑
    private func loadMoreAlbums() async {
        guard !isLoadingMore && hasMoreAlbums && !currentKeyword.isEmpty else { return }
        
        isLoadingMore = true
        
        do {
            let moreAlbums = try await musicService.searchAlbums(keyword: currentKeyword, limit: 20, offset: albumResults.count)
            await MainActor.run {
                if moreAlbums.isEmpty {
                    hasMoreAlbums = false
                } else {
                    albumResults.append(contentsOf: moreAlbums)
                }
                isLoadingMore = false
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
    
    // MARK: - 搜索结果视图
    private var searchResultsView: some View {
        VStack(spacing: 0) {
            if isSearching {
                TrackListSkeletonView(count: 10)
                    .padding(.top, 20)
            } else {
                // 分类标签
                searchTypePicker
                
                // 分类内容
                TabView(selection: $selectedType) {
                    // 歌曲列表
                    songListView
                        .tag(SearchType.song)
                    
                    // 歌手列表
                    artistListView
                        .tag(SearchType.artist)
                    
                    // 专辑列表
                    albumListView
                        .tag(SearchType.album)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }
    
    // MARK: - 分类选择器
    private var searchTypePicker: some View {
        HStack(spacing: 0) {
            ForEach(SearchType.allCases, id: \.self) { type in
                let count = countFor(type)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedType = type
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(type.rawValue)
                                .font(.system(size: 15, weight: selectedType == type ? .semibold : .regular))
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(selectedType == type ? .primary : .secondary)
                        
                        // 下划线
                        Rectangle()
                            .fill(selectedType == type ? Color.red : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }
    
    private func countFor(_ type: SearchType) -> Int {
        switch type {
        case .song: return searchResults.count
        case .artist: return artistResults.count
        case .album: return albumResults.count
        }
    }
    
    // MARK: - 歌曲列表
    private var songListView: some View {
        Group {
            if searchResults.isEmpty {
                emptyView(text: "未找到相关歌曲")
            } else {
                SearchResultsList(
                    searchResults: searchResults,
                    isLoadingMore: isLoadingMore,
                    hasMore: hasMoreSongs,
                    onLoadMore: {
                        Task { await loadMoreSongs() }
                    }
                )
            }
        }
    }
    
    // MARK: - 歌手列表
    private var artistListView: some View {
        Group {
            if artistResults.isEmpty {
                emptyView(text: "未找到相关歌手")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(artistResults.enumerated()), id: \.element.id) { index, artist in
                            NavigationLink {
                                ArtistDetailView(artistId: artist.id, artistName: artist.name)
                            } label: {
                                SearchArtistRow(artist: artist)
                            }
                            .onAppear {
                                if index == artistResults.count - 3 && hasMoreArtists {
                                    Task { await loadMoreArtists() }
                                }
                            }
                            
                            if artist.id != artistResults.last?.id {
                                Divider().padding(.leading, 76)
                            }
                        }
                        
                        // 加载更多指示器
                        if isLoadingMore && selectedType == .artist {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        } else if !hasMoreArtists && artistResults.count > 0 {
                            Text("已加载全部")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
    }
    
    // MARK: - 专辑列表
    private var albumListView: some View {
        Group {
            if albumResults.isEmpty {
                emptyView(text: "未找到相关专辑")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(albumResults.enumerated()), id: \.element.id) { index, album in
                            NavigationLink {
                                AlbumDetailView(albumId: album.id, albumName: album.name)
                            } label: {
                                SearchAlbumRow(album: album)
                            }
                            .onAppear {
                                if index == albumResults.count - 3 && hasMoreAlbums {
                                    Task { await loadMoreAlbums() }
                                }
                            }
                            
                            if album.id != albumResults.last?.id {
                                Divider().padding(.leading, 76)
                            }
                        }
                        
                        // 加载更多指示器
                        if isLoadingMore && selectedType == .album {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        } else if !hasMoreAlbums && albumResults.count > 0 {
                            Text("已加载全部")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
    }
    
    // MARK: - 音乐推荐视图
    private var musicCategoriesView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // 搜索历史
                if !searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("搜索历史")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                HapticFeedback.light()
                                clearSearchHistory()
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(searchHistory, id: \.self) { keyword in
                                    Button(action: {
                                        HapticFeedback.light()
                                        Task { await performSearch(keyword: keyword) }
                                    }) {
                                        LiquidGlassTag(text: keyword)
                                    }
                                    .buttonStyle(LiquidGlassButtonStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                
                // 热搜榜
                if !hotSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
                                    )
                                Text("热搜榜")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)
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
                        .padding(.horizontal, 20)
                        
                        LiquidGlassSection {
                            LazyVStack(spacing: 0) {
                                ForEach(hotSearches.indices, id: \.self) { index in
                                    Button(action: {
                                        HapticFeedback.light()
                                        Task { await performSearch(keyword: hotSearches[index].searchWord) }
                                    }) {
                                        LiquidGlassHotSearchRow(index: index + 1, item: hotSearches[index])
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if index < hotSearches.count - 1 {
                                        Divider().padding(.leading, 50)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                // 快乐启蒙
                if !recommendPlaylists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("快乐启蒙")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recommendPlaylists.prefix(10), id: \.id) { playlist in
                                    NavigationLink(destination: PlaylistDetailView(
                                        playlistId: playlist.id,
                                        playlistName: playlist.name,
                                        coverUrl: playlist.coverUrl
                                    )) {
                                        MusicRecommendCard(
                                            imageUrl: playlist.coverUrl.flatMap { URL(string: $0) },
                                            title: playlist.name,
                                            subtitle: playlist.copywriter
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                
                // 最新歌曲
                if !newSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最新歌曲")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        
                        LazyVStack(spacing: 0) {
                            ForEach(Array(newSongs.prefix(10).enumerated()), id: \.element.id) { index, track in
                                Button(action: {
                                    HapticFeedback.light()
                                    AudioPlayer.shared.setPlaylist(Array(newSongs.prefix(10)), startAt: index)
                                }) {
                                    NewSongRow(track: track)
                                }
                                
                                if index < min(9, newSongs.count - 1) {
                                    Divider().padding(.leading, 76)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                // 新近发布
                if !newAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("新近发布")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(newAlbums.prefix(10), id: \.id) { album in
                                    NavigationLink(destination: PlaylistDetailView(
                                        playlistId: album.id,
                                        playlistName: album.name,
                                        coverUrl: album.coverUrl
                                    )) {
                                        MusicRecommendCard(
                                            imageUrl: album.coverUrl.flatMap { URL(string: $0) },
                                            title: album.name,
                                            subtitle: album.copywriter
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .task {
            await loadMusicRecommendations()
        }
    }
    
    // MARK: - 加载音乐推荐
    private func loadMusicRecommendations() async {
        do {
            // 加载推荐歌单（快乐启蒙）
            let playlists = try await musicService.getPersonalized(limit: 10)
            
            // 加载最新歌曲（使用搜索热门关键词）
            let searchSongs = try await musicService.search(keyword: "新歌", limit: 10, offset: 0)
            let songs = searchSongs.map { $0.toTrack() }
            
            // 加载新近发布（使用热门歌单）
            let albums = try await musicService.getHotPlaylist(cat: "全部", limit: 10, offset: 0)
            
            await MainActor.run {
                recommendPlaylists = playlists
                newSongs = songs
                newAlbums = albums
            }
        } catch {
            #if DEBUG
            print("加载音乐推荐失败: \(error)")
            #endif
        }
    }
    
    // MARK: - 空状态
    private func emptyView(text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [.gray, .gray.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                )
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 歌手搜索结果行
struct SearchArtistRow: View {
    let artist: SearchArtistResult
    var isStrangerTheme: Bool = false
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var placeholderBackground: Color { isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : Color(.systemGray5) }
    
    var body: some View {
        HStack(spacing: 14) {
            // 头像
            if let avatarUrl = artist.avatarUrl, let url = URL(string: avatarUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 56, height: 56)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(placeholderBackground)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(secondaryTextColor)
                        )
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(placeholderBackground)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(secondaryTextColor)
                    )
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let alias = artist.aliasText {
                        Text(alias)
                            .font(.system(size: 13))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                    if let albumSize = artist.albumSize, albumSize > 0 {
                        Text("专辑:\(albumSize)")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundColor(secondaryTextColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - 专辑搜索结果行
struct SearchAlbumRow: View {
    let album: SearchAlbumResult
    var isStrangerTheme: Bool = false
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var placeholderBackground: Color { isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : Color(.systemGray5) }
    
    var body: some View {
        HStack(spacing: 14) {
            // 封面
            if let picUrl = album.picUrl, let url = URL(string: picUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 56, height: 56)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(placeholderBackground)
                        .overlay(
                            Image(systemName: "square.stack")
                                .foregroundColor(secondaryTextColor)
                        )
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(placeholderBackground)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "square.stack")
                            .foregroundColor(secondaryTextColor)
                    )
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(album.artistName)
                        .font(.system(size: 13))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                    
                    if !album.publishYear.isEmpty {
                        Text(album.publishYear)
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundColor(secondaryTextColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - 液态玻璃搜索栏组件（性能优化版 + 搜索建议）
struct LiquidGlassSearchBarView: View {
    @Binding var shouldFocus: Bool
    @Binding var hasSearched: Bool
    let onSearch: (String) -> Void
    let onClear: () -> Void

    @State private var searchText = ""
    @State private var suggestions: SearchSuggestResult?
    @State private var showSuggestions = false
    @State private var suggestTask: Task<Void, Never>?
    @FocusState private var textFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme

    private let musicService = MusicService.shared

    // 预计算背景色，避免运行时计算
    private var fieldBackground: Color {
        colorScheme == .dark ? Color(white: 0.18).opacity(0.9) : Color(white: 0.96).opacity(0.95)
    }

    private var borderColor: Color {
        textFieldFocused
            ? Color.pink.opacity(0.5)
            : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
    }

    private var showCancelButton: Bool {
        hasSearched || textFieldFocused
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 简化的搜索框 - 减少图层
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textFieldFocused ? .pink : .secondary)

                    TextField("搜索歌曲、歌手、专辑", text: $searchText)
                        .font(.system(size: 16))
                        .focused($textFieldFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            guard !searchText.isEmpty else { return }
                            showSuggestions = false
                            onSearch(searchText)
                            textFieldFocused = false
                        }
                        .onChangeCompat(of: searchText) { _, newValue in
                            fetchSuggestions(for: newValue)
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            suggestions = nil
                            showSuggestions = false
                            onClear()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(fieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColor, lineWidth: textFieldFocused ? 1.5 : 1)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.06), radius: 8, x: 0, y: 4)

                if showCancelButton {
                    Button("取消") {
                        searchText = ""
                        textFieldFocused = false
                        suggestions = nil
                        showSuggestions = false
                        onClear()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.pink, .red], startPoint: .leading, endPoint: .trailing)
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(.easeInOut(duration: 0.2), value: showCancelButton)
            .onChangeCompat(of: shouldFocus) { _, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        textFieldFocused = true
                        shouldFocus = false
                    }
                }
            }
            
            // 搜索建议下拉
            if showSuggestions, let suggest = suggestions, !hasSearched {
                searchSuggestionsView(suggest)
            }
        }
    }
    
    // MARK: - 搜索建议视图
    private func searchSuggestionsView(_ suggest: SearchSuggestResult) -> some View {
        VStack(spacing: 0) {
            // 歌曲建议
            if let songs = suggest.songs, !songs.isEmpty {
                suggestSectionHeader(icon: "music.note", title: "歌曲")
                ForEach(songs.prefix(4)) { song in
                    Button {
                        selectSuggestion(song.name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                highlightedText(song.name, keyword: searchText)
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(1)
                                Text(song.artistName)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 歌手建议
            if let artists = suggest.artists, !artists.isEmpty {
                suggestSectionHeader(icon: "person", title: "歌手")
                ForEach(artists.prefix(3)) { artist in
                    Button {
                        selectSuggestion(artist.name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            highlightedText(artist.name, keyword: searchText)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 专辑建议
            if let albums = suggest.albums, !albums.isEmpty {
                suggestSectionHeader(icon: "square.stack", title: "专辑")
                ForEach(albums.prefix(3)) { album in
                    Button {
                        selectSuggestion(album.name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                highlightedText(album.name, keyword: searchText)
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(1)
                                if let artist = album.artist {
                                    Text(artist.name)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassEffectRounded(cornerRadius: 12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private func suggestSectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
    
    /// 高亮匹配文字
    private func highlightedText(_ text: String, keyword: String) -> Text {
        guard !keyword.isEmpty else { return Text(text).foregroundColor(.primary) }
        
        let lowText = text.lowercased()
        let lowKey = keyword.lowercased()
        
        if let range = lowText.range(of: lowKey) {
            let before = String(text[text.startIndex..<range.lowerBound])
            let match = String(text[range])
            let after = String(text[range.upperBound...])
            return Text(before).foregroundColor(.primary) +
                   Text(match).foregroundColor(.pink) +
                   Text(after).foregroundColor(.primary)
        }
        return Text(text).foregroundColor(.primary)
    }
    
    private func selectSuggestion(_ keyword: String) {
        searchText = keyword
        showSuggestions = false
        onSearch(keyword)
        textFieldFocused = false
    }
    
    // MARK: - 搜索建议请求（防抖）
    private func fetchSuggestions(for keyword: String) {
        suggestTask?.cancel()
        
        guard !keyword.isEmpty, keyword.count >= 1 else {
            suggestions = nil
            showSuggestions = false
            return
        }
        
        suggestTask = Task {
            // 300ms 防抖
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            
            do {
                let result = try await musicService.getSearchSuggest(keyword: keyword)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    suggestions = result
                    let hasSongs = !(result?.songs?.isEmpty ?? true)
                    let hasArtists = !(result?.artists?.isEmpty ?? true)
                    let hasAlbums = !(result?.albums?.isEmpty ?? true)
                    showSuggestions = hasSongs || hasArtists || hasAlbums
                }
            } catch {
                // 静默失败，不影响用户体验
            }
        }
    }
}

// MARK: - 液态玻璃搜索内容视图
struct LiquidGlassSearchContentView: View {
    let hotSearches: [HotSearch]
    let searchHistory: [String]
    let onSelectKeyword: (String) -> Void
    let onClearHistory: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 24) {
                if !searchHistory.isEmpty {
                    liquidGlassHistorySection
                }
                liquidGlassHotSearchSection
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }
    
    private var liquidGlassHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("搜索历史")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onClearHistory) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(searchHistory, id: \.self) { keyword in
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            onSelectKeyword(keyword)
                        }) {
                            LiquidGlassTag(text: keyword)
                        }
                        .buttonStyle(LiquidGlassButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var liquidGlassHotSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
                        )
                    Text("热搜榜")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                }

                Spacer()

                Text("实时更新")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color(white: 0.2).opacity(0.85) : Color(white: 0.95).opacity(0.9))
                            .overlay(
                                Capsule()
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 0.5)
                            )
                    )
            }
            .padding(.horizontal, 20)

            LiquidGlassSection {
                LazyVStack(spacing: 0) {
                    ForEach(hotSearches.indices, id: \.self) { index in
                        LiquidGlassHotSearchRow(index: index + 1, item: hotSearches[index])
                            .onTapGesture {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                onSelectKeyword(hotSearches[index].searchWord)
                            }

                        if index < hotSearches.count - 1 {
                            LiquidGlassDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 搜索结果列表（支持分页加载）
struct SearchResultsList: View {
    let searchResults: [Track]
    var isLoadingMore: Bool = false
    var hasMore: Bool = true
    var onLoadMore: (() -> Void)? = nil
    
    @ObservedObject private var audioPlayer = AudioPlayer.shared

    @State private var selectedArtist: Artist?
    @State private var selectedAlbum: Album?
    @State private var showArtistDetail = false
    @State private var showAlbumDetail = false

    private var currentTrackId: Int? {
        audioPlayer.currentTrack?.id
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, track in
                    ModernSearchTrackRow(
                        track: track,
                        isPlaying: currentTrackId == track.id,
                        onArtistTap: { artist in
                            selectedArtist = artist
                            showArtistDetail = true
                        },
                        onAlbumTap: { album in
                            selectedAlbum = album
                            showAlbumDetail = true
                        }
                    )
                    .id(track.id)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .onTapGesture {
                        audioPlayer.setPlaylist(searchResults, startAt: index)
                    }
                    .onAppear {
                        // 接近底部时加载更多
                        if index == searchResults.count - 5 && hasMore {
                            onLoadMore?()
                        }
                    }

                    if index < searchResults.count - 1 {
                        Divider()
                            .padding(.leading, 86)
                    }
                }
                
                // 加载更多指示器
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if !hasMore && searchResults.count > 0 {
                    Text("已加载全部")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding(.bottom, 120)
        }
        .navigationDestination(isPresented: $showArtistDetail) {
            if let artist = selectedArtist {
                ArtistDetailView(artistId: artist.id, artistName: artist.name)
            }
        }
        .navigationDestination(isPresented: $showAlbumDetail) {
            if let album = selectedAlbum {
                AlbumDetailView(albumId: album.id, albumName: album.name)
            }
        }
    }
}

// MARK: - 现代化搜索结果Track行（简化版）
struct ModernSearchTrackRow: View {
    let track: Track
    let isPlaying: Bool
    var onArtistTap: ((Artist) -> Void)? = nil
    var onAlbumTap: ((Album) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // 封面
            ZStack {
                if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 52, height: 52)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        coverPlaceholder
                    }
                } else {
                    coverPlaceholder
                }

                if isPlaying {
                    Circle()
                        .fill(.black.opacity(0.5))
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.system(size: 15, weight: isPlaying ? .semibold : .regular))
                    .foregroundColor(isPlaying ? .red : .primary)
                    .lineLimit(1)

                Text("\(track.artistName) · \(track.albumName)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 更多按钮
            Menu {
                if let artist = track.ar?.first {
                    Button {
                        onArtistTap?(artist)
                    } label: {
                        Label("查看歌手", systemImage: "person")
                    }
                }

                if let album = track.al {
                    Button {
                        onAlbumTap?(album)
                    } label: {
                        Label("查看专辑", systemImage: "square.stack")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))

            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - 液态玻璃热搜行
struct LiquidGlassHotSearchRow: View {
    let index: Int
    let item: HotSearch
    @Environment(\.colorScheme) var colorScheme

    private var rankColor: Color {
        switch index {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .secondary
        }
    }
    
    private var rankGradient: [Color] {
        switch index {
        case 1: return [.red, .orange]
        case 2: return [.orange, .yellow]
        case 3: return [.yellow, .green]
        default: return [.secondary, .secondary]
        }
    }

    private var tagInfo: (text: String, color: Color)? {
        if let iconType = item.iconType {
            switch iconType {
            case 1: return ("热", .red)
            case 2: return ("新", .green)
            case 3: return ("飙", .orange)
            case 5: return ("荐", .purple)
            default: return nil
            }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 14) {
            // 液态玻璃排名徽章
            ZStack {
                if index <= 3 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [rankColor.opacity(0.3), rankColor.opacity(0.1), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 16
                            )
                        )
                }
                
                Text("\(index)")
                    .font(.system(size: index <= 3 ? 16 : 14, weight: index <= 3 ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        index <= 3
                            ? LinearGradient(colors: rankGradient, startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [.secondary, .secondary], startPoint: .top, endPoint: .bottom)
                    )
            }
            .frame(width: 32, height: 32)

            // 内容
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.searchWord)
                        .font(.system(size: 15, weight: index <= 3 ? .semibold : .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let tag = tagInfo {
                        Text(tag.text)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [tag.color, tag.color.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
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

            // 热度
            if let score = item.score {
                Text(formatScore(score))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func formatScore(_ score: Int) -> String {
        if score >= 10000 {
            return String(format: "%.1f万", Double(score) / 10000.0)
        }
        return "\(score)"
    }
}

// MARK: - 分类卡片组件
struct CategoryCard: View {
    let category: MusicCategory
    
    private var cardHeight: CGFloat {
        min((UIScreen.main.bounds.width - 44) / 2 * 0.75, 200)
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 渐变背景
            LinearGradient(
                colors: category.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // 标题
            Text(category.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .padding(14)
        }
        .frame(height: cardHeight)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    NavigationView {
        SearchView(shouldFocus: .constant(false))
    }
}

