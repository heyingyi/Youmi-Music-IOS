import SwiftUI
import AVKit
import AVFoundation
import WebKit
import MediaPlayer
import Combine

// MARK: - 系统音量观察器
class VolumeObserver: ObservableObject {
    @Published var volume: Float = AVAudioSession.sharedInstance().outputVolume

    /// 是否正在拖动（拖动时暂停 KVO 更新，避免循环更新导致"蹦迪"）
    var isDragging: Bool = false

    private var audioSession = AVAudioSession.sharedInstance()
    private var cancellable: AnyCancellable?

    init() {
        // 激活音频会话以便监听音量
        try? audioSession.setActive(true)

        // 使用 KVO 监听音量变化
        cancellable = audioSession.publisher(for: \.outputVolume)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newVolume in
                guard let self = self, !self.isDragging else { return }
                self.volume = newVolume
            }
    }

    deinit {
        cancellable?.cancel()
    }
}

struct SelectedArtist: Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
}

// MARK: - 系统音量控制器（需要 MPVolumeView 在视图层级中）
final class SystemVolumeController: ObservableObject {
    private weak var volumeView: MPVolumeView?
    private weak var slider: UISlider?

    func attach(_ view: MPVolumeView) {
        volumeView = view
        if slider == nil {
            slider = view.subviews.compactMap { $0 as? UISlider }.first
        }
    }

    func setVolume(_ volume: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.slider == nil, let view = self.volumeView {
                self.attach(view)
            }
            self.slider?.value = volume
            self.slider?.sendActions(for: .valueChanged)
        }
    }
}

struct HiddenSystemVolumeView: UIViewRepresentable {
    let controller: SystemVolumeController

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        view.isUserInteractionEnabled = false
        view.alpha = 0.01
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        controller.attach(uiView)
    }
}

struct PlayerView: View {
    // 支持两种关闭方式：外部传入的回调 或 Environment dismiss
    var dismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var environmentDismiss
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @State private var lyrics: [LyricLineWithTranslation] = []
    @StateObject private var localMusicService = LocalMusicService.shared
    @State private var currentLyricIndex: Int = 0
    @State private var showLyrics = false
    @State private var isLoadingLyrics = false
    @State private var showTranslation = true  // 是否显示翻译
    @State private var hasTranslation = false  // 是否有翻译歌词

    // 逐字歌词
    @State private var yrcLines: [YrcLine] = []
    @State private var hasYrcLyric = false     // 是否有逐字歌词
    @State private var currentTime: Double = 0 // 当前播放时间（用于驱动逐字动画）
    @State private var progressTime: Double = 0 // 进度条时间（高频更新）

    // 歌词滚动防抖优化
    @State private var lastLyricUpdateTime: Double = 0
    @State private var lastLyricIndex: Int = -1  // 记录上次歌词索引，避免重复设置

    // 动画状态
    @State private var isPlayButtonPressed = false
    @State private var isDraggingProgress = false
    @State private var dragProgress: Double = 0
    @State private var imageOffset: CGSize = .zero
    @State private var backgroundScale: CGFloat = 1.1

    // UI状态
    @State private var showShareSheet = false
    @State private var showPlaylistSheet = false
    @State private var showCommentSheet = false  // 评论弹窗
    @State private var showLikeSheet = false     // 喜欢选项弹窗
    @StateObject private var volumeObserver = VolumeObserver()
    @StateObject private var systemVolumeController = SystemVolumeController()
    @State private var selectedArtist: SelectedArtist?

    // 动态封面 - 使用 @State 触发视图更新
    @State private var lastLoadedTrackId: Int? = nil
    @State private var dynamicCoverURL: URL? = nil  // 改为 @State，触发视图更新

    private let musicService = MusicService.shared
    
    // 主题颜色
    private var isStrangerTheme: Bool {
        themeManager.themeStyle == .strangerThings
    }
    
    private var accentColor: Color {
        isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .white
    }
    
    // iPad 检测
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // 当前歌词文本
    private var currentLyricText: String {
        guard !lyrics.isEmpty, currentLyricIndex < lyrics.count else {
            return isLoadingLyrics ? "歌词加载中..." : ""
        }
        return lyrics[currentLyricIndex].text
    }
    
    // 当前歌词翻译
    private var currentLyricTranslation: String? {
        guard showTranslation, !lyrics.isEmpty, currentLyricIndex < lyrics.count else {
            return nil
        }
        return lyrics[currentLyricIndex].translation
    }
    
    // 当前逐字歌词行
    private var currentYrcLine: YrcLine? {
        guard !yrcLines.isEmpty, currentLyricIndex < yrcLines.count else {
            return nil
        }
        return yrcLines[currentLyricIndex]
    }
    
    // 统一的关闭方法
    private func dismissPlayer() {
        if let dismiss = dismiss {
            dismiss()
        } else {
            environmentDismiss()
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    // 层级 1: 全屏封面（从顶部开始铺满）
                    fullScreenArtwork(size: geo.size)
                        .blur(radius: showLyrics ? 50 : 0)
                        .scaleEffect(showLyrics ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.4), value: showLyrics)

                    // 歌词模式下的暗色蒙版
                    if showLyrics {
                        Color.black.opacity(0.55)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }

                    // 层级 2: 底部渐变遮罩（只在下半部分）
                    VStack(spacing: 0) {
                        Spacer()
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.4), location: 0.2),
                                .init(color: .black.opacity(0.85), location: 0.6),
                                .init(color: .black.opacity(0.95), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geo.size.height * 0.55)
                    }
                    .ignoresSafeArea()

                    // 层级 3: 内容
                    if isIPad && showLyrics {
                        // iPad 全屏歌词模式（类似 Apple Music）
                        iPadFullScreenLyricsView(size: geo.size)
                    } else if showLyrics {
                        // iPhone Apple Music 风格全屏歌词
                        VStack(spacing: 0) {
                            // 顶部：迷你封面 + 歌曲信息（Apple Music 风格）
                            lyricsTopBar
                            
                            // 歌词占满中间区域
                            lyricsView
                                .layoutPriority(1)
                            
                            // 底部：紧凑控制区
                            lyricsBottomControls
                        }
                    } else {
                        // iPhone 非歌词模式 / iPad 非歌词模式
                        VStack(spacing: 0) {
                            topBar
                            Spacer()
                            bottomControlsWithBlur(size: geo.size)
                        }
                    }

                    // 层级 4: DJ 过渡提示（顶部悬浮）
                    DJTransitionOverlay()

                    if let sourceName = audioPlayer.thirdPartySourceName, !sourceName.isEmpty {
                        VStack {
                            Text("已使用第三方音源：\(sourceName)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.72))
                                )
                                .padding(.top, 58)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }

                    HiddenSystemVolumeView(controller: systemVolumeController)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .fullScreenCover(item: $selectedArtist) { artist in
            NavigationStack {
                ArtistDetailView(artistId: artist.id, artistName: artist.name)
            }
        }
        .onAppear {
            loadLyrics()
            // 重置以允许重新加载（PlayerView 是新实例，@State 已重置）
            loadDynamicCover()
            startBackgroundAnimation()
            audioPlayer.onTimeUpdate = { [self] time in
                if abs(time - progressTime) >= 0.2 {
                    progressTime = time
                }
                if showLyrics && hasYrcLyric {
                    // 高频更新歌词时间，确保逐字动画流畅
                    currentTime = time
                }
                updateCurrentLyricIndex(time: time)
            }
            // 歌词显示时提高时间更新频率到 ~30fps，确保逐字动画丝滑
            audioPlayer.lyricsTimeUpdateInterval = 0.033
        }
        .onChangeCompat(of: audioPlayer.currentTrack?.id) { _, _ in
            lastLoadedTrackId = nil  // 切歌时重置
            loadLyrics()
            loadDynamicCover()
        }
        .onReceive(audioPlayer.$currentTrack.dropFirst()) { newTrack in
            // 双重保险：确保切歌时歌词和封面刷新
            guard newTrack != nil else { return }
            // 立即重置歌词时间，避免旧歌词残留
            currentTime = 0
            progressTime = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if lastLoadedTrackId != newTrack?.id {
                    lastLoadedTrackId = nil
                    loadLyrics()
                    loadDynamicCover()
                }
            }
        }
        .onDisappear {
            audioPlayer.onTimeUpdate = nil
            audioPlayer.lyricsTimeUpdateInterval = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // 从后台返回时恢复动态封面播放
            resumeDynamicCoverPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // App 激活时也尝试恢复播放
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                resumeDynamicCoverPlayback()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 || value.translation.width > 0 {
                        imageOffset = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 || value.translation.width > 80 {
                        dismissPlayer()
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            imageOffset = .zero
                        }
                    }
                }
        )
        .sheet(isPresented: $showPlaylistSheet) {
            PlaylistSheetView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            if let track = audioPlayer.currentTrack {
                ShareSheetView(track: track)
            }
        }
        .sheet(isPresented: $showCommentSheet) {
            if let track = audioPlayer.currentTrack {
                CommentView(trackId: track.id, trackName: track.name)
            }
        }
        .sheet(isPresented: $showLikeSheet) {
            if let track = audioPlayer.currentTrack {
                LikeOptionsSheet(track: track)
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    // MARK: - 全屏封面（上部清晰 + 底部模糊无缝衔接）
    private func fullScreenArtwork(size: CGSize) -> some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let screenHeight = geo.size.height
            let isLocal = audioPlayer.isPlayingLocal
            let localTrack = audioPlayer.currentLocalTrack

            ZStack(alignment: .top) {
                // 背景色
                Color.black

                // 本地歌曲封面
                if isLocal, let track = localTrack {
                    if let artworkImage = track.artworkImage {
                        localArtworkWithBlur(image: artworkImage, screenWidth: screenWidth, screenHeight: screenHeight)
                    } else {
                        gradientBackground
                    }
                }
                // 网络歌曲封面
                else if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                   let url = URL(string: coverUrl) {
                    staticCoverWithBlur(url: url, screenWidth: screenWidth, screenHeight: screenHeight)
                        .id(coverUrl)  // 强制切歌时刷新封面
                } else {
                    gradientBackground
                }

                // 动态封面叠加在静态封面上（无缝过渡）- 仅网络歌曲
                if !isLocal, let coverUrl = dynamicCoverURL {
                    dynamicCoverWithBlur(url: coverUrl, screenWidth: screenWidth, screenHeight: screenHeight)
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - 本地歌曲封面（使用 UIImage）
    private func localArtworkWithBlur(image: UIImage, screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        let imageHeight = screenHeight * 0.70
        
        return ZStack(alignment: .top) {
            // 层级 1: 全屏模糊背景
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: screenWidth, height: screenHeight)
                .blur(radius: 50)
                .clipped()
            
            // 层级 2: 暗色渐变蒙版
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.5),
                    .init(color: .black.opacity(0.7), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // 层级 3: 清晰封面
            VStack(spacing: 0) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: screenWidth, height: imageHeight)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(height: screenHeight)
            .mask(
                VStack(spacing: 0) {
                    // 封面区域完全不透明
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: imageHeight * 0.95)
                    // 底部渐变透明
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: imageHeight * 0.05)
                    Spacer(minLength: 0)
                }
            )
        }
    }
    
    // MARK: - 静态封面（清晰+模糊无缝衔接）
    private func staticCoverWithBlur(url: URL, screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        // 覆盖约 70% 屏幕高度（匹配 Apple Music）
        let imageHeight = screenHeight * 0.70

        return CachedAsyncImage(url: url, targetSize: CGSize(width: screenWidth, height: screenHeight)) { image in
            ZStack(alignment: .top) {
                // 层级 1: 全屏模糊背景
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: screenWidth, height: screenHeight)
                    .blur(radius: 50)
                    .clipped()

                // 层级 2: 暗色渐变蒙版
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.3), location: 0.5),
                        .init(color: .black.opacity(0.7), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 层级 3: 清晰封面
                VStack(spacing: 0) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: screenWidth, height: imageHeight)
                        .clipped()
                    Spacer(minLength: 0)
                }
                .frame(height: screenHeight)
                .mask(
                    VStack(spacing: 0) {
                        // 封面区域完全不透明
                        Rectangle()
                            .fill(Color.white)
                            .frame(height: imageHeight * 0.95)
                        // 底部渐变透明
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: imageHeight * 0.05)
                        Spacer(minLength: 0)
                    }
                )
            }
        } placeholder: {
            // 加载中显示渐变背景
            gradientBackground
        }
    }
    
    // MARK: - 动态封面（性能优化：模糊背景用静态图片，只保留一个WebView）
    private func dynamicCoverWithBlur(url: URL, screenWidth: CGFloat, screenHeight: CGFloat) -> some View {
        // 覆盖约 70% 屏幕高度（匹配 Apple Music）
        let videoHeight = screenHeight * 0.70
        
        return ZStack(alignment: .top) {
            // 性能优化：模糊背景使用静态封面图片，避免创建第二个WebView
            if let coverUrl = audioPlayer.currentTrack?.coverUrl,
               let staticUrl = URL(string: coverUrl) {
                AsyncImage(url: staticUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: screenWidth, height: screenHeight)
                            .blur(radius: 50)
                            .scaleEffect(1.2)
                            .clipped()
                    default:
                        Color.black
                    }
                }
            } else {
                Color.black
            }
            
            // 层级 2: 暗色渐变蒙版
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.5),
                    .init(color: .black.opacity(0.7), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // 层级 3: 清晰动态封面（唯一的WebView）
            VStack(spacing: 0) {
                DynamicCoverVideoView(url: url)
                    .id(url)  // 切歌时强制重新创建 WebView
                    .frame(width: screenWidth, height: videoHeight)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(height: screenHeight)
            .mask(
                VStack(spacing: 0) {
                    // 封面区域完全不透明
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: videoHeight * 0.95)
                    // 底部渐变透明
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: videoHeight * 0.05)
                    Spacer(minLength: 0)
                }
            )
        }
    }
    
    // MARK: - 底部控制区（带模糊背景）
    private func bottomControlsWithBlur(size: CGSize) -> some View {
        // iPad 适配：限制最大宽度，居中显示
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let maxWidth: CGFloat = isIPad ? 500 : .infinity
        let horizontalPadding: CGFloat = isIPad ? 60 : 16

        return VStack(spacing: isIPad ? 20 : 16) {
            // 当前歌词预览（非歌词模式时显示）
            if !showLyrics {
                if hasYrcLyric, let currentLine = currentYrcLine {
                    // 逐字变色预览 - 使用 audioPlayer.currentTime（低频更新）
                    KaraokePreviewView(line: currentLine, currentTime: audioPlayer.currentTime)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: currentLyricIndex)
                } else if !currentLyricText.isEmpty {
                    // 普通歌词预览
                    Text(currentLyricText)
                        .font(.system(size: isIPad ? 17 : 15))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .padding(.horizontal, horizontalPadding)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: currentLyricIndex)
                }
            }

            // 歌曲信息 + 进度条 紧密排列
            VStack(spacing: 12) {
                // 歌曲信息
                PlayerSongInfoView(
                    track: audioPlayer.currentTrack,
                    onShowLike: { showLikeSheet = true },
                    onShowShare: { showShareSheet = true },
                    onArtistTap: { artist in
                        selectedArtist = SelectedArtist(id: artist.id, name: artist.name)
                    }
                )
                .padding(.horizontal, horizontalPadding)

                // 进度条
                PlayerProgressView(
                    currentTime: progressTime,
                    duration: audioPlayer.duration,
                    isDragging: $isDraggingProgress,
                    dragProgress: $dragProgress,
                    onSeek: { time in audioPlayer.seek(to: time) }
                )
                .padding(.horizontal, horizontalPadding)
            }

            // 控制按钮
            PlayerControlsView(
                isPlaying: audioPlayer.isPlaying,
                isLoading: audioPlayer.isLoading,
                isIPad: isIPad,
                isPlayButtonPressed: $isPlayButtonPressed,
                onPrevious: { audioPlayer.playPrevious() },
                onPlayPause: { audioPlayer.togglePlayPause() },
                onNext: { audioPlayer.playNext() }
            )

            // 音量条
            PlayerVolumeView(
                volumeObserver: volumeObserver,
                systemVolumeController: systemVolumeController
            )
                .padding(.horizontal, horizontalPadding)

            // 底部操作栏
            PlayerBottomBarView(
                showLyrics: showLyrics,
                playModeIcon: audioPlayer.playMode.icon,
                sourceConfig: MusicSourceConfig.shared,
                audioPlayer: audioPlayer,
                onToggleLyrics: {
                    withAnimation(.spring(response: 0.4)) {
                        showLyrics.toggle()
                    }
                },
                onShowComments: { showCommentSheet = true },
                onShowPlaylist: { showPlaylistSheet = true },
                onTogglePlayMode: { audioPlayer.togglePlayMode() }
            )
            // 注意：PlayerBottomBarView 内部已有 padding，这里不再重复添加
        }
        .fixedSize(horizontal: false, vertical: true)  // 防止垂直方向被拉伸
        .frame(maxWidth: min(maxWidth, size.width))  // 限制宽度不超出屏幕
        .frame(maxWidth: .infinity, alignment: .center)  // 居中显示
        .padding(.bottom, isIPad ? 30 : 50)
        .offset(y: imageOffset.height * 0.2)
    }
    
    // MARK: - iPad 全屏歌词模式
    private func iPadFullScreenLyricsView(size: CGSize) -> some View {
        let isLandscape = size.width > size.height

        return Group {
            if isLandscape {
                // 横屏：左边封面+控件，右边歌词（Apple Music 风格）
                HStack(spacing: 0) {
                    // 左侧：封面 + 控件
                    VStack(spacing: 20) {
                        Spacer()

                        // 封面
                        if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                           let url = URL(string: coverUrl) {
                            CachedAsyncImage(url: url, targetSize: CGSize(width: 280, height: 280)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 280, height: 280)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 280, height: 280)
                            }
                        }

                        // 歌曲信息
                        if let track = audioPlayer.currentTrack {
                            VStack(spacing: 4) {
                                Text(track.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(track.artistName)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }

                        // 进度条
                        PlayerProgressView(
                            currentTime: progressTime,
                            duration: audioPlayer.duration,
                            isDragging: $isDraggingProgress,
                            dragProgress: $dragProgress,
                            onSeek: { time in audioPlayer.seek(to: time) }
                        )
                        .padding(.horizontal, 20)

                        // 播放控制
                        HStack(spacing: 44) {
                            Button(action: { audioPlayer.playPrevious() }) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                            Button(action: { audioPlayer.togglePlayPause() }) {
                                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.white)
                            }
                            Button(action: { audioPlayer.playNext() }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                        }

                        // 音量条
                        PlayerVolumeView(
                            volumeObserver: volumeObserver,
                            systemVolumeController: systemVolumeController
                        )
                        .padding(.horizontal, 20)

                        // 底部操作栏
                        HStack(spacing: 20) {
                            Button(action: {
                                withAnimation(.spring(response: 0.4)) { showLyrics.toggle() }
                            }) {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            Button(action: { showCommentSheet = true }) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Spacer()
                            Button(action: { audioPlayer.togglePlayMode() }) {
                                Image(systemName: audioPlayer.playMode.icon)
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Button(action: { showPlaylistSheet = true }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 20)

                        Spacer()
                    }
                    .frame(width: size.width * 0.38)
                    .padding(.horizontal, 30)

                    // 右侧：全屏歌词
                    lyricsView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .topLeading) {
                    Button(action: { dismissPlayer() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    .padding(.leading, 16)
                    .padding(.top, 20)
                }
            } else {
                // 竖屏：歌词全屏 + 底部迷你控件浮动
                ZStack(alignment: .bottom) {
                    lyricsView

                    VStack(spacing: 14) {
                        PlayerProgressView(
                            currentTime: progressTime,
                            duration: audioPlayer.duration,
                            isDragging: $isDraggingProgress,
                            dragProgress: $dragProgress,
                            onSeek: { time in audioPlayer.seek(to: time) }
                        )
                        HStack(spacing: 40) {
                            Button(action: { audioPlayer.playPrevious() }) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                            Button(action: { audioPlayer.togglePlayPause() }) {
                                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                            }
                            Button(action: { audioPlayer.playNext() }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                        }
                        HStack {
                            if let track = audioPlayer.currentTrack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(track.artistName)
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.4)) { showLyrics.toggle() }
                            }) {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            .padding(.trailing, 16)
                            Button(action: { showPlaylistSheet = true }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 30)
                    .background(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.6), location: 0.3),
                                .init(color: .black.opacity(0.8), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false),
                        alignment: .bottom
                    )

                    VStack {
                        HStack {
                            Button(action: { dismissPlayer() }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: $showPlaylistSheet) {
            PlaylistSheetView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCommentSheet) {
            if let track = audioPlayer.currentTrack {
                CommentView(trackId: track.id, trackName: track.name)
            }
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: [Color.indigo, Color.purple, Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - 背景动画
    private func startBackgroundAnimation() {
        withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
            backgroundScale = 1.2
        }
    }
    
    // MARK: - 顶部栏
    private var topBar: some View {
        HStack {
            Button(action: { dismissPlayer() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
        .offset(y: imageOffset.height * 0.3)
    }
    
    // MARK: - 歌词模式顶部栏（Apple Music 风格）
    private var lyricsTopBar: some View {
        VStack(spacing: 12) {
            // 拖拽指示器 — 点击回到播放器界面
            Button(action: {
                withAnimation(.spring(response: 0.4)) {
                    showLyrics = false
                }
            }) {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 36, height: 5)
            }
            .padding(.top, 10)
            
            HStack(spacing: 12) {
                // 封面（Apple Music ~56pt）
                if let coverUrl = audioPlayer.currentTrack?.coverUrl,
                   let url = URL(string: coverUrl) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 120, height: 120)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.08))
                            .frame(width: 56, height: 56)
                    }
                    .id(audioPlayer.currentTrack?.id)
                }
                
                // 歌曲信息
                if let track = audioPlayer.currentTrack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 收藏（无背景，纯图标）
                Button(action: { showLikeSheet = true }) {
                    Image(systemName: "star")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                
                // 更多
                Button(action: { showShareSheet = true }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 44)
    }
    
    // MARK: - 歌词模式底部控制区（Apple Music 风格）
    private var lyricsBottomControls: some View {
        VStack(spacing: 0) {
            // 翻译 + 工具按钮行（Apple Music 歌词区域底部，左右分布）
            HStack {
                if hasTranslation {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            showTranslation.toggle()
                        }
                    }) {
                        Image(systemName: "character.bubble")
                            .font(.system(size: 16))
                            .foregroundColor(showTranslation ? .white : .white.opacity(0.45))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(showTranslation ? 0.18 : 0.08)))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            // 进度条（Apple Music 细线风格）
            PlayerProgressView(
                currentTime: progressTime,
                duration: audioPlayer.duration,
                isDragging: $isDraggingProgress,
                dragProgress: $dragProgress,
                onSeek: { time in audioPlayer.seek(to: time) }
            )
            .padding(.horizontal, 20)
            
            // 播放控制（Apple Music 大按钮）
            HStack(spacing: 56) {
                Button(action: { audioPlayer.playPrevious() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
                Button(action: { audioPlayer.togglePlayPause() }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.white)
                }
                Button(action: { audioPlayer.playNext() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
            
            // 音量条
            PlayerVolumeView(
                volumeObserver: volumeObserver,
                systemVolumeController: systemVolumeController
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            
            // 底部操作栏（Apple Music：歌词气泡/AirPlay/播放列表）
            HStack {
                Button(action: { showCommentSheet = true }) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.55))
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.4)) {
                        showLyrics.toggle()
                    }
                }) {
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: { showPlaylistSheet = true }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 48)
        }
        .padding(.bottom, 30)
    }
    
    // MARK: - 歌词视图
    @ViewBuilder
    private var lyricsView: some View {
        if hasYrcLyric {
            // 逐字变色歌词视图
            KaraokeLyricsView(
                lines: yrcLines,
                currentTime: currentTime,
                showTranslation: showTranslation,
                hasTranslation: hasTranslation,
                onToggleTranslation: {
                    withAnimation(.spring(response: 0.3)) {
                        showTranslation.toggle()
                    }
                },
                onSeek: { time in
                    audioPlayer.seek(to: time)
                }
            )
            .offset(y: imageOffset.height * 0.3)
        } else {
            // 普通歌词视图
            normalLyricsView
        }
    }
    
    // MARK: - 普通歌词视图
    private var normalLyricsView: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // 翻译开关（只在有翻译时显示）
                if hasTranslation {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showTranslation.toggle()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .font(.system(size: 12))
                                Text(showTranslation ? "翻译" : "原文")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(showTranslation ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(showTranslation ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                            )
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 60)
                    }
                }
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                            let isCurrent = index == currentLyricIndex
                            let distance = abs(index - currentLyricIndex)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                // 原文歌词（Apple Music 风格：左对齐、大字、粗体）
                                Text(line.text)
                                    .font(.system(size: isCurrent ? 28 : 22, weight: .bold))
                                    .foregroundColor(isCurrent ? .white : .white.opacity(distance <= 1 ? 0.4 : 0.2))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .shadow(color: isCurrent ? .black.opacity(0.3) : .clear, radius: 8, x: 0, y: 2)
                                
                                // 翻译歌词
                                if showTranslation, let translation = line.translation {
                                    Text(translation)
                                        .font(.system(size: isCurrent ? 16 : 14, weight: .regular))
                                        .foregroundColor(isCurrent ? .white.opacity(0.7) : .white.opacity(distance <= 1 ? 0.3 : 0.15))
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentLyricIndex)
                            .id(index)
                            .onTapGesture {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                audioPlayer.seek(to: line.time)
                            }
                        }
                    }
                    .padding(.vertical, hasTranslation ? 120 : 180)
                    .padding(.horizontal, 24)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white, location: 0.12),
                            .init(color: .white, location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChangeCompat(of: currentLyricIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newIndex, anchor: .init(x: 0.5, y: 0.35))
                    }
                }
            }
        }
        .offset(y: imageOffset.height * 0.3)
    }
    
    // MARK: - 加载歌词（优先加载逐字歌词）
    private func loadLyrics() {
        guard let _ = audioPlayer.currentTrack?.id else { return }
        
        lyrics = []
        yrcLines = []
        isLoadingLyrics = true
        hasTranslation = false
        hasYrcLyric = false
        
        // 检查是否是本地歌曲
        let isLocal = audioPlayer.isPlayingLocal
        let localTrack = audioPlayer.currentLocalTrack
        
        if isLocal, let track = localTrack {
            // 优先读取侧载 .lrc
            if let lrc = localMusicService.findSidecarLyrics(for: track), !lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let parsed = LyricLine.parse(lrc)
                if parsed.isEmpty {
                    lyrics = [LyricLineWithTranslation(time: 0, text: lrc, translation: nil)]
                } else {
                    lyrics = parsed.map { LyricLineWithTranslation(time: $0.time, text: $0.text, translation: nil) }
                }
                hasTranslation = false
                hasYrcLyric = false
                currentLyricIndex = 0
                isLoadingLyrics = false
                #if DEBUG
                print("✅ 使用侧载歌词(.lrc): \(track.displayTitle)")
                #endif
                return
            }
            // 其次尝试内嵌歌词/或下载歌曲用 sourceTrackId 联网
            loadLocalLyrics(from: track)
            return
        }
        
        // 网络歌曲：从 API 获取歌词
        guard let trackId = audioPlayer.currentTrack?.id else {
            isLoadingLyrics = false
            return
        }
        
        Task {
            do {
                // 优先尝试获取逐字歌词
                let result = try await musicService.getYrcLyric(id: trackId)
                
                await MainActor.run {
                    // 如果有逐字歌词，解析YRC格式
                    if let yrcString = result.yrc, !yrcString.isEmpty {
                        yrcLines = YrcLine.parse(yrcString: yrcString, translation: result.translation)
                        hasYrcLyric = !yrcLines.isEmpty
                        hasTranslation = yrcLines.contains { $0.translation != nil }
                    }

                    // 同时解析普通歌词作为fallback
                    if !result.lyric.isEmpty {
                        lyrics = LyricLineWithTranslation.parse(lyric: result.lyric, translation: result.translation)
                        if !hasYrcLyric {
                            hasTranslation = lyrics.contains { $0.translation != nil }
                        }
                    }

                    currentLyricIndex = 0
                    isLoadingLyrics = false
                }
            } catch {
                #if DEBUG
                print("Load lyric error: \(error)")
                #endif
                await MainActor.run {
                    isLoadingLyrics = false
                }
            }
        }
    }
    
    /// 加载本地歌曲的歌词
    private func loadLocalLyrics(from localTrack: LocalTrack) {
        // 如果是下载的歌曲，优先用 sourceTrackId 从网络获取歌词
        if let sourceId = localTrack.sourceTrackId {
            #if DEBUG
            print("🎵 下载歌曲，使用 sourceTrackId 获取在线歌词: \(sourceId)")
            #endif
            
            Task {
                do {
                    let result = try await musicService.getYrcLyric(id: sourceId)
                    
                    await MainActor.run {
                        // 如果有逐字歌词
                        if let yrcString = result.yrc, !yrcString.isEmpty {
                            yrcLines = YrcLine.parse(yrcString: yrcString, translation: result.translation)
                            hasYrcLyric = !yrcLines.isEmpty
                            hasTranslation = yrcLines.contains { $0.translation != nil }
                        }
                        
                        // 解析普通歌词
                        if !result.lyric.isEmpty {
                            lyrics = LyricLineWithTranslation.parse(lyric: result.lyric, translation: result.translation)
                            if !hasYrcLyric {
                                hasTranslation = lyrics.contains { $0.translation != nil }
                            }
                        }
                        
                        currentLyricIndex = 0
                        isLoadingLyrics = false
                        
                        // 将普通歌词落盘为 .lrc 侧载，并更新内存模型，便于离线
                        if !result.lyric.isEmpty {
                            _ = localMusicService.saveSidecarLyrics(for: localTrack, lrcContent: result.lyric)
                            localMusicService.updateLocalTrackLyrics(trackId: localTrack.id, lyrics: result.lyric)
                        }
                        
                        #if DEBUG
print("✅ 下载歌曲歌词加载成功并已缓存到本地: \(hasYrcLyric ? "逐字" : "普通") \(lyrics.count) 行")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("⚠️ 获取在线歌词失败，尝试使用内嵌歌词: \(error)")
                    #endif
                    // 失败时回退到内嵌歌词
                    await MainActor.run {
                        loadEmbeddedLyrics(from: localTrack)
                    }
                }
            }
            return
        }
        
        // 非下载歌曲，使用内嵌歌词
        loadEmbeddedLyrics(from: localTrack)
    }
    
    /// 加载内嵌歌词
    private func loadEmbeddedLyrics(from localTrack: LocalTrack) {
        guard let embeddedLyrics = localTrack.embeddedLyrics, !embeddedLyrics.isEmpty else {
            lyrics = []
            isLoadingLyrics = false
            #if DEBUG
            print("🎵 本地歌曲无内嵌歌词: \(localTrack.displayTitle)")
            #endif
            return
        }
        
        let parsedLines = LyricLine.parse(embeddedLyrics)
        
        if parsedLines.isEmpty {
            lyrics = [LyricLineWithTranslation(time: 0, text: embeddedLyrics, translation: nil)]
        } else {
            lyrics = parsedLines.map { line in
                LyricLineWithTranslation(time: line.time, text: line.text, translation: nil)
            }
        }
        
        hasTranslation = false
        hasYrcLyric = false
        currentLyricIndex = 0
        isLoadingLyrics = false
        
        #if DEBUG
        print("✅ 加载内嵌歌词成功: \(lyrics.count) 行")
        #endif
    }
    
    // MARK: - 加载动态封面（优先使用预加载缓存，避免重复加载）
    private func loadDynamicCover() {
        guard let track = audioPlayer.currentTrack else { return }
        
        // 同一首歌不重复加载
        if lastLoadedTrackId == track.id { return }

        // 优先使用已下载的本地 MP4 文件
        if let localFileURL = DynamicCoverCache.shared.getLocalFile(for: track.id),
           FileManager.default.fileExists(atPath: localFileURL.path) {
            lastLoadedTrackId = track.id
            // 清理旧的 HLS WebView（URL 不同时才需要）
            if let oldUrl = dynamicCoverURL, oldUrl != localFileURL {
                WebViewPool.shared.recycleWebView(for: oldUrl.absoluteString)
            }
            dynamicCoverURL = localFileURL
            return
        }

        // 检查 AudioPlayer 缓存的远程 URL
        if let cachedUrlString = audioPlayer.getDynamicCoverURL(for: track.id),
           let cachedUrl = URL(string: cachedUrlString) {
            lastLoadedTrackId = track.id
            dynamicCoverURL = cachedUrl
            return
        }

        // 清理旧状态
        dynamicCoverURL = nil

        // 异步搜索
        let trackId = track.id
        let trackName = track.name
        let artistName = track.artistName
        Task {
            await searchAppleMusicAnimatedArtwork(
                trackId: trackId,
                songName: trackName,
                artistName: artistName
            )
        }
    }

    // MARK: - 搜索 Apple Music 动态封面
    private func searchAppleMusicAnimatedArtwork(trackId: Int, songName: String, artistName: String) async {
        do {
            if let videoUrlString = try await musicService.getAppleMusicAnimatedCover(
                songName: songName,
                artistName: artistName
            ),
               let videoUrl = URL(string: videoUrlString) {
                audioPlayer.cacheDynamicCoverURL(videoUrlString, for: trackId)
                HLSVariantCache.shared.preload(masterUrl: videoUrlString)
                await MainActor.run {
                    lastLoadedTrackId = trackId
                    dynamicCoverURL = videoUrl
                }
            } else {
                await MainActor.run { lastLoadedTrackId = trackId }
            }
        } catch {
            #if DEBUG
            print("Apple Music animated cover error: \(error)")
            #endif
        }
    }
    
    // MARK: - 恢复动态封面播放
    private func resumeDynamicCoverPlayback() {
        guard let url = dynamicCoverURL else { return }
        WebViewPool.shared.resumePlayback(for: url.absoluteString)
    }
    
    // MARK: - 更新当前歌词索引（性能优化版）
    private func updateCurrentLyricIndex(time: Double) {
        // 检测时间跳跃（seek 操作）
        let timeDiff = abs(time - lastLyricUpdateTime)
        let isSeek = timeDiff > 1.0 || audioPlayer.isSeeking

        // 性能优化：根据歌词类型使用不同的防抖策略
        if hasYrcLyric {
            // 逐字歌词需要高频更新，但依然添加轻微防抖（seek 时跳过防抖）
            guard isSeek || timeDiff > 0.05 else { return }
            lastLyricUpdateTime = time

            // 优化：先检查当前索引是否仍然有效，避免不必要的遍历（seek 时跳过此检查）
            if !isSeek && currentLyricIndex < yrcLines.count - 1 {
                let currentLine = yrcLines[currentLyricIndex]
                let nextLine = yrcLines[currentLyricIndex + 1]
                if time >= currentLine.startTime && time < nextLine.startTime {
                    return  // 当前索引仍然有效
                }
            }

            // 逐字歌词索引更新
            for (index, line) in yrcLines.enumerated().reversed() {
                if time >= line.startTime {
                    if currentLyricIndex != index {
                        currentLyricIndex = index
                        // 同步歌词到 Widget
                        let nextLyric = index + 1 < yrcLines.count ? yrcLines[index + 1].text : ""
                        audioPlayer.updateLyricsForWidget(currentLyric: line.text, nextLyric: nextLyric)
                    }
                    break
                }
            }
        } else {
            // 普通歌词模式下大幅降低更新频率（0.3秒）（seek 时跳过防抖）
            guard isSeek || timeDiff > 0.3 else { return }
            lastLyricUpdateTime = time

            // 优化：先检查当前索引是否仍然有效（seek 时跳过此检查）
            if !isSeek && currentLyricIndex < lyrics.count - 1 {
                let currentLine = lyrics[currentLyricIndex]
                let nextLine = lyrics[currentLyricIndex + 1]
                if time >= currentLine.time && time < nextLine.time {
                    return  // 当前索引仍然有效
                }
            }

            // 普通歌词索引更新
            for (index, line) in lyrics.enumerated().reversed() {
                if time >= line.time {
                    if currentLyricIndex != index {
                        currentLyricIndex = index
                        // 同步歌词到 Widget
                        let nextLyric = index + 1 < lyrics.count ? lyrics[index + 1].text : ""
                        audioPlayer.updateLyricsForWidget(currentLyric: line.text, nextLyric: nextLyric)
                    }
                    break
                }
            }
        }
    }
    
    // MARK: - 格式化时间
    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - WKWebView 缓存池
final class WebViewPool {
    static let shared = WebViewPool()

    private var keepAliveWebView: WKWebView?
    private var activeWebViews: [String: WKWebView] = [:]
    private let queue = DispatchQueue(label: "webViewPool")
    private var isWarmedUp = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func warmUp() {
        guard !isWarmedUp else { return }
        isWarmedUp = true
        if Thread.isMainThread {
            createWarmupWebView()
        } else {
            DispatchQueue.main.sync { createWarmupWebView() }
        }
    }

    private func createWarmupWebView() {
        let config = createWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1), configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        self.keepAliveWebView = webView
        #if DEBUG
        print("🚀 WebView 已预热")
        #endif
    }

    @objc private func handleMemoryWarning() {
        queue.async { [weak self] in
            self?.activeWebViews.removeAll()
        }
    }

    private func createWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = WKWebsiteDataStore.default()
        return config
    }

    /// 获取或创建 WebView（不再复用旧的，避免竞态）
    func getWebView(for url: String, coordinator: DynamicCoverVideoView.Coordinator) -> WKWebView {
        let config = createWebViewConfiguration()
        config.userContentController.add(coordinator, name: "log")
        config.userContentController.add(coordinator, name: "cache")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false

        queue.async { [weak self] in
            self?.activeWebViews[url] = webView
        }
        return webView
    }

    /// 按 URL 回收
    func recycleWebView(for url: String) {
        queue.async { [weak self] in
            if let wv = self?.activeWebViews.removeValue(forKey: url) {
                DispatchQueue.main.async {
                    wv.stopLoading()
                    wv.loadHTMLString("", baseURL: nil)
                    wv.configuration.userContentController.removeAllScriptMessageHandlers()
                }
            }
        }
    }

    func clearPool() {
        queue.async { [weak self] in
            self?.activeWebViews.removeAll()
        }
    }

    /// 恢复播放
    func resumePlayback(for url: String) {
        var webView: WKWebView?
        queue.sync { webView = activeWebViews[url] }
        guard let wv = webView else { return }
        DispatchQueue.main.async {
            wv.evaluateJavaScript("""
                (function() {
                    var v = document.querySelector('video');
                    if (v && v.paused) { v.muted = true; v.play().catch(function(){}); }
                })()
            """, completionHandler: nil)
        }
    }
}

// MARK: - 动态封面视频视图
struct DynamicCoverVideoView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(masterUrl: url.absoluteString)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let masterUrl: String
        weak var webView: WKWebView?

        init(masterUrl: String) {
            self.masterUrl = masterUrl
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "cache", let variantUrl = message.body as? String {
                HLSVariantCache.shared.setVariant(variantUrl, for: masterUrl)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            #if DEBUG
            print("⚠️ WKWebView navigation failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func swiftPreParse(masterUrl: String) -> String? {
        guard let url = URL(string: masterUrl) else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var resultVariant: String?
        AppleMusicNetworkSession.shared.fetchData(from: url, maxRetries: 2) { data, _, error in
            defer { semaphore.signal() }
            guard let data = data, let text = String(data: data, encoding: .utf8) else { return }
            if let variantUrl = HLSParser.shared.selectVariant(
                from: text, baseUrl: masterUrl,
                strategy: .preferAspectRatio(width: 3, height: 4, maxPixels: 720 * 960)
            ) {
                resultVariant = variantUrl
                HLSVariantCache.shared.setVariant(variantUrl, for: masterUrl)
            }
        }
        if semaphore.wait(timeout: .now() + .seconds(10)) == .timedOut { return nil }
        return resultVariant
    }

    func makeUIView(context: Context) -> WKWebView {
        let urlString = url.absoluteString
        let webView = WebViewPool.shared.getWebView(for: urlString, coordinator: context.coordinator)
        context.coordinator.webView = webView

        if url.isFileURL {
            let directory = url.deletingLastPathComponent()
            let videoFileName = url.lastPathComponent
            let htmlFile = directory.appendingPathComponent("_player_\(videoFileName).html")
            let html = """
            <!DOCTYPE html>
            <html><head>
            <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
            <style>*{margin:0;padding:0}html,body{width:100vw;height:100vh;background:transparent;overflow:hidden}
            video{position:fixed;top:0;left:0;width:100%;height:100%;object-fit:cover;background:transparent}</style>
            </head><body>
            <video id="v" autoplay loop muted playsinline webkit-playsinline src="\(videoFileName)"></video>
            <script>
            const v=document.getElementById('v');v.muted=true;
            v.play().catch(()=>{});
            v.addEventListener('pause',()=>{if(!v.ended)setTimeout(()=>v.play().catch(()=>{}),200)});
            </script></body></html>
            """
            try? html.write(to: htmlFile, atomically: true, encoding: .utf8)
            webView.loadFileURL(htmlFile, allowingReadAccessTo: directory)
            return webView
        }

        // 远程 HLS
        let cachedVariant = HLSVariantCache.shared.getVariant(for: urlString)
        if cachedVariant == nil {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = Self.swiftPreParse(masterUrl: urlString)
            }
        }
        let videoUrl = cachedVariant ?? urlString
        let hasCached = cachedVariant != nil
        let html = Self.buildHLSHTML(masterUrl: url.absoluteString, videoUrl: videoUrl, hasCached: hasCached)
        webView.loadHTMLString(html, baseURL: URL(string: "https://music.apple.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.evaluateJavaScript(
            "(function(){var v=document.querySelector('video');if(v&&v.paused&&v.readyState>=2){v.muted=true;v.play().catch(function(){});}})();"
        , completionHandler: nil)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        WebViewPool.shared.recycleWebView(for: coordinator.masterUrl)
    }

    // MARK: - HLS HTML
    private static func buildHLSHTML(masterUrl: String, videoUrl: String, hasCached: Bool) -> String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>*{margin:0;padding:0}html,body{width:100vw;height:100vh;background:transparent;overflow:hidden}
        #container{position:fixed;top:0;left:0;width:100vw;height:100vh;overflow:hidden}
        video{position:absolute;top:0;left:0;width:100%;height:100%;object-fit:cover;background:transparent}</style>
        </head><body><div id="container">
        <video id="v" autoplay loop muted playsinline webkit-playsinline preload="auto"></video>
        </div><script>
        const v=document.getElementById('v');
        const masterUrl='\(masterUrl)';
        const cachedUrl=\(hasCached ? "'\(videoUrl)'" : "null");
        const cache=url=>webkit.messageHandlers.cache.postMessage(url);
        let retryCount=0,isPlaying=false;

        function tryPlay(){
            if(isPlaying)return;
            v.muted=true;
            v.play().then(()=>{isPlaying=true}).catch(()=>{
                if(!isPlaying)setTimeout(tryPlay,200);
            });
        }

        v.addEventListener('loadedmetadata',()=>setTimeout(tryPlay,50));
        v.addEventListener('canplay',tryPlay);
        v.addEventListener('playing',()=>{isPlaying=true});
        v.addEventListener('pause',()=>{if(!v.ended)setTimeout(tryPlay,200)});
        v.addEventListener('stalled',()=>{
            setTimeout(()=>{if(v.paused||v.readyState<3)tryPlay()},2000);
        });
        v.addEventListener('error',()=>{
            if(retryCount<2){retryCount++;setTimeout(()=>{v.src=masterUrl;v.load();tryPlay()},retryCount*1000);}
        });

        (function loadVideo(){
            if(cachedUrl){v.src=cachedUrl;v.load();tryPlay();return;}
            v.src=masterUrl;v.load();
            setTimeout(()=>{
                if(v.readyState<2&&!isPlaying){
                    fetch(masterUrl,{signal:AbortSignal.timeout(15000)}).then(r=>r.text()).then(text=>{
                        const lines=text.split('\\n');const variants=[];
                        for(let i=0;i<lines.length;i++){
                            if(lines[i].startsWith('#EXT-X-STREAM-INF:')){
                                const bw=lines[i].match(/BANDWIDTH=(\\d+)/);
                                const res=lines[i].match(/RESOLUTION=(\\d+)x(\\d+)/);
                                if(bw&&res&&lines[i+1])variants.push({bw:+bw[1],w:+res[1],h:+res[2],url:lines[i+1].trim()});
                            }
                        }
                        if(!variants.length)return;
                        const maxPx=720*960;
                        const cands=variants.filter(x=>(x.w*x.h)<=maxPx);
                        const pick=cands.length?cands:[variants.reduce((a,b)=>(a.w*a.h)<(b.w*b.h)?a:b)];
                        let best=pick.reduce((a,b)=>(a.w*a.h)>(b.w*b.h)?a:b);
                        let url=best.url;
                        if(!url.startsWith('http'))url=masterUrl.substring(0,masterUrl.lastIndexOf('/')+1)+url;
                        cache(url);v.src=url;v.load();tryPlay();
                    }).catch(()=>{});
                }
            },10000);
            tryPlay();
        })();
        </script></body></html>
        """
    }
}

// MARK: - AVPlayer 容器（SwiftUI 包装）
struct AVPlayerContainerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> UIView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let v = uiView as? PlayerLayerView {
            v.player = player
        }
    }
}

// 使用 layerClass 直接返回 AVPlayerLayer（避免 layer 嵌套问题）
class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    
    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.backgroundColor = UIColor.clear.cgColor
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - HLS 资源代理加载器
class HLSResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = HLSResourceLoaderDelegate()
    
    var originalURL: URL?
    private let session: URLSession
    
    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        super.init()
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let requestURL = loadingRequest.request.url else {
            return false
        }
        
        // 将代理 URL 转回真实 URL
        var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        
        guard let realURL = components?.url else {
            return false
        }
        
        print(" HLS Proxy loading: \(realURL.lastPathComponent)")
        
        var request = URLRequest(url: realURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print(" HLS Proxy error: \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
                return
            }
            
            guard let data = data, let response = response as? HTTPURLResponse else {
                loadingRequest.finishLoading(with: NSError(domain: "HLSProxy", code: -1))
                return
            }
            
            // 处理 m3u8 播放列表 - 需要替换其中的 URL
            if realURL.pathExtension == "m3u8",
               var playlist = String(data: data, encoding: .utf8) {
                playlist = self?.rewritePlaylist(playlist, baseURL: realURL) ?? playlist
                if let modifiedData = playlist.data(using: .utf8) {
                    loadingRequest.dataRequest?.respond(with: modifiedData)
                    loadingRequest.finishLoading()
                    print(" HLS Proxy: playlist loaded")
                    return
                }
            }
            
            // 设置响应信息
            if let contentRequest = loadingRequest.contentInformationRequest {
                contentRequest.contentType = response.mimeType
                contentRequest.contentLength = Int64(data.count)
                contentRequest.isByteRangeAccessSupported = true
            }
            
            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        }
        task.resume()
        
        return true
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // 取消请求
    }
    
    // 重写播放列表中的 URL
    private func rewritePlaylist(_ playlist: String, baseURL: URL) -> String {
        var result = playlist
        let lines = playlist.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 跳过注释和空行
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // 处理相对 URL
            if !trimmed.hasPrefix("http") {
                if let absoluteURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteString {
                    // 替换为代理 URL
                    let proxyURL = absoluteURL.replacingOccurrences(of: "https://", with: "hlsproxy://")
                    result = result.replacingOccurrences(of: trimmed, with: proxyURL)
                }
            } else {
                // 绝对 URL 也替换为代理
                let proxyURL = trimmed.replacingOccurrences(of: "https://", with: "hlsproxy://")
                result = result.replacingOccurrences(of: trimmed, with: proxyURL)
            }
        }
        
        return result
    }
}

// MARK: - 播放控制按钮
struct PlayerControlButton: View {
    let icon: String
    var size: CGFloat = 24
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.2)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2)) {
                    isPressed = false
                }
                action()
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .scaleEffect(isPressed ? 0.85 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 播放列表弹窗
struct PlaylistSheetView: View {
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 播放模式指示
                HStack {
                    Image(systemName: audioPlayer.playMode.icon)
                        .foregroundColor(.secondary)
                    Text(audioPlayer.playMode.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(audioPlayer.playlist.count) 首歌曲")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                
                if audioPlayer.playlist.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("播放列表为空")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(audioPlayer.playlist.enumerated()), id: \.element.id) { index, track in
                            PlaylistTrackRow(
                                track: track,
                                index: index,
                                isPlaying: index == audioPlayer.currentIndex
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // 点击切换到该歌曲
                                audioPlayer.currentIndex = index
                                Task {
                                    await audioPlayer.play(track: track)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            // 从播放列表删除
                            audioPlayer.playlist.remove(atOffsets: indexSet)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清空") {
                        audioPlayer.playlist.removeAll()
                    }
                    .foregroundColor(.red)
                    .disabled(audioPlayer.playlist.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 播放列表歌曲行
struct PlaylistTrackRow: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 序号或播放指示
            ZStack {
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 28)
            
            // 封面
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            // 歌曲信息
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 15, weight: isPlaying ? .semibold : .regular))
                    .foregroundColor(isPlaying ? .red : .primary)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 分享弹窗
struct ShareSheetView: View {
    let track: Track
    @Environment(\.dismiss) var dismiss
    @State private var showingSystemShare = false
    @State private var coverImage: UIImage?
    
    private var shareText: String {
        "我正在听《\(track.name)》- \(track.artistName) #NeteaseMusic"
    }
    
    private var shareUrl: URL? {
        URL(string: "https://music.163.com/song?id=\(track.id)")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // 封面预览
                if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .onAppear {
                                    // 保存图片用于分享
                                    let renderer = ImageRenderer(content: image.resizable().aspectRatio(contentMode: .fill).frame(width: 300, height: 300))
                                    coverImage = renderer.uiImage
                                }
                        default:
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 10)
                }
                
                VStack(spacing: 8) {
                    Text(track.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(track.artistName)
                        .foregroundColor(.secondary)
                }
                
                // 分享按钮
                VStack(spacing: 16) {
                    HStack(spacing: 40) {
                        ShareOptionButton(icon: "square.and.arrow.up", title: "分享", color: .blue) {
                            showingSystemShare = true
                        }
                        ShareOptionButton(icon: "link", title: "复制链接", color: .green) {
                            if let url = shareUrl {
                                UIPasteboard.general.string = url.absoluteString
                                dismiss()
                            }
                        }
                        ShareOptionButton(icon: "doc.on.doc", title: "复制文案", color: .orange) {
                            UIPasteboard.general.string = shareText
                            dismiss()
                        }
                    }
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingSystemShare) {
                let items: [Any] = {
                    var result: [Any] = [shareText]
                    if let url = shareUrl {
                        result.append(url)
                    }
                    if let image = coverImage {
                        result.append(image)
                    }
                    return result
                }()
                ActivityViewController(activityItems: items, applicationActivities: nil)
            }
        }
    }
}

struct ShareOptionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(color)
                    )
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - 系统分享弹窗
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - AirPlay 按钮
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = UIColor.white.withAlphaComponent(0.8)
        routePickerView.activeTintColor = UIColor.systemBlue
        routePickerView.prioritizesVideoDevices = false
        routePickerView.backgroundColor = .clear
        
        // 设置约束让按钮居中且大小固定
        routePickerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(routePickerView)
        
        NSLayoutConstraint.activate([
            routePickerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            routePickerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            routePickerView.widthAnchor.constraint(equalToConstant: 24),
            routePickerView.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - 播放器组件视图

struct PlayerSongInfoView: View {
    let track: Track?
    let onShowLike: () -> Void
    let onShowShare: () -> Void
    let onArtistTap: (Artist) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 左侧占位（与右侧按钮宽度相同，保持标题居中）
            Color.clear
                .frame(width: 60)

            // 中间：歌曲信息（居中显示）
            VStack(spacing: 4) {
                Text(track?.name ?? "")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let track = track, let artist = track.artists?.first ?? track.ar?.first {
                    Button(action: { onArtistTap(artist) }) {
                        Text(track.artistName)
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(track?.artistName ?? "")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            // 右侧按钮
            HStack(spacing: 0) {
                Button(action: onShowLike) {
                    Image(systemName: "heart")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 30, height: 30)
                }

                Button(action: onShowShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 30, height: 30)
                }
            }
        }
    }
}

struct PlayerProgressView: View {
    let currentTime: Double
    let duration: Double
    @Binding var isDragging: Bool
    @Binding var dragProgress: Double
    let onSeek: (Double) -> Void

    private var displayTime: Double {
        isDragging ? dragProgress : currentTime
    }

    var body: some View {
        VStack(spacing: 8) {
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .frame(height: 4)

                    // 进度
                    Capsule()
                        .fill(.white)
                        .frame(width: geometry.size.width * CGFloat(displayTime / max(duration, 1)), height: 4)

                    // 滑块
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * CGFloat(displayTime / max(duration, 1)) - 6)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let progress = min(max(0, value.location.x / geometry.size.width), 1)
                            dragProgress = progress * duration
                        }
                        .onEnded { value in
                            isDragging = false
                            let progress = min(max(0, value.location.x / geometry.size.width), 1)
                            onSeek(progress * duration)
                        }
                )
            }
            .frame(height: 12)

            // 时间标签
            HStack {
                Text(formatTime(displayTime))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PlayerControlsView: View {
    let isPlaying: Bool
    let isLoading: Bool
    var isIPad: Bool = false
    @Binding var isPlayButtonPressed: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: isIPad ? 60 : 50) {
            // 上一首
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: isIPad ? 36 : 32))
                    .foregroundColor(.white)
            }

            // 播放/暂停
            Button(action: onPlayPause) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: isIPad ? 80 : 72, height: isIPad ? 80 : 72)

                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: isIPad ? 32 : 28))
                            .foregroundColor(.white)
                    }
                }
                .scaleEffect(isPlayButtonPressed ? 0.95 : 1.0)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPlayButtonPressed = true }
                    .onEnded { _ in isPlayButtonPressed = false }
            )

            // 下一首
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: isIPad ? 36 : 32))
                    .foregroundColor(.white)
            }
        }
    }
}

struct PlayerVolumeView: View {
    @ObservedObject var volumeObserver: VolumeObserver
    let systemVolumeController: SystemVolumeController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))

            Slider(
                value: $volumeObserver.volume,
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        volumeObserver.isDragging = true
                    } else {
                        // 延迟恢复，确保系统音量更新完成
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            volumeObserver.isDragging = false
                        }
                    }
                }
            )
                .tint(.white)
                .onChangeCompat(of: volumeObserver.volume) { _, newValue in
                    if volumeObserver.isDragging {
                        systemVolumeController.setVolume(newValue)
                    }
                }

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

struct PlayerBottomBarView: View {
    let showLyrics: Bool
    let playModeIcon: String
    @ObservedObject var sourceConfig: MusicSourceConfig
    @ObservedObject var audioPlayer: AudioPlayer
    let onToggleLyrics: () -> Void
    let onShowComments: () -> Void
    let onShowPlaylist: () -> Void
    let onTogglePlayMode: () -> Void
    
    @State private var showQualityPicker = false
    @State private var showDownloadCenter = false
    @State private var showSleepTimer = false
    @StateObject private var downloadService = SongDownloadService.shared
    @StateObject private var localMusicService = LocalMusicService.shared
    @StateObject private var sleepTimer = SleepTimerManager.shared
    
    // 将API返回的level转为显示名称
    private func qualityDisplayName(_ level: String) -> String {
        switch level {
        case "standard": return "标准"
        case "exhigh": return "HQ"
        case "lossless": return "无损"
        case "hires": return "Hi-Res"
        case "jyeffect": return "环绕"
        case "sky": return "沉浸"
        case "jymaster": return "母带"
        default: return level
        }
    }
    
    // 显示实际音质和请求音质
    private var displayQuality: String {
        let requestedQuality = sourceConfig.quality.shortName
        
        if audioPlayer.actualQuality.isEmpty {
            return requestedQuality
        }
        
        let actualName = qualityDisplayName(audioPlayer.actualQuality)
        
        // 如果实际音质与请求音质相同，只显示一个
        if audioPlayer.actualQuality == sourceConfig.quality.rawValue {
            return actualName
        }
        
        // 不同时显示两者
        return "\(actualName)(\(requestedQuality))"
    }
    
    // 检查当前歌曲是否已下载
    private var isCurrentTrackDownloaded: Bool {
        guard let track = audioPlayer.currentTrack else { return false }
        return localMusicService.localTracks.contains { $0.sourceTrackId == track.id }
    }
    
    // 当前歌曲下载状态
    private var currentDownloadStatus: DownloadStatus {
        guard let track = audioPlayer.currentTrack else { return .idle }
        return downloadService.getStatus(trackId: track.id)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // 歌词按钮
            Button(action: onToggleLyrics) {
                Image(systemName: showLyrics ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 评论按钮
            Button(action: onShowComments) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 下载按钮
            downloadButton
            
            // 音质按钮 - 显示实际音质
            Button(action: { showQualityPicker = true }) {
                Text(displayQuality)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                    )
            }
            .frame(minWidth: 65)
            
            Spacer()
            
            // AirPlay 按钮
            AirPlayButton()
                .frame(width: 22, height: 22)
            
            // 定时关闭按钮
            Button(action: { showSleepTimer = true }) {
                ZStack {
                    Image(systemName: sleepTimer.isActive ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 20))
                        .foregroundColor(sleepTimer.isActive ? .orange : .white.opacity(0.8))
                    
                    // 倒计时显示
                    if case .countdown = sleepTimer.mode {
                        Text(sleepTimer.formattedRemainingTime)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                            .offset(y: 14)
                    }
                }
            }
            
            // 播放模式
            Button(action: onTogglePlayMode) {
                Image(systemName: playModeIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // 播放列表
            Button(action: onShowPlaylist) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 32)
        .sheet(isPresented: $showQualityPicker) {
            QualityPickerView(sourceConfig: sourceConfig)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showDownloadCenter) {
            DownloadCenterView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - 下载按钮
    @ViewBuilder
    private var downloadButton: some View {
        if isCurrentTrackDownloaded {
            // 已下载 - 点击打开下载中心
            Button(action: { showDownloadCenter = true }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            }
        } else {
            switch currentDownloadStatus {
            case .idle:
                // 未下载 - 点击开始下载
                Button {
                    if let track = audioPlayer.currentTrack {
                        downloadService.download(track: track)
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                }
            case .waiting:
                // 等待中
                Button(action: { showDownloadCenter = true }) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                }
            case .downloading(let progress):
                // 下载中 - 显示进度
                Button(action: { showDownloadCenter = true }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 22, height: 22)
                }
            case .completed:
                // 完成
                Button(action: { showDownloadCenter = true }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            case .failed:
                // 失败 - 点击重试
                Button {
                    if let track = audioPlayer.currentTrack {
                        downloadService.retry(track: track)
                    }
                } label: {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - 音质选择视图
struct QualityPickerView: View {
    @ObservedObject var sourceConfig: MusicSourceConfig
    @Environment(\.dismiss) var dismiss
    @State private var selectedQuality: MusicQuality
    
    init(sourceConfig: MusicSourceConfig) {
        self.sourceConfig = sourceConfig
        _selectedQuality = State(initialValue: sourceConfig.quality)
    }
    
    // 音质分组
    private let standardQualities: [MusicQuality] = [.standard, .exhigh]
    private let hdQualities: [MusicQuality] = [.lossless, .hires]
    private let spatialQualities: [MusicQuality] = [.jyeffect, .sky, .jymaster]
    
    var body: some View {
        ZStack {
            // 暗色模糊背景
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部拖拽指示器
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)
                
                // 标题
                HStack {
                    Text("音质选择")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // 标准音质组
                        QualityGroup(title: "标准", qualities: standardQualities, selectedQuality: $selectedQuality, onSelect: applyQuality)
                        
                        // 无损音质组
                        QualityGroup(title: "无损", qualities: hdQualities, selectedQuality: $selectedQuality, onSelect: applyQuality)
                        
                        // 空间音频组
                        QualityGroup(title: "空间音频", qualities: spatialQualities, selectedQuality: $selectedQuality, onSelect: applyQuality)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    private func applyQuality(_ quality: MusicQuality) {
        let oldQuality = sourceConfig.quality
        sourceConfig.quality = quality
        AudioPlayer.shared.clearPreloadCache()
        
        if oldQuality != quality, let currentTrack = AudioPlayer.shared.currentTrack {
            let currentTime = AudioPlayer.shared.currentTime
            Task {
                await AudioPlayer.shared.play(track: currentTrack)
                try? await Task.sleep(nanoseconds: 500_000_000)
                AudioPlayer.shared.seek(to: currentTime)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

// MARK: - 音质分组
struct QualityGroup: View {
    let title: String
    let qualities: [MusicQuality]
    @Binding var selectedQuality: MusicQuality
    let onSelect: (MusicQuality) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.leading, 4)
            
            VStack(spacing: 8) {
                ForEach(qualities, id: \.self) { quality in
                    QualityOptionCard(
                        quality: quality,
                        isSelected: selectedQuality == quality,
                        onSelect: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedQuality = quality
                            }
                            onSelect(quality)
                        }
                    )
                }
            }
        }
    }
}

// MARK: - 音质选项卡片
struct QualityOptionCard: View {
    let quality: MusicQuality
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var qualityInfo: (icon: String, gradient: [Color], desc: String, badge: String?) {
        switch quality {
        case .standard:
            return ("speaker.wave.1.fill", [.gray, .gray.opacity(0.7)], "128kbps MP3", nil)
        case .exhigh:
            return ("speaker.wave.2.fill", [.blue, .cyan], "320kbps MP3", "HQ")
        case .lossless:
            return ("hifispeaker.fill", [.green, .mint], "16bit/44.1kHz FLAC", "无损")
        case .hires:
            return ("hifispeaker.2.fill", [.purple, .pink], "24bit/192kHz", "Hi-Res")
        case .jyeffect:
            return ("ear.fill", [.orange, .yellow], "高清环绕声", "环绕")
        case .sky:
            return ("sparkles", [.cyan, .blue], "Dolby Atmos", "沉浸")
        case .jymaster:
            return ("crown.fill", [.yellow, .orange], "超清母带", "臻峰")
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // 渐变图标
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isSelected ? qualityInfo.gradient : [.gray.opacity(0.3), .gray.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: qualityInfo.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isSelected ? .white : .gray)
                }
                
                // 文字
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(quality.displayName)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(.white)
                        
                        if let badge = qualityInfo.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        colors: qualityInfo.gradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(qualityInfo.desc)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // 选中指示
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected 
                                ? LinearGradient(colors: qualityInfo.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [.white.opacity(0.2)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 2
                        )
                        .frame(width: 26, height: 26)
                    
                    if isSelected {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: qualityInfo.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 16, height: 16)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isSelected 
                            ? LinearGradient(colors: qualityInfo.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected
                            ? LinearGradient(colors: qualityInfo.gradient.map { $0.opacity(0.5) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - DJ 过渡提示悬浮层 (已禁用)
struct DJTransitionOverlay: View {
    var body: some View {
        EmptyView()
    }
}

// MARK: - 喜欢选项弹窗
struct LikeOptionsSheet: View {
    let track: Track
    @Environment(\.dismiss) var dismiss
    @StateObject private var localStorage = LocalStorageService.shared
    
    @State private var isLiking = false
    @State private var showLoginAlert = false
    @State private var toastMessage: String?
    @State private var showToast = false
    
    private let userService = UserService.shared
    private let authService = AuthService.shared
    
    // 检查是否已本地收藏
    private var isLocalFavorited: Bool {
        localStorage.isFavorite(track.id)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 歌曲信息
                HStack(spacing: 16) {
                    // 封面
                    if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artistName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)
                
                Divider()
                
                // 选项列表
                VStack(spacing: 0) {
                    // 喜欢到网易云
                    LikeOptionRow(
                        icon: "cloud.fill",
                        iconColor: .red,
                        title: "喜欢到网易云",
                        subtitle: "同步到网易云账号",
                        isLoading: isLiking,
                        action: likeToCloud
                    )
                    
                    Divider().padding(.leading, 60)
                    
                    // 喜欢到本地
                    LikeOptionRow(
                        icon: isLocalFavorited ? "heart.fill" : "heart",
                        iconColor: isLocalFavorited ? .pink : .pink,
                        title: isLocalFavorited ? "已收藏到本地" : "收藏到本地",
                        subtitle: isLocalFavorited ? "点击取消本地收藏" : "保存到本地收藏夹",
                        isLoading: false,
                        action: toggleLocalFavorite
                    )
                }
                
                Spacer()
            }
            .navigationTitle("喜欢歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .alert("需要登录", isPresented: $showLoginAlert) {
                Button("取消", role: .cancel) {}
                Button("去登录") {
                    dismiss()
                    // 跳转到登录页面（通过发通知）
                    NotificationCenter.default.post(name: .showLoginSheet, object: nil)
                }
            } message: {
                Text("请先登录网易云账号后再进行操作")
            }
            .overlay(alignment: .bottom) {
                if showToast, let message = toastMessage {
                    ToastView(message: message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - 喜欢到网易云
    private func likeToCloud() {
        // 检查登录状态
        guard authService.isLoggedIn() else {
            showLoginAlert = true
            return
        }
        
        isLiking = true
        Task {
            do {
                let _ = try await userService.likeSong(id: track.id, like: true)
                await MainActor.run {
                    isLiking = false
                    showToastMessage("已添加到网易云喜欢")
                    LikedSongsStore.shared.markDirty()
                    NotificationCenter.default.post(name: .likedSongsChanged, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isLiking = false
                    showToastMessage("喜欢失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - 切换本地收藏
    private func toggleLocalFavorite() {
        let wasAdded = localStorage.toggleFavorite(track)
        showToastMessage(wasAdded ? "已添加到本地收藏" : "已从本地收藏移除")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }
    
    // MARK: - 显示 Toast
    private func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.3)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.3)) {
                showToast = false
            }
        }
    }
}

// MARK: - 喜欢选项行
struct LikeOptionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // 图标
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(iconColor)
                    }
                }
                
                // 文字
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Toast 视图
struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
            )
    }
}

// MARK: - 登录弹窗通知
extension Notification.Name {
    static let showLoginSheet = Notification.Name("showLoginSheet")
    static let likedSongsChanged = Notification.Name("likedSongsChanged")
}

#Preview {
    PlayerView()
}
