import SwiftUI

/// 心动模式视图
struct HeartbeatModeView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentSongId: Int?
    @State private var currentPlaylistId: Int?
    
    private let musicService = MusicService.shared
    private let storageService = LocalStorageService.shared
    
    // 主题颜色
    private var isStrangerTheme: Bool {
        themeManager.themeStyle == .strangerThings
    }
    
    private var textColor: Color {
        isStrangerTheme ? .white : .primary
    }
    
    private var secondaryTextColor: Color {
        isStrangerTheme ? .white.opacity(0.6) : .secondary
    }
    
    private var accentColor: Color {
        isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .pink
    }
    
    var body: some View {
        ZStack {
            // 背景
            themedBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if tracks.isEmpty {
                    emptyView
                } else {
                    trackListView
                }
            }
        }
        .navigationTitle("心动模式")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !tracks.isEmpty {
                    Button(action: playAll) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(accentColor)
                    }
                }
            }
        }
        .task {
            await loadHeartbeatSongs()
        }
    }
    
    // MARK: - 主题背景
    @ViewBuilder
    private var themedBackground: some View {
        if themeManager.showsCustomWallpaper {
            CustomWallpaperLayer()
        } else if isStrangerTheme {
            StrangerThingsBackground()
        } else {
            LiquidGlassBackground()
        }
    }
    
    // MARK: - 加载视图
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(accentColor)
            
            Text("正在生成心动歌单...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 错误视图
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: error == "暂无播放历史" ? "clock.arrow.circlepath" : "heart.slash")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(secondaryTextColor)
            
            Text(error == "暂无播放历史" ? "暂无播放历史" : "需要登录才能使用心动模式")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(textColor)
            
            Text(error == "暂无播放历史" ? "先听几首歌，让我了解你的口味" : "请先登录网易云账号")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
            
            if error != "暂无播放历史" {
                Button(action: {
                    Task { await loadHeartbeatSongs() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("重试")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(accentColor)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - 空视图
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(secondaryTextColor)
            
            Text("暂无心动歌曲")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(textColor)
            
            Text("先播放一些歌曲，让我了解你的口味")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 歌曲列表
    private var trackListView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // 头部信息
                headerView
                    .padding(.bottom, 20)
                
                // 歌曲列表
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HeartbeatTrackRow(
                        track: track,
                        index: index + 1,
                        isPlaying: audioPlayer.currentTrack?.id == track.id,
                        isStrangerTheme: isStrangerTheme
                    ) {
                        playTrack(track, at: index)
                    }
                }
            }
            .padding(.bottom, 120)
        }
    }
    
    // MARK: - 头部视图
    private var headerView: some View {
        VStack(spacing: 12) {
            // 心动图标
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "heart.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }
            .shadow(color: accentColor.opacity(0.4), radius: 15, x: 0, y: 8)
            
            Text("基于你喜欢的歌曲推荐")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
            
            Text("\(tracks.count) 首歌曲")
                .font(.system(size: 13))
                .foregroundColor(secondaryTextColor.opacity(0.8))
        }
        .padding(.top, 20)
    }
    
    // MARK: - 加载心动歌曲
    private func loadHeartbeatSongs() async {
        isLoading = true
        errorMessage = nil
        
        // 获取最近播放的歌曲
        let history = storageService.getHistory()
        
        // 如果有播放历史，使用第一首歌作为种子
        if let firstTrack = history.first {
            do {
                // 获取用户的"喜欢的音乐"歌单ID
                guard let playlistId = try await musicService.getUserLikedPlaylistId() else {
                    await MainActor.run {
                        errorMessage = "需要登录"
                        isLoading = false
                    }
                    return
                }
                
                let songs = try await musicService.getHeartbeatList(
                    songId: firstTrack.id,
                    playlistId: playlistId
                )
                
                // 如果返回空列表，说明需要登录
                if songs.isEmpty {
                    await MainActor.run {
                        errorMessage = "需要登录"
                        isLoading = false
                    }
                    return
                }
                
                await MainActor.run {
                    tracks = songs
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "需要登录"
                    isLoading = false
                }
            }
        } else {
            // 没有播放历史
            await MainActor.run {
                errorMessage = "暂无播放历史"
                isLoading = false
            }
        }
    }
    
    // MARK: - 获取用户歌单（已废弃，使用MusicService.getUserLikedPlaylistId）
    private func getUserPlaylists() async throws -> [RecommendPlaylist]? {
        return nil
    }
    
    // MARK: - 播放歌曲
    private func playTrack(_ track: Track, at index: Int) {
        HapticFeedback.light()
        Task {
            await audioPlayer.setPlaylist(tracks, startAt: index)
        }
    }
    
    // MARK: - 播放全部
    private func playAll() {
        HapticFeedback.medium()
        Task {
            await audioPlayer.setPlaylist(tracks, startAt: 0)
        }
    }
}

// MARK: - 心动歌曲行
struct HeartbeatTrackRow: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    let isStrangerTheme: Bool
    let action: () -> Void
    
    private var textColor: Color {
        isStrangerTheme ? .white : .primary
    }
    
    private var secondaryTextColor: Color {
        isStrangerTheme ? .white.opacity(0.6) : .secondary
    }
    
    private var accentColor: Color {
        isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .pink
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 序号
                Text("\(index)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isPlaying ? accentColor : secondaryTextColor)
                    .frame(width: 28)
                
                // 封面
                if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.gray)
                        )
                }
                
                // 歌曲信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isPlaying ? accentColor : textColor)
                        .lineLimit(1)
                    
                    Text(track.artistName)
                        .font(.system(size: 13))
                        .foregroundColor(secondaryTextColor)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // 播放指示器
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(accentColor)
                }
                
                // 时长
                Text(track.durationText)
                    .font(.system(size: 13))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isPlaying ? accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationView {
        HeartbeatModeView()
            .environmentObject(ThemeManager.shared)
    }
}
