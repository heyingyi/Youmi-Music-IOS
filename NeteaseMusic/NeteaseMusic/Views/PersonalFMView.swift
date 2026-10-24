import SwiftUI

/// 私人FM视图
struct PersonalFMView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @Environment(\.colorScheme) var colorScheme
    
    @StateObject private var fmManager = PersonalFMManager.shared
    
    private var isStrangerTheme: Bool {
        themeManager.themeStyle == .strangerThings
    }
    
    var body: some View {
        ZStack {
            themedBackground.ignoresSafeArea()
            
            if fmManager.isLoading {
                loadingView
            } else if let error = fmManager.errorMessage {
                errorView(error)
            } else if let track = fmManager.currentTrack {
                fmPlayerView(track: track)
            }
        }
        .navigationTitle("私人FM")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if fmManager.fmTracks.isEmpty {
                await fmManager.startFM()
            }
        }
    }
    
    // MARK: - FM播放器主视图
    private func fmPlayerView(track: Track) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                fmCoverView(track: track)
                    .padding(.top, 20)
                
                VStack(spacing: 8) {
                    Text(track.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text(track.artistName)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    
                    if !track.albumName.isEmpty && track.albumName != "未知专辑" {
                        Text(track.albumName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                
                fmControlButtons(track: track)
                    .padding(.top, 8)
                
                fmQueuePreview
                    .padding(.top, 16)
            }
            .padding(.bottom, 120)
        }
    }
    
    // MARK: - 封面
    private func fmCoverView(track: Track) -> some View {
        ZStack {
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    coverPlaceholder
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 280, height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
    }
    
    private var coverPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "radio")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: - 控制按钮
    private func fmControlButtons(track: Track) -> some View {
        HStack(spacing: 40) {
            Button {
                Task { await fmManager.trashCurrent() }
            } label: {
                Image(systemName: "hand.thumbsdown")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)))
            }
            
            Button {
                if audioPlayer.currentTrack?.id == track.id {
                    audioPlayer.togglePlayPause()
                } else {
                    Task { await audioPlayer.play(track: track) }
                }
            } label: {
                Image(systemName: audioPlayer.currentTrack?.id == track.id && audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 68, height: 68)
                    .background(
                        Circle().fill(
                            LinearGradient(colors: isStrangerTheme ? [.red, .orange] : [.pink, .purple],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )
                    .shadow(color: .pink.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            
            Button {
                Task { await fmManager.playNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)))
            }
        }
    }
    
    // MARK: - 即将播放
    private var fmQueuePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("即将播放")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if fmManager.isLoadingMore {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                let upcoming = fmManager.upcomingTracks
                if upcoming.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("加载中...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    ForEach(Array(upcoming.prefix(5).enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 12) {
                            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5))
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(track.artistName)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        
                        if index < min(4, upcoming.count - 1) {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 背景
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
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("正在为你调频...")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            Text("FM信号中断")
                .font(.system(size: 18, weight: .semibold))
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("重新连接") {
                Task { await fmManager.startFM() }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Capsule().fill(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)))
        }
        .padding(40)
    }
}

// MARK: - 私人FM管理器（单例，持续管理FM队列）
class PersonalFMManager: ObservableObject {
    static let shared = PersonalFMManager()
    
    @Published var fmTracks: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    
    private let musicService = MusicService.shared
    
    var currentTrack: Track? {
        guard currentIndex >= 0, currentIndex < fmTracks.count else { return nil }
        return fmTracks[currentIndex]
    }
    
    var upcomingTracks: [Track] {
        guard currentIndex + 1 < fmTracks.count else { return [] }
        return Array(fmTracks[(currentIndex + 1)...])
    }
    
    private var remainingCount: Int {
        max(0, fmTracks.count - currentIndex - 1)
    }
    
    private init() {}
    
    /// 启动FM
    @MainActor
    func startFM() async {
        isLoading = true
        errorMessage = nil
        fmTracks = []
        currentIndex = 0
        
        do {
            let batch = try await musicService.getPersonalFM()
            fmTracks.append(contentsOf: batch)
            isLoading = false
            
            if let first = fmTracks.first {
                await AudioPlayer.shared.play(track: first)
            }
            
            // 后台预加载更多
            await prefetchIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    /// 下一首
    @MainActor
    func playNext() async {
        currentIndex += 1
        
        // 如果已经到队列末尾，先拉新的再播放
        if currentIndex >= fmTracks.count {
            do {
                let more = try await musicService.getPersonalFM()
                appendUnique(more)
            } catch {
                // 拉取失败，回退index
                currentIndex = max(0, currentIndex - 1)
                return
            }
        }
        
        if let track = currentTrack {
            await AudioPlayer.shared.play(track: track)
        }
        
        await prefetchIfNeeded()
    }
    
    /// 不喜欢当前歌曲，丢垃圾桶并切下一首
    @MainActor
    func trashCurrent() async {
        guard let track = currentTrack else { return }
        
        // 异步丢垃圾桶，不阻塞切歌
        let trashId = track.id
        Task {
            try? await musicService.fmTrash(id: trashId)
        }
        
        await playNext()
    }
    
    /// 预加载：剩余不足2首时拉新的
    @MainActor
    private func prefetchIfNeeded() async {
        guard remainingCount < 2, !isLoadingMore else { return }
        
        isLoadingMore = true
        do {
            let more = try await musicService.getPersonalFM()
            appendUnique(more)
        } catch {
            #if DEBUG
            print("FM预加载失败: \(error)")
            #endif
        }
        isLoadingMore = false
    }
    
    /// 去重追加
    private func appendUnique(_ tracks: [Track]) {
        let existingIds = Set(fmTracks.map { $0.id })
        let newTracks = tracks.filter { !existingIds.contains($0.id) }
        if newTracks.isEmpty && !tracks.isEmpty {
            // API返回的全是重复的，直接加进去（可能是API就这样）
            fmTracks.append(contentsOf: tracks)
        } else {
            fmTracks.append(contentsOf: newTracks)
        }
    }
}

#Preview {
    NavigationView {
        PersonalFMView()
    }
}
