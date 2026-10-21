import SwiftUI
import MusicKit

// MARK: - 分类枚举
enum AppleMusicCategory: String, CaseIterable {
    case songs = "歌曲"
    case albums = "专辑"
    case artists = "艺人"
    case playlists = "播放列表"
    
    var icon: String {
        switch self {
        case .songs: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .playlists: return "music.note.list"
        }
    }
}

// MARK: - 专辑显示模式
enum AlbumDisplayMode: String {
    case grid = "网格"
    case list = "列表"
    
    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

// MARK: - 专辑排序方式
enum AlbumSortOption: String, CaseIterable {
    case dateAdded = "添加日期"
    case name = "名称"
    case artist = "艺人"
    case year = "年份"
}

struct AppleMusicView: View {
    @StateObject private var service = AppleMusicService.shared
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var selectedCategory: AppleMusicCategory = .songs
    @State private var librarySongs: [Song] = []
    @State private var libraryAlbums: [MusicKit.Album] = []
    @State private var libraryArtists: [MusicKit.Artist] = []
    @State private var libraryPlaylists: [Playlist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var albumDisplayMode: AlbumDisplayMode = .grid
    @State private var albumSortOption: AlbumSortOption = .dateAdded
    @State private var showAlbumSortSheet = false
    
    private var isStrangerTheme: Bool { themeManager.themeStyle == .strangerThings }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .pink }
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            
            if !service.isAuthorized {
                authorizationView
            } else {
                VStack(spacing: 0) {
                    categoryPicker
                    libraryContent
                }
            }
        }
        .navigationTitle("Apple Music")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if service.isAuthorized {
                await loadAllCategories()
            }
        }
    }

    // MARK: - 分类选择器
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AppleMusicCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.caption)
                            Text(category.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedCategory == category ? accentColor : Color(.systemGray5))
                        )
                        .foregroundColor(selectedCategory == category ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
    
    // MARK: - 授权视图
    private var authorizationView: some View {
        VStack(spacing: 24) {
            Image(systemName: "apple.logo")
                .font(.system(size: 60))
                .foregroundColor(accentColor)
            
            Text("连接 Apple Music")
                .font(.title2.bold())
            
            Text("授权后可以访问你的 Apple Music 资料库")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                Task {
                    await service.requestAuthorization()
                    if service.isAuthorized {
                        await loadAllCategories()
                    }
                }
            } label: {
                Text("授权访问")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accentColor)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - 资料库内容
    private var libraryContent: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("重试") {
                        Task { await loadAllCategories() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                switch selectedCategory {
                case .songs:
                    songsListView
                case .albums:
                    albumsGridView
                case .artists:
                    artistsListView
                case .playlists:
                    playlistsListView
                }
            }
        }
    }

    // MARK: - 歌曲列表
    private var songsListView: some View {
        Group {
            if librarySongs.isEmpty {
                emptyView(icon: "music.note", text: "没有歌曲")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HStack {
                            Text("\(librarySongs.count) 首歌曲")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                playAll()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                    Text("播放全部")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(accentColor)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        
                        ForEach(librarySongs, id: \.id) { song in
                            AppleMusicSongRow(song: song)
                            Divider().padding(.leading, 74)
                        }
                    }
                    .padding(.bottom, 120)
                }
                .refreshable { await loadAllCategories() }
            }
        }
    }
    
    // MARK: - 排序后的专辑
    private var sortedAlbums: [MusicKit.Album] {
        switch albumSortOption {
        case .dateAdded:
            return libraryAlbums // 默认顺序就是添加日期
        case .name:
            return libraryAlbums.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .artist:
            return libraryAlbums.sorted { $0.artistName.localizedCompare($1.artistName) == .orderedAscending }
        case .year:
            return libraryAlbums.sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        }
    }
    
    // MARK: - 专辑视图
    private var albumsGridView: some View {
        Group {
            if libraryAlbums.isEmpty {
                emptyView(icon: "square.stack", text: "没有专辑")
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // 工具栏：数量 + 显示模式 + 排序
                        HStack {
                            Text("\(libraryAlbums.count) 张专辑")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // 显示模式切换
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    albumDisplayMode = albumDisplayMode == .grid ? .list : .grid
                                }
                            } label: {
                                Image(systemName: albumDisplayMode == .grid ? "list.bullet" : "square.grid.2x2")
                                    .font(.subheadline)
                                    .foregroundColor(accentColor)
                            }
                            
                            // 排序
                            Button {
                                showAlbumSortSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.arrow.down")
                                    Text(albumSortOption.rawValue)
                                }
                                .font(.caption)
                                .foregroundColor(accentColor)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        
                        if albumDisplayMode == .grid {
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
                            ], spacing: 20) {
                                ForEach(sortedAlbums, id: \.id) { album in
                                    AppleMusicAlbumCard(album: album, accentColor: accentColor)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(sortedAlbums, id: \.id) { album in
                                    AppleMusicAlbumListRow(album: album, accentColor: accentColor)
                                    Divider().padding(.leading, 74)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 120)
                }
                .refreshable { await loadAllCategories() }
                .confirmationDialog("排序方式", isPresented: $showAlbumSortSheet) {
                    ForEach(AlbumSortOption.allCases, id: \.self) { option in
                        Button(option == albumSortOption ? "✓ \(option.rawValue)" : option.rawValue) {
                            albumSortOption = option
                        }
                    }
                    Button("取消", role: .cancel) {}
                }
            }
        }
    }
    
    // MARK: - 艺人列表
    private var artistsListView: some View {
        Group {
            if libraryArtists.isEmpty {
                emptyView(icon: "person.2", text: "没有艺人")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Text("\(libraryArtists.count) 位艺人")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                        
                        ForEach(libraryArtists, id: \.id) { artist in
                            AppleMusicArtistRow(artist: artist, accentColor: accentColor)
                            Divider().padding(.leading, 74)
                        }
                    }
                    .padding(.bottom, 120)
                }
                .refreshable { await loadAllCategories() }
            }
        }
    }
    
    // MARK: - 播放列表
    private var playlistsListView: some View {
        Group {
            if libraryPlaylists.isEmpty {
                emptyView(icon: "music.note.list", text: "没有播放列表")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Text("\(libraryPlaylists.count) 个播放列表")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                        
                        ForEach(libraryPlaylists, id: \.id) { playlist in
                            NavigationLink {
                                AppleMusicPlaylistDetailView(playlist: playlist)
                                    .environmentObject(themeManager)
                            } label: {
                                AppleMusicPlaylistRow(playlist: playlist, accentColor: accentColor)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 74)
                        }
                    }
                    .padding(.bottom, 120)
                }
                .refreshable { await loadAllCategories() }
            }
        }
    }
    
    // MARK: - 空状态
    private func emptyView(icon: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(text)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 加载所有分类
    private func loadAllCategories() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let songsTask = service.getAllLibrarySongs()
            async let albumsTask = service.getAllLibraryAlbums()
            async let artistsTask = service.getAllLibraryArtists()
            async let playlistsTask = service.getAllLibraryPlaylists()
            
            let (songs, albums, artists, playlists) = try await (songsTask, albumsTask, artistsTask, playlistsTask)
            
            librarySongs = songs
            libraryAlbums = albums
            libraryArtists = artists
            libraryPlaylists = playlists
            
            print("✅ 资料库加载完成: \(songs.count) 首歌, \(albums.count) 张专辑, \(artists.count) 位艺人, \(playlists.count) 个播放列表")
        } catch {
            print("❌ 资料库加载失败: \(error)")
            errorMessage = "加载失败，请重试"
        }
        
        isLoading = false
    }
    
    // MARK: - 播放全部
    private func playAll() {
        guard !librarySongs.isEmpty else { return }
        Task {
            let song = librarySongs[0]
            let keyword = "\(song.title) \(song.artistName)"
            do {
                let results = try await MusicService.shared.search(keyword: keyword, limit: 1)
                if let firstResult = results.first {
                    let tracks = try await MusicService.shared.getSongDetail(ids: [firstResult.id])
                    if let track = tracks.first {
                        await AudioPlayer.shared.play(track: track)
                    }
                }
            } catch {
                print("❌ 播放失败: \(error)")
            }
        }
    }
}


// MARK: - 歌曲行
struct AppleMusicSongRow: View {
    let song: Song
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                guard !isLoading else { return }
                playWithNetease()
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.pink)
                }
            }
            .disabled(isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isLoading else { return }
            playWithNetease()
        }
        .alert("播放失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func playWithNetease() {
        isLoading = true
        Task {
            do {
                let keyword = "\(song.title) \(song.artistName)"
                let results = try await MusicService.shared.search(keyword: keyword, limit: 5)
                if let firstResult = results.first {
                    let tracks = try await MusicService.shared.getSongDetail(ids: [firstResult.id])
                    if let track = tracks.first {
                        await AudioPlayer.shared.play(track: track)
                    } else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取歌曲详情"])
                    }
                } else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到匹配的歌曲"])
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - 专辑卡片（网格模式）
struct AppleMusicAlbumCard: View {
    let album: MusicKit.Album
    let accentColor: Color
    
    var body: some View {
        NavigationLink {
            AppleMusicAlbumDetailView(album: album)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let artwork = album.artwork {
                    ArtworkImage(artwork, width: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray5))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.title)
                                .foregroundColor(.secondary)
                        )
                }
                
                Text(album.title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(album.artistName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 专辑行（列表模式）
struct AppleMusicAlbumListRow: View {
    let album: MusicKit.Album
    let accentColor: Color
    
    var body: some View {
        NavigationLink {
            AppleMusicAlbumDetailView(album: album)
        } label: {
            HStack(spacing: 12) {
                if let artwork = album.artwork {
                    ArtworkImage(artwork, width: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(album.artistName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Apple Music 专辑详情页
struct AppleMusicAlbumDetailView: View {
    let album: MusicKit.Album
    @EnvironmentObject var themeManager: ThemeManager
    @State private var tracks: [MusicKit.Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private var isStrangerTheme: Bool { themeManager.themeStyle == .strangerThings }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .pink }
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("重试") { Task { await loadTracks() } }
                        .buttonStyle(.bordered)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        albumHeader
                        playButtons
                        tracksList
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTracks() }
    }
    
    private var albumHeader: some View {
        VStack(spacing: 12) {
            if let artwork = album.artwork {
                ArtworkImage(artwork, width: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            }
            
            Text(album.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            Text(album.artistName)
                .font(.subheadline)
                .foregroundColor(accentColor)
            
            HStack(spacing: 8) {
                if let genre = album.genreNames.first {
                    Text(genre)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let releaseDate = album.releaseDate {
                    Text("·").foregroundColor(.secondary)
                    Text({
                        let f = DateFormatter()
                        f.dateFormat = "yyyy"
                        return f.string(from: releaseDate)
                    }())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !tracks.isEmpty {
                    Text("·").foregroundColor(.secondary)
                    Text("\(tracks.count) 首歌曲")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 16)
        .padding(.horizontal)
    }
    
    private var playButtons: some View {
        HStack(spacing: 16) {
            Button {
                playAllTracks(shuffle: false)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("播放")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(accentColor)
                .clipShape(Capsule())
            }
            
            Button {
                playAllTracks(shuffle: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                    Text("随机播放")
                }
                .font(.subheadline.bold())
                .foregroundColor(accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(accentColor.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var tracksList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                AppleMusicTrackRow(track: track, trackNumber: index + 1)
                if index < tracks.count - 1 {
                    Divider().padding(.leading, 48)
                }
            }
        }
    }
    
    private func loadTracks() async {
        isLoading = true
        errorMessage = nil
        do {
            tracks = try await AppleMusicService.shared.getAlbumTracks(album: album)
        } catch {
            errorMessage = "加载失败，请重试"
        }
        isLoading = false
    }
    
    private func playAllTracks(shuffle: Bool) {
        guard !tracks.isEmpty else { return }
        let first = shuffle ? tracks.randomElement()! : tracks[0]
        Task {
            let keyword = "\(first.title) \(first.artistName)"
            do {
                let results = try await MusicService.shared.search(keyword: keyword, limit: 1)
                if let firstResult = results.first {
                    let details = try await MusicService.shared.getSongDetail(ids: [firstResult.id])
                    if let track = details.first {
                        await AudioPlayer.shared.play(track: track)
                    }
                }
            } catch {
                print("❌ 播放失败: \(error)")
            }
        }
    }
}

// MARK: - 艺人行
struct AppleMusicArtistRow: View {
    let artist: MusicKit.Artist
    let accentColor: Color
    @State private var isSearching = false
    @State private var neteaseArtistId: Int?
    @State private var showArtistDetail = false
    
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = artist.artwork {
                ArtworkImage(artwork, width: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.secondary)
                    )
            }
            
            Text(artist.name)
                .font(.subheadline)
                .lineLimit(1)
            
            Spacer()
            
            if isSearching {
                ProgressView()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSearching else { return }
            searchAndNavigate()
        }
        .background(
            NavigationLink(
                destination: ArtistDetailView(
                    artistId: neteaseArtistId ?? 0,
                    artistName: artist.name
                ),
                isActive: $showArtistDetail
            ) {
                EmptyView()
            }
            .hidden()
        )
    }
    
    private func searchAndNavigate() {
        isSearching = true
        Task {
            do {
                let results = try await MusicService.shared.searchArtists(keyword: artist.name, limit: 1)
                if let first = results.first {
                    neteaseArtistId = first.id
                    showArtistDetail = true
                }
            } catch {
                print("❌ 搜索艺人失败: \(error)")
            }
            isSearching = false
        }
    }
}

// MARK: - 播放列表行
struct AppleMusicPlaylistRow: View {
    let playlist: Playlist
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            if let artwork = playlist.artwork {
                ArtworkImage(artwork, width: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note.list")
                            .foregroundColor(.secondary)
                    )
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                if let description = playlist.shortDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - 专辑曲目行
struct AppleMusicTrackRow: View {
    let track: MusicKit.Track
    var trackNumber: Int? = nil
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        HStack(spacing: 12) {
            if let num = trackNumber {
                Text("\(num)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }
            
            if let artwork = track.artwork {
                ArtworkImage(artwork, width: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                guard !isLoading else { return }
                playTrack()
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.pink)
                }
            }
            .disabled(isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isLoading else { return }
            playTrack()
        }
        .alert("播放失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func playTrack() {
        isLoading = true
        Task {
            do {
                let keyword = "\(track.title) \(track.artistName)"
                let results = try await MusicService.shared.search(keyword: keyword, limit: 5)
                if let firstResult = results.first {
                    let tracks = try await MusicService.shared.getSongDetail(ids: [firstResult.id])
                    if let t = tracks.first {
                        await AudioPlayer.shared.play(track: t)
                    } else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取歌曲详情"])
                    }
                } else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到匹配的歌曲"])
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - 播放列表详情页
struct AppleMusicPlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var themeManager: ThemeManager
    @State private var tracks: [MusicKit.Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private var isStrangerTheme: Bool { themeManager.themeStyle == .strangerThings }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .pink }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("重试") {
                        Task { await loadTracks() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if tracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("播放列表为空")
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 播放列表头部
                        VStack(spacing: 12) {
                            if let artwork = playlist.artwork {
                                ArtworkImage(artwork, width: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            Text("\(tracks.count) 首歌曲")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 16)
                        
                        // 歌曲列表
                        ForEach(tracks, id: \.id) { track in
                            AppleMusicTrackRow(track: track)
                            Divider().padding(.leading, 64)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadTracks()
        }
    }
    
    private func loadTracks() async {
        isLoading = true
        errorMessage = nil
        do {
            tracks = try await AppleMusicService.shared.getPlaylistTracks(playlist: playlist)
        } catch {
            print("❌ 加载播放列表失败: \(error)")
            errorMessage = "加载失败，请重试"
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        AppleMusicView()
            .environmentObject(ThemeManager.shared)
    }
}
