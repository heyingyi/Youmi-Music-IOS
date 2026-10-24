import SwiftUI

/// 雷达歌单视图
struct RadarPlaylistView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    private let musicService = MusicService.shared
    
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
        isStrangerTheme ? Color(red: 0.2, green: 0.6, blue: 1.0) : .blue
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
        .navigationTitle("雷达歌单")
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
            await loadRadarPlaylist()
        }
        .refreshable {
            await loadRadarPlaylist()
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
            // 雷达动画
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(accentColor.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                        .frame(width: CGFloat(60 + i * 30), height: CGFloat(60 + i * 30))
                }
                
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(accentColor)
            }
            
            Text("正在扫描你的音乐雷达...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 错误视图
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(secondaryTextColor)
            
            Text("需要登录才能使用雷达歌单")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(textColor)
            
            Text("请先登录网易云账号")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
            
            Button(action: {
                Task { await loadRadarPlaylist() }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - 空视图
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(secondaryTextColor)
            
            Text("雷达暂未捕获到歌曲")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(textColor)
            
            Text("多听听歌，让雷达更了解你")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
            
            Button(action: {
                Task { await loadRadarPlaylist() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("刷新")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(accentColor)
                .clipShape(Capsule())
            }
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
                    RadarTrackRow(
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
            // 雷达图标
            ZStack {
                // 雷达波纹
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [accentColor.opacity(0.4 - Double(i) * 0.1), accentColor.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .frame(width: CGFloat(50 + i * 20), height: CGFloat(50 + i * 20))
                }
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 100, height: 100)
            
            Text("根据你的听歌习惯智能推荐")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
            
            Text("\(tracks.count) 首歌曲")
                .font(.system(size: 13))
                .foregroundColor(secondaryTextColor.opacity(0.8))
        }
        .padding(.top, 20)
    }
    
    // MARK: - 加载雷达歌单
    private func loadRadarPlaylist() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let songs = try await musicService.getRadarPlaylist()
            
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

// MARK: - 雷达歌曲行
struct RadarTrackRow: View {
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
        isStrangerTheme ? Color(red: 0.2, green: 0.6, blue: 1.0) : .blue
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
        RadarPlaylistView()
            .environmentObject(ThemeManager.shared)
    }
}
