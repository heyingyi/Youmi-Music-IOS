import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    let playlistId: Int
    let playlistName: String
    let coverUrl: String?
    
    @State private var playlist: PlaylistDetail?
    @State private var isLoading = true
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    // 分页加载
    @State private var displayedTrackCount: Int = 50
    private let pageSize: Int = 50
    
    // 主题相关（使用 ThemeManager 集中管理的颜色）
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { themeManager.accentColor }
    private var backgroundColor: Color { themeManager.backgroundColor }
    
    // 导航状态提升到父视图
    @State private var selectedArtist: Artist?
    @State private var selectedAlbum: Album?
    @State private var showArtistDetail = false
    @State private var showAlbumDetail = false
    
    @StateObject private var downloadService = SongDownloadService.shared
    @StateObject private var localMusicService = LocalMusicService.shared
    
    private let musicService = MusicService.shared
    
    // 性能优化：缓存触觉反馈生成器
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    headerView
                    playlistContent
                }
            }
            .coordinateSpace(name: "playlistScroll")
            .background {
                ThemedBackground()
                    .environmentObject(themeManager)
            }
            .ignoresSafeArea(edges: .top)

            topBar
        }
        .navigationBarHidden(true)
        .task {
            await loadPlaylist()
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
    
    // MARK: - 顶部栏
    private var topBar: some View {
        VStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .padding(.top, 54)
    }
    
    // MARK: - 头部视图（Apple Music 风格）
    private var headerView: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("playlistScroll")).minY
            let baseHeight: CGFloat = 380
            // 下拉时增加高度，上滑时保持最小高度
            let height = minY > 0 ? baseHeight + minY : baseHeight
            
            ZStack(alignment: .bottom) {
                headerBackground
                    .frame(width: geo.size.width, height: height + (minY > 0 ? minY : 0))
                    .clipped()
                
                VStack(spacing: 10) {
                    Text(playlistName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    if let creator = playlist?.creator {
                        Text(creator.nickname)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    
                    if let count = playlist?.trackCount {
                        Text("\(count) 首歌曲")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    playButtons
                    
                    if let desc = playlist?.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(height: height)
            .offset(y: minY > 0 ? -minY : 0)  // 下拉时固定在顶部
        }
        .frame(height: 380)
    }
    
    private var headerBackground: some View {
        ZStack {
            if let url = coverUrl, let imageUrl = URL(string: url) {
                CachedAsyncImage(url: imageUrl, targetSize: CGSize(width: 500, height: 500)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color(.systemGray5))
                }
            } else {
                LinearGradient(
                    colors: [accentColor.opacity(0.8), accentColor.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // 底部渐变过渡（更轻的渐变，保持图片清晰）
            VStack {
                Spacer()
                LinearGradient(
                    colors: [
                        Color.clear,
                        backgroundColor.opacity(0.6),
                        backgroundColor
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }
        }
    }
    
    private var playButtons: some View {
        HStack(spacing: 12) {
            Button(action: playAll) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("播放")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(playGradient)
                .clipShape(Capsule())
            }
            
            Button(action: playShuffle) {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                    Text("随机播放")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
            }
        }
        .font(.system(size: 14))
    }
    
    private var playGradient: LinearGradient {
        if isStrangerTheme {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.2, green: 0.6, blue: 1.0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(colors: [.pink, .red], startPoint: .leading, endPoint: .trailing)
    }
    
    // MARK: - 歌曲列表内容
    private var playlistContent: some View {
        LazyVStack(spacing: 0) {
            if isLoading {
                TrackListSkeletonView(count: 10)
                    .padding(.top, 12)
            } else if let tracks = playlist?.tracks, !tracks.isEmpty {
                let currentTrackId = audioPlayer.currentTrack?.id
                let isPlaying = audioPlayer.isPlaying
                let visibleCount = min(displayedTrackCount, tracks.count)
                
                ForEach(0..<visibleCount, id: \.self) { index in
                    let track = tracks[index]
                    OptimizedTrackRow(
                        track: track,
                        index: index + 1,
                        isCurrentTrack: track.id == currentTrackId,
                        isPlaying: isPlaying
                    )
                    .staggeredEntrance(index: min(index, 15), baseDelay: 0.03)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Self.impactGenerator.impactOccurred()
                        audioPlayer.setPlaylist(tracks, startAt: index)
                    }
                    .contextMenu {
                        if localMusicService.localTracks.contains(where: { $0.sourceTrackId == track.id }) {
                            Label("已下载", systemImage: "checkmark.circle.fill")
                        } else {
                            let status = downloadService.getStatus(trackId: track.id)
                            switch status {
                            case .idle:
                                Button {
                                    downloadService.download(track: track)
                                } label: {
                                    Label("下载", systemImage: "arrow.down.circle")
                                }
                            case .waiting, .downloading:
                                Button {
                                    downloadService.cancel(trackId: track.id)
                                } label: {
                                    Label("取消下载", systemImage: "xmark.circle")
                                }
                            case .failed:
                                Button {
                                    downloadService.retry(track: track)
                                } label: {
                                    Label("重试下载", systemImage: "arrow.clockwise")
                                }
                            case .completed:
                                Label("已下载", systemImage: "checkmark.circle.fill")
                            }
                        }

                        Divider()

                        if let artist = track.ar?.first {
                            Button {
                                selectedArtist = artist
                                showArtistDetail = true
                            } label: {
                                Label("查看歌手: \(artist.name)", systemImage: "person")
                            }
                        }
                        if let album = track.al {
                            Button {
                                selectedAlbum = album
                                showAlbumDetail = true
                            } label: {
                                Label("查看专辑: \(album.name)", systemImage: "square.stack")
                            }
                        }
                    }

                    if index < visibleCount - 1 {
                        Divider()
                            .padding(.leading, 70)
                    }
                    
                    // 滚动到底部时加载更多
                    if index == visibleCount - 1 && visibleCount < tracks.count {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 16)
                            Spacer()
                        }
                        .onAppear {
                            displayedTrackCount = min(displayedTrackCount + pageSize, tracks.count)
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Text("暂无歌曲")
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.top, 40)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 120)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: -2)
        )
        .padding(.top, -24)
    }
    
    private func playAll() {
        if let tracks = playlist?.tracks, !tracks.isEmpty {
            audioPlayer.playMode = .order
            audioPlayer.setPlaylist(tracks, startAt: 0)
        }
    }
    
    private func playShuffle() {
        if let tracks = playlist?.tracks, !tracks.isEmpty {
            audioPlayer.playMode = .random
            audioPlayer.setPlaylist(tracks.shuffled(), startAt: 0)
        }
    }
    
    // MARK: - 加载歌单
    private func loadPlaylist() async {
        isLoading = true
        displayedTrackCount = pageSize  // 重置分页
        do {
            // 先获取歌单基本信息
            playlist = try await musicService.getPlaylistDetail(id: playlistId)
            
            // 如果 tracks 为空或数量不足，使用 track/all 接口获取完整歌曲列表
            if let trackCount = playlist?.trackCount,
               (playlist?.tracks?.isEmpty ?? true) || (playlist?.tracks?.count ?? 0) < trackCount {
                let allTracks = try await musicService.getPlaylistAllTracks(id: playlistId)
                if !allTracks.isEmpty {
                    // 更新 playlist 的 tracks
                    playlist = PlaylistDetail(
                        id: playlist?.id ?? playlistId,
                        name: playlist?.name ?? playlistName,
                        coverImgUrl: playlist?.coverImgUrl ?? coverUrl,
                        description: playlist?.description,
                        playCount: playlist?.playCount,
                        trackCount: playlist?.trackCount,
                        creator: playlist?.creator,
                        tracks: allTracks
                    )
                }
            }
        } catch {
            #if DEBUG
            print("Load playlist error: \(error)")
            #endif
        }
        isLoading = false
    }
}

// MARK: - 歌曲行（支持歌手/专辑导航）
struct TrackRow: View {
    let track: Track
    let index: Int
    let isCurrentTrack: Bool
    let isPlaying: Bool
    var onArtistTap: ((Artist) -> Void)? = nil
    var onAlbumTap: ((Album) -> Void)? = nil
    
    @StateObject private var downloadService = SongDownloadService.shared
    @StateObject private var localMusicService = LocalMusicService.shared
    
    private var isDownloaded: Bool {
        localMusicService.localTracks.contains { $0.sourceTrackId == track.id }
    }
    
    private var downloadStatus: DownloadStatus {
        downloadService.getStatus(trackId: track.id)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号或播放指示
            ZStack {
                if isCurrentTrack && isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.red)
                } else {
                    Text("\(index)")
                        .foregroundColor(isCurrentTrack ? .red : .gray)
                }
            }
            .frame(width: 30)
            
            // 封面
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 45, height: 45)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color(.systemGray5))
                }
                .frame(width: 45, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(track.name)
                        .font(.subheadline)
                        .foregroundColor(isCurrentTrack ? .red : .primary)
                        .lineLimit(1)
                    
                    // 已下载标识
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(track.artistName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    
                    Text("·")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(track.albumName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 下载进度/状态
            downloadIndicator
            
            // 更多菜单
            Menu {
                // 下载按钮
                if isDownloaded {
                    Label("已下载", systemImage: "checkmark.circle.fill")
                } else {
                    switch downloadStatus {
                    case .idle:
                        Button {
                            downloadService.download(track: track)
                        } label: {
                            Label("下载", systemImage: "arrow.down.circle")
                        }
                    case .waiting, .downloading:
                        Button {
                            downloadService.cancel(trackId: track.id)
                        } label: {
                            Label("取消下载", systemImage: "xmark.circle")
                        }
                    case .failed:
                        Button {
                            downloadService.retry(track: track)
                        } label: {
                            Label("重试下载", systemImage: "arrow.clockwise")
                        }
                    case .completed:
                        Label("已下载", systemImage: "checkmark.circle.fill")
                    }
                }
                
                Divider()
                
                if let artist = track.ar?.first {
                    Button {
                        onArtistTap?(artist)
                    } label: {
                        Label("查看歌手: \(artist.name)", systemImage: "person")
                    }
                }
                
                if let album = track.al {
                    Button {
                        onAlbumTap?(album)
                    } label: {
                        Label("查看专辑: \(album.name)", systemImage: "square.stack")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var downloadIndicator: some View {
        switch downloadStatus {
        case .downloading(let progress):
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
        case .waiting:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 18, height: 18)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.red)
        default:
            EmptyView()
        }
    }
}

// MARK: - 优化的歌曲行（性能优化版 - 使用Equatable避免不必要重绘）
struct OptimizedTrackRow: View, Equatable {
    let track: Track
    let index: Int
    let isCurrentTrack: Bool
    let isPlaying: Bool
    
    // Equatable实现：只比较影响视图的属性
    static func == (lhs: OptimizedTrackRow, rhs: OptimizedTrackRow) -> Bool {
        lhs.track.id == rhs.track.id &&
        lhs.index == rhs.index &&
        lhs.isCurrentTrack == rhs.isCurrentTrack &&
        lhs.isPlaying == rhs.isPlaying
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号或播放指示
            indexView
                .frame(width: 30)
            
            // 封面
            coverView
            
            // 歌曲信息
            infoView
            
            Spacer()
            
            // 更多按钮
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var indexView: some View {
        if isCurrentTrack && isPlaying {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundColor(.red)
        } else {
            Text("\(index)")
                .font(.system(size: 14))
                .foregroundColor(isCurrentTrack ? .red : .gray)
        }
    }
    
    @ViewBuilder
    private var coverView: some View {
        if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
            CachedAsyncImage(url: url, targetSize: CGSize(width: 45, height: 45)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color(.systemGray5))
            }
            .frame(width: 45, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(width: 45, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
    
    private var infoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name)
                .font(.subheadline)
                .foregroundColor(isCurrentTrack ? .red : .primary)
                .lineLimit(1)
            
            Text("\(track.artistName) · \(track.albumName)")
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
    }
}

#Preview {
    NavigationView {
        PlaylistDetailView(
            playlistId: 3778678,
            playlistName: "测试歌单",
            coverUrl: nil
        )
    }
}
