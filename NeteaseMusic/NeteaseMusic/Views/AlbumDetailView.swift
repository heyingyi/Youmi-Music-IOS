import SwiftUI

// MARK: - 专辑详情视图
struct AlbumDetailView: View {
    let albumId: Int
    let albumName: String
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @State private var album: AlbumDetail?
    @State private var songs: [Track] = []
    @State private var isLoading = true
    @State private var showDescription = false
    @State private var scrollOffset: CGFloat = 0
    @State private var searchText = ""
    @State private var isSearching = false
    
    private let musicService = MusicService.shared
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }

    
    // 过滤后的歌曲列表
    private var filteredSongs: [Track] {
        if searchText.isEmpty {
            return songs
        }
        let query = searchText.lowercased()
        return songs.filter {
            $0.name.lowercased().contains(query) ||
            $0.artistName.lowercased().contains(query)
        }
    }
    
    var body: some View {
        ZStack {
            // 背景
            backgroundView
            
            // 内容
            ScrollView(showsIndicators: false) {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: AlbumScrollOffsetKey.self,
                        value: geo.frame(in: .named("albumScroll")).minY
                    )
                }
                .frame(height: 0)
                
                VStack(spacing: 0) {
                    // 顶部留白
                    Color.clear.frame(height: 100)
                    
                    // 主内容区
                    VStack(spacing: 24) {
                        // 专辑信息
                        albumInfoSection
                        
                        // 歌曲列表
                        if !songs.isEmpty {
                            songsSection
                        }
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.ultraThinMaterial)
                    )
                }
            }
            .coordinateSpace(name: "albumScroll")
            .onPreferenceChange(AlbumScrollOffsetKey.self) { value in
                scrollOffset = value
            }
            
            // 加载中
            if isLoading {
                loadingOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(scrollOffset < -180 ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(album?.name ?? albumName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .opacity(scrollOffset < -180 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: scrollOffset < -180)
            }
        }
        .ignoresSafeArea()
        .enableSwipeBack()
        .task {
            await loadData()
        }
        .sheet(isPresented: $showDescription) {
            if let desc = album?.description, !desc.isEmpty {
                AlbumDescriptionSheet(title: album?.name ?? "", description: desc)
            }
        }
    }
    
    // MARK: - 背景视图
    private var backgroundView: some View {
        ThemedBackground()
            .environmentObject(themeManager)
    }
    
    
    // MARK: - 专辑信息区域
    private var albumInfoSection: some View {
        VStack(spacing: 20) {
            // 封面
            if let picUrl = album?.picUrl, let url = URL(string: picUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 200, height: 200)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color(.systemGray4), Color(.systemGray5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            }
            
            // 专辑名
            Text(album?.name ?? albumName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // 歌手名
            if let artistName = album?.artistName {
                NavigationLink(destination: artistDestination) {
                    HStack(spacing: 4) {
                        Text(artistName)
                            .font(.system(size: 15))
                            .foregroundColor(secondaryTextColor)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(secondaryTextColor)
                    }
                }
            }
            
            // 发行信息
            if let album = album {
                HStack(spacing: 16) {
                    if !album.publishTimeText.isEmpty {
                        Label(album.publishTimeText, systemImage: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                    }
                    
                    if let company = album.company, !company.isEmpty {
                        Label(company, systemImage: "building.2")
                            .font(.system(size: 12))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }
                }
            }
            
            // 简介按钮
            if let desc = album?.description, !desc.isEmpty {
                Button(action: { showDescription = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                        Text("查看专辑简介")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                }
            }
            
            // 播放全部按钮
            if !songs.isEmpty {
                HStack(spacing: 16) {
                    // 播放全部
                    Button(action: {
                        audioPlayer.setPlaylist(songs, startAt: 0)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14))
                            Text("播放全部")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: isStrangerTheme 
                                    ? [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]
                                    : [.pink, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    
                    // 随机播放
                    Button(action: {
                        audioPlayer.playMode = .random
                        audioPlayer.setPlaylist(songs, startAt: 0)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 14))
                            Text("随机播放")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - 歌手跳转
    @ViewBuilder
    private var artistDestination: some View {
        if let artist = album?.artist {
            ArtistDetailView(artistId: artist.id, artistName: artist.name)
        } else if let artists = album?.artists, let first = artists.first {
            ArtistDetailView(artistId: first.id, artistName: first.name)
        } else {
            EmptyView()
        }
    }
    
    // MARK: - 歌曲列表区域
    private var songsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 16))
                        .foregroundColor(isStrangerTheme ? Color(red: 0.2, green: 0.6, blue: 1.0) : .blue)
                    Text("全部歌曲")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(textColor)
                }
                
                Spacer()
                
                // 搜索按钮
                Button(action: { 
                    withAnimation(.spring(response: 0.3)) {
                        isSearching.toggle()
                        if !isSearching {
                            searchText = ""
                        }
                    }
                }) {
                    Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(secondaryTextColor)
                }
                
                if !isSearching {
                    Text("\(songs.count) 首")
                        .font(.system(size: 13))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .padding(.horizontal, 20)
            
            // 搜索框
            if isSearching {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(secondaryTextColor)
                    TextField("搜索歌曲", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(textColor)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                }
                .padding(10)
                .background(isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : Color(.tertiarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 搜索结果为空
            if isSearching && !searchText.isEmpty && filteredSongs.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 30))
                            .foregroundColor(secondaryTextColor.opacity(0.5))
                        Text("未找到 \"\(searchText)\"")
                            .font(.system(size: 14))
                            .foregroundColor(secondaryTextColor)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                // 歌曲列表
                LazyVStack(spacing: 0) {
                    let songsToShow = isSearching ? filteredSongs : songs
                    ForEach(Array(songsToShow.enumerated()), id: \.element.id) { index, track in
                        let originalIndex = songs.firstIndex(where: { $0.id == track.id }) ?? index
                        AlbumTrackRow(
                            track: track,
                            index: originalIndex + 1,
                            isPlaying: audioPlayer.currentTrack?.id == track.id,
                            isStrangerTheme: isStrangerTheme
                        )
                        .onTapGesture {
                            audioPlayer.setPlaylist(songs, startAt: originalIndex)
                        }
                        
                        if index < songsToShow.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .glassEffectRounded(cornerRadius: 16)
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - 加载中遮罩
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : nil)
                Text("加载中...")
                    .font(.system(size: 14))
                    .foregroundColor(secondaryTextColor)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - 加载数据
    private func loadData() async {
        do {
            let result = try await musicService.getAlbumDetail(id: albumId)
            
            await MainActor.run {
                album = result.album
                songs = result.songs
                isLoading = false
            }
        } catch {
            #if DEBUG
            print("Load album data error: \(error)")
            #endif
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - 滚动偏移量 Key
private struct AlbumScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 专辑歌曲行
struct AlbumTrackRow: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    var isStrangerTheme: Bool = false
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .red }
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号
            ZStack {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accentColor)
                } else {
                    Text("\(index)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .frame(width: 32)
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.system(size: 15, weight: isPlaying ? .semibold : .regular))
                    .foregroundColor(isPlaying ? accentColor : textColor)
                    .lineLimit(1)
                
                Text(track.artistName)
                    .font(.system(size: 12))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 时长
            Text(track.durationText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(secondaryTextColor)
            
            // 更多
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(secondaryTextColor)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - 专辑简介弹窗
struct AlbumDescriptionSheet: View {
    let title: String
    let description: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineSpacing(6)
                    .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        AlbumDetailView(albumId: 74824603, albumName: "测试专辑")
    }
}
