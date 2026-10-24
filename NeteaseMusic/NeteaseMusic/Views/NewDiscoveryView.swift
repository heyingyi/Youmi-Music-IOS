import SwiftUI

// MARK: - 新发现页面
struct NewDiscoveryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var personalizedSongs: [PersonalizedSong] = [] // 快乐启蒙（推荐新音乐）
    @State private var newSongs: [Track] = [] // 最新歌曲（新歌速递）
    @State private var newAlbums: [NewAlbum] = [] // 新近发布（新碑上架）
    @State private var isLoading = true
    @State private var loadingError: String?
    
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }
    
    private let musicService = MusicService.shared
    
    var body: some View {
        ZStack {
            themedBackground
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 12) {
                                SkeletonBlock(width: 120, height: 22, cornerRadius: 4)
                                    .padding(.horizontal, 20)
                                HorizontalCardSkeletonView(count: 4, cardWidth: 160)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                SkeletonBlock(width: 100, height: 22, cornerRadius: 4)
                                    .padding(.horizontal, 20)
                                TrackListSkeletonView(count: 5)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                SkeletonBlock(width: 100, height: 22, cornerRadius: 4)
                                    .padding(.horizontal, 20)
                                HorizontalCardSkeletonView(count: 4, cardWidth: 160)
                            }
                        }
                    } else {
                        if !personalizedSongs.isEmpty {
                            PersonalizedSongsSection(songs: personalizedSongs)
                                .staggeredEntrance(index: 0)
                        }

                        if !newSongs.isEmpty {
                            NewSongsSection(songs: newSongs)
                                .staggeredEntrance(index: 1)
                        }

                        if !newAlbums.isEmpty {
                            NewAlbumsSection(albums: newAlbums)
                                .staggeredEntrance(index: 2)
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("新发现")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadMusicRecommendations()
        }
        .refreshable {
            await loadMusicRecommendations()
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
    
    // MARK: - 加载音乐推荐
    private func loadMusicRecommendations() async {
        isLoading = true
        loadingError = nil
        
        do {
            // 加载推荐新音乐（快乐启蒙）
            #if DEBUG
            print(" 开始加载推荐新音乐...")
            #endif
            let personalized = try await musicService.getPersonalizedNewSong(limit: 12)
            #if DEBUG
            print(" 推荐新音乐加载成功: \(personalized.count) 首")
            #endif

            // 加载最新歌曲（使用新歌速递 API）
            #if DEBUG
            print(" 开始加载最新歌曲...")
            #endif
            let songs = try await musicService.getTopSongs(type: 0)
            #if DEBUG
            print(" 最新歌曲加载成功: \(songs.count) 首")
            #endif

            // 加载新碑上架（新近发布）
            #if DEBUG
            print(" 开始加载新碑上架...")
            #endif
            let albums = try await musicService.getNewAlbums(area: "ALL", limit: 10)
            #if DEBUG
            print(" 新碑上架加载成功: \(albums.count) 张")
            #endif
            
            await MainActor.run {
                personalizedSongs = personalized
                newSongs = songs
                newAlbums = albums
                isLoading = false
            }
        } catch {
            #if DEBUG
            print(" 加载音乐推荐失败: \(error)")
            #endif
            await MainActor.run {
                loadingError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - 音乐推荐卡片
struct MusicRecommendCard: View {
    let imageUrl: URL?
    let title: String
    let subtitle: String?
    @Environment(\.colorScheme) var colorScheme
    
    private var cardWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.4, 180)
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
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .foregroundColor(.primary)
                .frame(width: cardWidth, alignment: .leading)
            
            // 副标题
            if let subtitle = subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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

// MARK: - 推荐新音乐区域（快乐启蒙）
struct PersonalizedSongsSection: View {
    let songs: [PersonalizedSong]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var navigateToList = false
    
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("快乐启蒙")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    navigateToList = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .background(
                NavigationLink(destination: PersonalizedSongsListView(songs: songs), isActive: $navigateToList) {
                    EmptyView()
                }
                .hidden()
            )
            
            if isWideLayout {
                // iPad: 网格布局
                let iPadColumns = [
                    GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 12)
                ]
                LazyVGrid(columns: iPadColumns, spacing: 16) {
                    ForEach(songs.prefix(12), id: \.id) { song in
                        PersonalizedSongCard(song: song, allSongs: songs)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(songs.prefix(12), id: \.id) { song in
                            PersonalizedSongCard(song: song, allSongs: songs)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: - 新碟上架区域（新近发布）
struct NewAlbumsSection: View {
    let albums: [NewAlbum]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var navigateToList = false
    
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("新近发布")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    navigateToList = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .background(
                NavigationLink(destination: NewAlbumsListView(albums: albums), isActive: $navigateToList) {
                    EmptyView()
                }
                .hidden()
            )
            
            if isWideLayout {
                // iPad: 网格布局
                let iPadColumns = [
                    GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 12)
                ]
                LazyVGrid(columns: iPadColumns, spacing: 16) {
                    ForEach(albums.prefix(10), id: \.id) { album in
                        NavigationLink(destination: AlbumDetailView(
                            albumId: album.id,
                            albumName: album.name
                        )) {
                            MusicRecommendCard(
                                imageUrl: album.picUrl.flatMap { URL(string: $0) },
                                title: album.name,
                                subtitle: album.artistName
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(albums.prefix(10), id: \.id) { album in
                            NavigationLink(destination: AlbumDetailView(
                                albumId: album.id,
                                albumName: album.name
                            )) {
                                MusicRecommendCard(
                                    imageUrl: album.picUrl.flatMap { URL(string: $0) },
                                    title: album.name,
                                    subtitle: album.artistName
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: - 最新歌曲区域（四行横向滚动）
struct NewSongsSection: View {
    let songs: [Track]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var navigateToList = false
    
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }
    
    // 每组4首歌曲
    private var songGroups: [[Track]] {
        let songsArray = Array(songs.prefix(40))
        return stride(from: 0, to: songsArray.count, by: 4).map { i in
            Array(songsArray[i..<min(i + 4, songsArray.count)])
        }
    }
    
    private var songsArray: [Track] {
        Array(songs.prefix(40))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最新歌曲")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    navigateToList = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .background(
                NavigationLink(destination: NewSongsListView(songs: songsArray), isActive: $navigateToList) {
                    EmptyView()
                }
                .hidden()
            )
            
            if isWideLayout {
                // iPad: 双列歌曲列表
                let iPadColumns = [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ]
                LazyVGrid(columns: iPadColumns, spacing: 0) {
                    ForEach(Array(songsArray.prefix(20).enumerated()), id: \.element.id) { index, track in
                        Button {
                            HapticFeedback.light()
                            AudioPlayer.shared.setPlaylist(songsArray, startAt: index)
                        } label: {
                            NewSongRow(track: track)
                        }
                    }
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(songGroups.enumerated()), id: \.offset) { groupIndex, group in
                            NewSongColumn(
                                tracks: group,
                                playlist: songsArray,
                                startIndex: groupIndex * 4
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: - 歌曲列（4首）
struct NewSongColumn: View {
    let tracks: [Track]
    let playlist: [Track]
    let startIndex: Int
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    HapticFeedback.light()
                    AudioPlayer.shared.setPlaylist(playlist, startAt: startIndex + index)
                } label: {
                    NewSongRow(track: track)
                }
            }
        }
        .frame(width: min(UIScreen.main.bounds.width * 0.75, 380))
    }
}

// MARK: - 最新歌曲行
struct NewSongRow: View {
    let track: Track
    @Environment(\.colorScheme) var colorScheme
    @State private var navigateToAlbum = false
    @State private var navigateToArtist = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 60, height: 60)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    coverPlaceholder
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                coverPlaceholder
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(track.artistName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 更多按钮
            Menu {
                Button {
                    AudioPlayer.shared.playNext(track: track)
                    HapticFeedback.light()
                } label: {
                    Label("播放下一首", systemImage: "text.insert")
                }
                
                Button {
                    AudioPlayer.shared.addToQueue(track: track)
                    HapticFeedback.light()
                } label: {
                    Label("添加到播放列表", systemImage: "text.append")
                }
                
                Divider()
                
                if let albumId = track.album?.id ?? track.al?.id {
                    Button {
                        navigateToAlbum = true
                    } label: {
                        Label("查看专辑", systemImage: "square.stack")
                    }
                }
                
                if let artistId = track.artists?.first?.id ?? track.ar?.first?.id {
                    Button {
                        navigateToArtist = true
                    } label: {
                        Label("查看艺人", systemImage: "person")
                    }
                }
                
                Divider()
                
                Button {
                    let shareText = "\(track.name) - \(track.artistName)"
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            Group {
                if let albumId = track.album?.id ?? track.al?.id {
                    NavigationLink(
                        destination: AlbumDetailView(albumId: albumId, albumName: track.albumName),
                        isActive: $navigateToAlbum
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
                if let artistId = track.artists?.first?.id ?? track.ar?.first?.id {
                    NavigationLink(
                        destination: ArtistDetailView(artistId: artistId, artistName: track.artistName),
                        isActive: $navigateToArtist
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
        )
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5))
            
            Image(systemName: "music.note")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - 快乐启蒙卡片（带菜单）
struct PersonalizedSongCard: View {
    let song: PersonalizedSong
    let allSongs: [PersonalizedSong]
    @State private var navigateToAlbum = false
    @State private var navigateToArtist = false
    
    var body: some View {
        Button {
            HapticFeedback.light()
            let tracks = allSongs.map { $0.toTrack() }
            if let index = allSongs.firstIndex(where: { $0.id == song.id }) {
                AudioPlayer.shared.setPlaylist(tracks, startAt: index)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    MusicRecommendCard(
                        imageUrl: song.picUrl.flatMap { URL(string: $0) },
                        title: song.name,
                        subtitle: song.artistName
                    )
                    
                    // 菜单按钮
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
                        
                        if let albumId = song.song?.album?.id {
                            Button {
                                navigateToAlbum = true
                            } label: {
                                Label("查看专辑", systemImage: "square.stack")
                            }
                        }
                        
                        if let artistId = song.song?.artists?.first?.id {
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
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.4))
                                    .frame(width: 26, height: 26)
                            )
                    }
                    .padding(8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            Group {
                if let albumId = song.song?.album?.id, let albumName = song.song?.album?.name {
                    NavigationLink(
                        destination: AlbumDetailView(albumId: albumId, albumName: albumName),
                        isActive: $navigateToAlbum
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
                if let artistId = song.song?.artists?.first?.id {
                    NavigationLink(
                        destination: ArtistDetailView(artistId: artistId, artistName: song.artistName),
                        isActive: $navigateToArtist
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
        )
    }
}

// MARK: - 快乐启蒙列表视图
struct PersonalizedSongsListView: View {
    let songs: [PersonalizedSong]
    
    var body: some View {
        List {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                Button {
                    let tracks = songs.map { $0.toTrack() }
                    AudioPlayer.shared.setPlaylist(tracks, startAt: index)
                } label: {
                    HStack(spacing: 12) {
                        if let picUrl = song.picUrl, let url = URL(string: picUrl) {
                            CachedAsyncImage(url: url, targetSize: CGSize(width: 50, height: 50)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color(.systemGray5))
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Text(song.artistName)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("快乐启蒙")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - 最新歌曲列表视图
struct NewSongsListView: View {
    let songs: [Track]
    
    var body: some View {
        List {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, track in
                Button {
                    AudioPlayer.shared.setPlaylist(songs, startAt: index)
                } label: {
                    HStack(spacing: 12) {
                        if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                            CachedAsyncImage(url: url, targetSize: CGSize(width: 50, height: 50)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color(.systemGray5))
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Text(track.artistName)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("最新歌曲")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - 新近发布列表视图
struct NewAlbumsListView: View {
    let albums: [NewAlbum]
    
    var body: some View {
        List {
            ForEach(albums, id: \.id) { album in
                NavigationLink(destination: AlbumDetailView(albumId: album.id, albumName: album.name)) {
                    HStack(spacing: 12) {
                        if let picUrl = album.picUrl, let url = URL(string: picUrl) {
                            CachedAsyncImage(url: url, targetSize: CGSize(width: 50, height: 50)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color(.systemGray5))
                            }
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Text(album.artistName)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("新近发布")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationView {
        NewDiscoveryView()
    }
}
