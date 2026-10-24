import SwiftUI

// MARK: - 搜索导航目标
struct ArtistDestination: Hashable {
    let id: Int
    let name: String
}

struct AlbumDestination: Hashable {
    let id: Int
    let name: String
}

// MARK: - 搜索历史管理器
@MainActor
class SearchHistoryManager: ObservableObject {
    static let shared = SearchHistoryManager()
    
    @Published var history: [SearchHistoryEntry] = []
    
    private let userDefaultsKey = "SearchHistory"
    private let maxHistoryCount = 20
    
    init() {
        loadHistory()
    }
    
    func addSearch(keyword: String, type: SearchHistoryEntry.SearchType = .keyword) {
        // 移除重复项
        history.removeAll { $0.keyword == keyword }
        
        // 添加到开头
        let entry = SearchHistoryEntry(keyword: keyword, type: type, timestamp: Date())
        history.insert(entry, at: 0)
        
        // 限制数量
        if history.count > maxHistoryCount {
            history = Array(history.prefix(maxHistoryCount))
        }
        
        saveHistory()
    }
    
    func removeSearch(keyword: String) {
        history.removeAll { $0.keyword == keyword }
        saveHistory()
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data) {
            history = decoded
        }
    }
}

// MARK: - 搜索历史条目
struct SearchHistoryEntry: Codable, Identifiable {
    var id: String { keyword }
    let keyword: String
    let type: SearchType
    let timestamp: Date
    
    enum SearchType: String, Codable {
        case keyword
        case song
        case album
        case artist
    }
}

// MARK: - 搜索分类
enum SearchCategory: String, CaseIterable {
    case best = "最佳结果"
    case artist = "艺人"
    case album = "专辑"
    case song = "歌曲"
    
    var icon: String {
        switch self {
        case .best: return "star.fill"
        case .artist: return "person.fill"
        case .album: return "square.stack.fill"
        case .song: return "music.note"
        }
    }
}

// MARK: - 全屏搜索界面
struct FullScreenSearchView: View {
    @Binding var isSearchMode: Bool
    let previousTabIcon: String
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }

    
    // 搜索状态
    @StateObject private var historyManager = SearchHistoryManager.shared
    @State private var hotSearches: [HotSearch] = []
    @State private var selectedCategory: SearchCategory = .best
    
    // 搜索结果
    @State private var songResults: [SearchSong] = []
    @State private var artistResults: [SearchArtistResult] = []
    @State private var albumResults: [SearchAlbumResult] = []
    
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    
    // 搜索任务管理（用于取消旧搜索）
    @State private var searchTask: Task<Void, Never>?
    
    // 导航路径
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // 上方搜索内容区域
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if hasSearched {
                            // 分类标签栏
                            categoryTabBar
                            
                            // 搜索结果
                            searchResultsView
                        } else {
                            // 搜索历史和热搜
                            searchHistoryView
                            hotSearchView
                        }
                    }
                    .padding(.bottom, 100)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer(minLength: 0)
                
                // 底部搜索栏
                searchBarView
            }
            .background {
                ThemedBackground()
                    .environmentObject(themeManager)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ArtistDestination.self) { dest in
                ArtistDetailView(artistId: dest.id, artistName: dest.name)
            }
            .navigationDestination(for: AlbumDestination.self) { dest in
                AlbumDetailView(albumId: dest.id, albumName: dest.name)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            loadHotSearches()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
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
                            .foregroundColor(selectedCategory == category ? .white : textColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                if selectedCategory == category {
                                    Capsule().fill(accentColor)
                                } else {
                                    Capsule().fill(.ultraThinMaterial)
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - 搜索历史视图
    @ViewBuilder
    private var searchHistoryView: some View {
        if !historyManager.history.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("最近搜索")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(textColor)
                    
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
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // 搜索历史列表
                ForEach(historyManager.history) { entry in
                    SearchHistoryRowView(
                        entry: entry,
                        isStrangerTheme: isStrangerTheme,
                        onTap: {
                            searchText = entry.keyword
                            performSearch()
                        },
                        onDelete: {
                            withAnimation {
                                historyManager.removeSearch(keyword: entry.keyword)
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - 热搜视图
    @ViewBuilder
    private var hotSearchView: some View {
        if !hotSearches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("热门搜索")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(textColor)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                
                // 热搜列表
                ForEach(Array(hotSearches.enumerated()), id: \.element.id) { index, item in
                    HotSearchRow(index: index + 1, item: item, isStrangerTheme: isStrangerTheme) {
                        searchText = item.searchWord
                        performSearch()
                    }
                }
            }
        }
    }
    
    // MARK: - 搜索结果视图
    @ViewBuilder
    private var searchResultsView: some View {
        if isSearching {
            TrackListSkeletonView(count: 10)
                .padding(.top, 20)
        } else if let error = errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundColor(secondaryTextColor)
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            switch selectedCategory {
            case .best:
                bestResultsView
            case .artist:
                artistResultsView
            case .album:
                albumResultsView
            case .song:
                songResultsView
            }
        }
    }
    
    // MARK: - 最佳结果视图
    @ViewBuilder
    private var bestResultsView: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            // 艺人结果（显示第一个匹配的艺人）
            if let firstArtist = artistResults.first {
                BestMatchArtistRow(artist: firstArtist, isStrangerTheme: isStrangerTheme)
            }
            
            // 歌曲结果
            ForEach(songResults) { song in
                SearchResultRow(song: song, coverUrl: getCoverUrl(for: song), isStrangerTheme: isStrangerTheme) {
                    playSong(song)
                }
            }
            
            if songResults.isEmpty && artistResults.isEmpty {
                emptyResultView
            }
        }
    }
    
    // MARK: - 艺人结果视图
    @ViewBuilder
    private var artistResultsView: some View {
        if artistResults.isEmpty {
            emptyResultView
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(artistResults) { artist in
                    ArtistResultRow(artist: artist, isStrangerTheme: isStrangerTheme)
                }
            }
        }
    }
    
    // MARK: - 专辑结果视图
    @ViewBuilder
    private var albumResultsView: some View {
        if albumResults.isEmpty {
            emptyResultView
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(albumResults) { album in
                    AlbumResultRow(album: album, isStrangerTheme: isStrangerTheme)
                }
            }
        }
    }
    
    // MARK: - 歌曲结果视图
    @ViewBuilder
    private var songResultsView: some View {
        if songResults.isEmpty {
            emptyResultView
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(songResults) { song in
                    SearchResultRow(song: song, coverUrl: getCoverUrl(for: song), isStrangerTheme: isStrangerTheme) {
                        playSong(song)
                    }
                }
            }
        }
    }
    
    // MARK: - 空结果视图
    private var emptyResultView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(secondaryTextColor)
            Text("未找到\"\(searchText)\"的相关结果")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - 底部搜索栏
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @State private var showPlayer = false
    
    private var showMiniPlayer: Bool {
        audioPlayer.currentTrack != nil
    }
    
    private var searchBarView: some View {
        VStack(spacing: 0) {
            // 迷你播放器
            if showMiniPlayer {
                SearchMiniPlayerBar(showPlayer: $showPlayer, isStrangerTheme: isStrangerTheme)
            }
            
            // 搜索栏
            HStack(spacing: 10) {
                // 左边返回按钮（显示之前 Tab 的图标）
                Button {
                    HapticFeedback.light()
                    isSearchFocused = false
                    dismiss()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSearchMode = false
                    }
                } label: {
                    Image(systemName: previousTabIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(textColor)
                        .frame(width: 48, height: 48)
                }
                .liquidGlassCircle()
                
                // 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    
                    TextField("艺人、歌曲、歌词以及更多内容", text: $searchText)
                        .font(.system(size: 16))
                        .foregroundColor(textColor)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            hasSearched = false
                            songResults = []
                            artistResults = []
                            albumResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                
                // 关闭按钮
                Button {
                    HapticFeedback.light()
                    isSearchFocused = false
                    dismiss()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSearchMode = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(textColor)
                        .frame(width: 48, height: 48)
                }
                .liquidGlassCircle()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView()
        }
    }
    
    // MARK: - 加载热搜
    private func loadHotSearches() {
        Task {
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
    }
    
    // 歌曲详情缓存（包含封面）
    @State private var songDetailsCache: [Int: Track] = [:]
    
    // MARK: - 执行搜索
    
    private func performSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        
        // 取消上一次搜索任务（避免旧结果覆盖新结果）
        searchTask?.cancel()
        
        // 添加到搜索历史
        historyManager.addSearch(keyword: keyword)
        
        isSearching = true
        hasSearched = true
        errorMessage = nil
        selectedCategory = .best
        
        searchTask = Task {
            do {
                // 网易云搜索
                async let songsTask = MusicService.shared.search(keyword: keyword, limit: 30)
                async let artistsTask = MusicService.shared.searchArtists(keyword: keyword, limit: 10)
                async let albumsTask = MusicService.shared.searchAlbums(keyword: keyword, limit: 10)
                
                let (songRes, artistRes, albumRes) = try await (songsTask, artistsTask, albumsTask)
                
                // 检查任务是否已被取消（用户可能已发起新搜索）
                guard !Task.isCancelled else { return }
                
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
                        guard !Task.isCancelled else { return }
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
                if !Task.isCancelled {
                    await MainActor.run {
                        errorMessage = "搜索失败，请重试"
                        isSearching = false
                    }
                }
            }
        }
    }
    
    // 获取歌曲封面（优先使用详情缓存）
    private func getCoverUrl(for song: SearchSong) -> String? {
        if let cached = songDetailsCache[song.id], let cover = cached.coverUrl {
            return cover
        }
        return song.coverUrl
    }
    
    // MARK: - 播放歌曲
    private func playSong(_ song: SearchSong) {
        #if DEBUG
        print("🔴 [FullScreenSearch] playSong 被调用: \(song.name), id: \(song.id)")
        print("🔴 [FullScreenSearch] songResults数量: \(songResults.count)")
        #endif
        
        // 转换时传入缓存的封面 URL
        let tracks = songResults.map { s in
            s.toTrack(withCoverUrl: getCoverUrl(for: s))
        }
        
        #if DEBUG
        print("🔴 [FullScreenSearch] tracks数量: \(tracks.count)")
        #endif
        
        if let index = songResults.firstIndex(where: { $0.id == song.id }) {
            #if DEBUG
            print("🔴 [FullScreenSearch] 找到索引: \(index)，开始播放")
            #endif
            AudioPlayer.shared.setPlaylist(tracks, startAt: index)
        } else {
            #if DEBUG
            print("🔴 [FullScreenSearch] 未找到匹配的歌曲索引")
            #endif
            // 如果找不到索引，直接播放第一首
            if !tracks.isEmpty {
                AudioPlayer.shared.setPlaylist(tracks, startAt: 0)
            }
        }
        HapticFeedback.light()
    }
}

// MARK: - 搜索界面迷你播放器
struct SearchMiniPlayerBar: View {
    @Binding var showPlayer: Bool
    var isStrangerTheme: Bool = false
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    
    var body: some View {
        HStack(spacing: 8) {
            // 封面和歌曲信息区域 - 使用 Button 确保点击可靠
            Button {
                HapticFeedback.light()
                showPlayer = true
            } label: {
                HStack(spacing: 12) {
                    // 封面
                    Group {
                        if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                           let url = URL(string: coverUrl) {
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color(.systemGray5))
                            }
                            .id(coverUrl)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // 歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioPlayer.currentTrack?.name ?? "未播放")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(textColor)
                            .lineLimit(1)
                        
                        Text(audioPlayer.currentTrack?.artistName ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(SearchMiniPlayerTapStyle())
            
            // 播放/暂停按钮
            Button {
                HapticFeedback.light()
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(textColor)
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SearchMiniPlayerTapStyle())
            
            // 下一首按钮
            Button {
                HapticFeedback.light()
                audioPlayer.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(textColor)
                    .frame(width: 52, height: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SearchMiniPlayerTapStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 搜索迷你播放器点击样式
struct SearchMiniPlayerTapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 最佳匹配艺人行
struct BestMatchArtistRow: View {
    let artist: SearchArtistResult
    var isStrangerTheme: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    
    var body: some View {
        NavigationLink(value: ArtistDestination(id: artist.id, name: artist.name)) {
            HStack(spacing: 14) {
                // 艺人头像（圆形）
                if let avatarUrl = artist.avatarUrl, let url = URL(string: avatarUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 24))
                                .foregroundColor(secondaryTextColor)
                        )
                }
                
                // 艺人信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    
                    Text("艺人")
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 艺人结果行
struct ArtistResultRow: View {
    let artist: SearchArtistResult
    var isStrangerTheme: Bool = false
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    
    var body: some View {
        NavigationLink(value: ArtistDestination(id: artist.id, name: artist.name)) {
            HStack(spacing: 12) {
                // 头像
                if let avatarUrl = artist.avatarUrl, let url = URL(string: avatarUrl) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color(.systemGray5))
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(secondaryTextColor)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(artist.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("艺人")
                            .font(.system(size: 13))
                            .foregroundColor(secondaryTextColor)
                        
                        if let albumSize = artist.albumSize, albumSize > 0 {
                            Text("\(albumSize)张专辑")
                                .font(.system(size: 13))
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 专辑结果行
struct AlbumResultRow: View {
    let album: SearchAlbumResult
    var isStrangerTheme: Bool = false
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    
    var body: some View {
        NavigationLink(value: AlbumDestination(id: album.id, name: album.name)) {
            HStack(spacing: 12) {
                // 封面
                if let picUrl = album.picUrl, let url = URL(string: picUrl) {
                    CachedAsyncImage(url: url) { image in
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
                                .foregroundColor(secondaryTextColor)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    
                    Text("专辑 · \(album.artistName)")
                        .font(.system(size: 13))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 搜索历史行视图
struct SearchHistoryRowView: View {
    let entry: SearchHistoryEntry
    var isStrangerTheme: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18))
                .foregroundColor(secondaryTextColor)
                .frame(width: 24)
            
            Text(entry.keyword)
                .font(.system(size: 16))
                .foregroundColor(textColor)
                .lineLimit(1)
            
            Spacer()
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - 热搜行视图
struct HotSearchRow: View {
    let index: Int
    let item: HotSearch
    var isStrangerTheme: Bool = false
    let onTap: () -> Void
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    
    private var indexColor: Color {
        switch index {
        case 1: return isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red
        case 2: return .orange
        case 3: return .yellow
        default: return secondaryTextColor
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
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    
                    // 热搜标签
                    if let iconType = item.iconType {
                        hotSearchTag(iconType: iconType)
                    }
                }
                
                if let content = item.content, !content.isEmpty {
                    Text(content)
                        .font(.system(size: 12))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let score = item.score {
                Text(formatScore(score))
                    .font(.system(size: 12))
                    .foregroundColor(secondaryTextColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticFeedback.light()
            onTap()
        }
    }
    
    @ViewBuilder
    private func hotSearchTag(iconType: Int) -> some View {
        let (text, color): (String, Color) = {
            switch iconType {
            case 1: return ("热", isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red)
            case 2: return ("新", isStrangerTheme ? Color(red: 0.2, green: 0.6, blue: 1.0) : .blue)
            case 3: return ("飙", .orange)
            case 5: return ("荐", .purple)
            default: return ("", .clear)
            }
        }()
        
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(color)
                .cornerRadius(4)
        }
    }
    
    private func formatScore(_ score: Int) -> String {
        if score >= 10000 {
            return String(format: "%.1f万", Double(score) / 10000)
        }
        return "\(score)"
    }
}

// MARK: - 搜索结果行视图
struct SearchResultRow: View {
    let song: SearchSong
    var coverUrl: String?  // 可选的封面 URL（优先使用）
    var isStrangerTheme: Bool = false
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    
    // 导航状态
    @State private var navigateToAlbum = false
    @State private var navigateToArtist = false
    
    private var displayCoverUrl: String? {
        coverUrl ?? song.coverUrl
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let coverUrl = displayCoverUrl, let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url) { image in
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
                            .foregroundColor(secondaryTextColor)
                    )
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(song.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                Text("\(song.artistName) - \(song.albumName)")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryTextColor)
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
                
                Divider()
                
                if song.albumId != nil {
                    Button {
                        navigateToAlbum = true
                    } label: {
                        Label("查看专辑", systemImage: "square.stack")
                    }
                }
                
                if song.artistId != nil {
                    Button {
                        navigateToArtist = true
                    } label: {
                        Label("查看艺人", systemImage: "person")
                    }
                }
                
                Divider()
                
                Button {
                    let shareText = "\(song.name) - \(song.artistName)"
                    let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        rootVC.present(activityVC, animated: true)
                    }
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .background(
            Group {
                EmptyView()
            }
        )
        .navigationDestination(isPresented: $navigateToAlbum) {
            if let albumId = song.albumId {
                AlbumDetailView(albumId: albumId, albumName: song.albumName)
            }
        }
        .navigationDestination(isPresented: $navigateToArtist) {
            if let artistId = song.artistId {
                ArtistDetailView(artistId: artistId, artistName: song.artistName)
            }
        }
    }
}

// MARK: - 搜索模式下的内容视图（分类浏览）
struct SearchContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    // 歌单分类数据（Apple Music 风格）
    private let playlistCategories: [SearchCategoryItem] = [
        SearchCategoryItem(title: "C-Pop", apiTag: "华语", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        SearchCategoryItem(title: "空间音频", apiTag: "流行", gradientColors: [Color(red: 0.8, green: 0.3, blue: 0.35), Color(red: 0.85, green: 0.35, blue: 0.4)]),
        SearchCategoryItem(title: "国语流行", apiTag: "国语", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        SearchCategoryItem(title: "DJ 混音精选", apiTag: "电子", gradientColors: [Color(red: 0.8, green: 0.3, blue: 0.35), Color(red: 0.85, green: 0.35, blue: 0.4)]),
        SearchCategoryItem(title: "月度音乐回忆", apiTag: "流行", gradientColors: [Color(red: 0.5, green: 0.75, blue: 0.9), Color(red: 0.6, green: 0.8, blue: 0.95)]),
        SearchCategoryItem(title: "排行榜", apiTag: "流行", gradientColors: [Color(red: 0.6, green: 0.65, blue: 0.4), Color(red: 0.65, green: 0.7, blue: 0.45)]),
        SearchCategoryItem(title: "爵士乐", apiTag: "爵士", gradientColors: [Color(red: 0.35, green: 0.55, blue: 0.65), Color(red: 0.45, green: 0.65, blue: 0.75)]),
        SearchCategoryItem(title: "创作与制作", apiTag: "流行", gradientColors: [Color(red: 0.6, green: 0.65, blue: 0.4), Color(red: 0.65, green: 0.7, blue: 0.45)]),
        SearchCategoryItem(title: "国际流行", apiTag: "欧美", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        SearchCategoryItem(title: "粤语流行", apiTag: "粤语", gradientColors: [Color(red: 0.9, green: 0.5, blue: 0.6), Color(red: 0.95, green: 0.6, blue: 0.7)]),
        SearchCategoryItem(title: "嘻哈 / 说唱", apiTag: "说唱", gradientColors: [Color(red: 0.4, green: 0.5, blue: 0.75), Color(red: 0.5, green: 0.6, blue: 0.85)]),
        SearchCategoryItem(title: "古典音乐", apiTag: "古典", gradientColors: [Color(red: 0.6, green: 0.4, blue: 0.7), Color(red: 0.7, green: 0.5, blue: 0.8)])
    ]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)
            ], spacing: 12) {
                ForEach(playlistCategories) { category in
                    NavigationLink {
                        CategoryPlaylistListView(category: category.apiTag, title: category.title)
                    } label: {
                        SearchCategoryCard(category: category)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background {
            ThemedBackground()
                .environmentObject(ThemeManager.shared)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - 分类模型
struct SearchCategoryItem: Identifiable {
    let id = UUID()
    let title: String
    let apiTag: String
    let gradientColors: [Color]
}

// MARK: - 分类卡片
struct SearchCategoryCard: View {
    let category: SearchCategoryItem
    
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

#Preview {
    FullScreenSearchView(isSearchMode: .constant(true), previousTabIcon: "house.fill")
}
