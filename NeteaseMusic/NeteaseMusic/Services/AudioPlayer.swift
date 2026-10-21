import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
import WidgetKit

// MARK: - 播放模式
enum PlayMode: String, CaseIterable {
    case order = "顺序播放"
    case random = "随机播放"
    case repeatOne = "单曲循环"
    
    var icon: String {
        switch self {
        case .order: return "repeat"
        case .random: return "shuffle"
        case .repeatOne: return "repeat.1"
        }
    }

    /// 用于持久化存储的值（不要使用 rawValue，rawValue 用于 UI 展示）
    var storageValue: String {
        switch self {
        case .order: return "order"
        case .random: return "random"
        case .repeatOne: return "repeatOne"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "order": self = .order
        case "random": self = .random
        case "repeatOne": self = .repeatOne
        default: return nil
        }
    }
}

// MARK: - 缓冲状态
enum BufferingState: Equatable {
    case idle
    case buffering(progress: Double)  // 0-1
    case ready
    case failed(String)
    
    var isBuffering: Bool {
        if case .buffering = self { return true }
        return false
    }
}

// MARK: - 播放器错误
enum AudioPlayerError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case playbackFailed(String)
    case noAvailableSource
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的播放链接"
        case .networkError(let msg):
            return "网络错误: \(msg)"
        case .playbackFailed(let msg):
            return "播放失败: \(msg)"
        case .noAvailableSource:
            return "暂无可用音源"
        }
    }
}

// MARK: - 歌曲URL响应
struct SongUrlResponse: Codable {
    let code: Int
    let data: [SongUrlData]?
}

struct SongUrlData: Codable {
    let id: Int
    let url: String?
    let br: Int?          // 比特率
    let size: Int?        // 文件大小
    let type: String?     // 文件类型
    let level: String?    // 音质等级
}

// MARK: - 音频播放器
class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    
    // MARK: - Published 属性
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    /// 实时播放时间（直接从 AVPlayer 获取，用于高频更新场景如逐字歌词）
    /// 注意：这个属性不是 @Published，不会触发 SwiftUI 重绘
    var realtimePlaybackTime: Double {
        guard let player = player else { return currentTime }
        let time = CMTimeGetSeconds(player.currentTime())
        return time.isFinite ? time : currentTime
    }
    @Published var playlist: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var playMode: PlayMode = .order
    @Published var actualQuality: String = ""  // 实际获取到的音质
    @Published var bufferingState: BufferingState = .idle
    @Published var lastError: AudioPlayerError?
    @Published var currentLocalTrack: LocalTrack?  // 当前播放的本地歌曲
    @Published var isPlayingLocal: Bool = false    // 是否在播放本地歌曲

    // MARK: - 回调
    var onTimeUpdate: ((Double) -> Void)?
    var onError: ((AudioPlayerError) -> Void)?
    
    /// seek 进行中标记，防止旧时间回调导致歌词跳回
    private(set) var isSeeking: Bool = false
    
    // MARK: - 歌词高频更新（CADisplayLink 驱动，~60fps）
    private var lyricsDisplayLink: CADisplayLink?
    var lyricsTimeUpdateInterval: Double = 0 {
        didSet {
            if lyricsTimeUpdateInterval > 0 {
                startLyricsDisplayLink()
            } else {
                stopLyricsDisplayLink()
            }
        }
    }
    
    private func startLyricsDisplayLink() {
        stopLyricsDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(lyricsDisplayLinkFired))
        // 约 30fps，足够歌词逐字动画丝滑
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        lyricsDisplayLink = link
    }
    
    private func stopLyricsDisplayLink() {
        lyricsDisplayLink?.invalidate()
        lyricsDisplayLink = nil
    }
    
    @objc private func lyricsDisplayLinkFired() {
        guard let player = player, isPlaying, !isSeeking else { return }
        let seconds = CMTimeGetSeconds(player.currentTime())
        if seconds.isFinite {
            onTimeUpdate?(seconds)
        }
    }
    
    // MARK: - 私有属性
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var bufferObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    private var playbackStateCancellables = Set<AnyCancellable>()
    private let musicService = MusicService.shared
    private let sourceConfig = MusicSourceConfig.shared
    private let songCache = SongCacheService.shared
    
    // 预加载缓存
    private var preloadedURLs: [Int: String] = [:]
    private let maxPreloadCacheCount = 20  // 限制预加载缓存数量
    private let preloadQueue = DispatchQueue(label: "audioPlayer.preload", qos: .utility)
    private var preloadTasks: [Int: Task<Void, Never>] = [:]  // 预加载任务管理

    // 动态封面预加载任务
    private var dynamicCoverTask: Task<Void, Never>?
    
    // 时长观察者
    private var durationObserver: NSKeyValueObservation?

    // 重试配置
    private let maxRetryCount = 3
    private var currentRetryCount = 0

    // Widget 数据服务
    private let widgetService = WidgetDataService.shared

    // 当前歌词（用于 Widget 同步）
    @Published var currentLyricText: String = ""
    @Published var nextLyricText: String = ""

    // Widget 刷新节流
    private var lastWidgetRefreshTime: Date = .distantPast
    private let widgetRefreshInterval: TimeInterval = 3.0  // 最少 3 秒刷新一次
    
    // MARK: - 初始化
    private init() {
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotifications()
        
        // 启动时清理过期缓存
        songCache.cleanExpired()
        
        // 一次性清理旧的 1:1 动态封面缓存（升级到 3:4 版本后）
        migrateAnimatedArtworkCacheIfNeeded()
        
        // 恢复上次播放队列（仅恢复信息，不自动播放）
        restorePlaybackState()

        // 监听队列/索引/播放模式变化，持久化保存（用于重启后恢复播放列表）
        setupPlaybackStatePersistence()
    }
    
    /// 迁移动态封面缓存（一次性清理旧的 1:1 缓存）
    private func migrateAnimatedArtworkCacheIfNeeded() {
        let migrationKey = "AnimatedArtworkMigratedTo3x4_v1"
        
        // 如果已经迁移过，跳过
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return
        }
        
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let animatedArtworkDir = cacheDir.appendingPathComponent("AnimatedArtwork", isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: animatedArtworkDir.path) {
                try FileManager.default.removeItem(at: animatedArtworkDir)
                #if DEBUG
                print("✅ 已清理旧的动态封面缓存（升级到 3:4）")
                #endif
            }
            // 清理统一缓存
            DynamicCoverCache.shared.clearAll()
        } catch {
            #if DEBUG
            print(" 清理动态封面缓存失败: \(error.localizedDescription)")
            #endif
        }
        
        // 标记已迁移
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
    
    // MARK: - 播放队列持久化

    private func setupPlaybackStatePersistence() {
        Publishers.CombineLatest3($playlist, $currentIndex, $playMode)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { playlist, currentIndex, playMode in
                if playlist.isEmpty {
                    LocalStorageService.shared.clearPlaybackState()
                    return
                }

                LocalStorageService.shared.savePlaybackState(
                    playlist: playlist,
                    currentIndex: currentIndex,
                    playMode: playMode.storageValue
                )
            }
            .store(in: &playbackStateCancellables)
    }

    /// 恢复上次播放队列（仅恢复信息，不自动播放）
    private func restorePlaybackState() {
        if let state = LocalStorageService.shared.getPlaybackState(), !state.playlist.isEmpty {
            playlist = state.playlist
            let safeIndex = min(max(0, state.currentIndex), playlist.count - 1)
            currentIndex = safeIndex
            currentTrack = playlist[safeIndex]

            if let savedMode = state.playMode, let mode = PlayMode(storageValue: savedMode) {
                playMode = mode
            }
            return
        }

        // 兜底：如果没有保存队列，只恢复上次播放的单首歌曲信息
        restoreLastPlayedTrack()
    }

    /// 恢复上次播放的歌曲（兜底：无保存队列时使用）
    private func restoreLastPlayedTrack() {
        if let lastTrack = LocalStorageService.shared.getLastPlayedTrack() {
            currentTrack = lastTrack
            // 添加到播放列表以便后续操作
            if playlist.isEmpty {
                playlist = [lastTrack]
                currentIndex = 0
            }
        }
    }
    
    // MARK: - 允许与其他应用同时播放
    @Published var allowMixWithOthers: Bool = UserDefaults.standard.bool(forKey: "allow_mix_with_others") {
        didSet {
            UserDefaults.standard.set(allowMixWithOthers, forKey: "allow_mix_with_others")
            setupAudioSession()
        }
    }
    
    // MARK: - 音频会话设置
    func setupAudioSession() {
        do {
            if allowMixWithOthers {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            } else {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            }
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            #if DEBUG
            print(" 音频会话设置失败: \(error)")
            #endif
        }
    }
    
    // MARK: - 远程控制中心
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }
    
    // MARK: - 通知监听
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }
    
    // MARK: - 播放控制
    
    /// 播放指定歌曲（带重试和缓冲状态）
    func play(track: Track) async {
        #if DEBUG
        print("🎵 play(track:) 被调用: \(track.name)")
        #endif

        await MainActor.run {
            isLoading = true
            bufferingState = .buffering(progress: 0)
            currentTrack = track
            currentLocalTrack = nil
            isPlayingLocal = false
            lastError = nil
            currentRetryCount = 0
        }

        // 添加到播放历史（在主线程执行）
        await MainActor.run {
            LocalStorageService.shared.addToHistory(track)
            LocalStorageService.shared.saveLastPlayedTrack(track)
        }

        // 立即开始预加载动态封面（不等待结果）
        preloadDynamicCover(for: track)

        // 同步到 Widget（异步加载封面）
        syncWidgetWithCover(track: track)

        await playWithRetry(track: track)
    }
    
    /// 播放本地歌曲
    func play(localTrack: LocalTrack) async {
        await MainActor.run {
            isLoading = true
            bufferingState = .buffering(progress: 0)
            currentLocalTrack = localTrack
            currentTrack = localTrack.toTrack()
            isPlayingLocal = true
            lastError = nil
        }
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: localTrack.fileURL.path) else {
            await MainActor.run {
                isLoading = false
                lastError = .playbackFailed("文件不存在")
                bufferingState = .failed("文件不存在")
            }
            return
        }
        
        await MainActor.run {
            bufferingState = .buffering(progress: 0.5)
        }
        
        // 设置播放器（本地文件）
        await setupLocalPlayer(with: localTrack.fileURL, track: localTrack)
    }
    
    /// 设置本地文件播放器
    private func setupLocalPlayer(with url: URL, track: LocalTrack) async {
        await MainActor.run {
            // 移除旧的观察者
            cleanupObservers()
            
            // 重置时长
            self.duration = 0
            self.currentTime = 0
            
            // 本地文件不需要请求头
            let asset = AVURLAsset(url: url)
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem)
            
            // 添加时间观察者（4fps 基础更新，降低 CPU 占用）
            let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    // 只在时间变化超过 1 秒时才更新 @Published 的 currentTime
                    if abs(seconds - self.currentTime) >= 1.0 {
                        self.currentTime = seconds
                    }
                    // seek 期间跳过回调，防止旧时间导致歌词跳回
                    if !self.isSeeking {
                        self.onTimeUpdate?(seconds)
                    }
                }
            }

            // 监听播放结束
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerDidFinishPlaying),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
            
            // 监听播放状态
            playerItem?.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    guard let self = self else { return }
                    switch status {
                    case .readyToPlay:
                        self.isLoading = false
                        self.bufferingState = .ready
                        if let duration = self.playerItem?.duration {
                            let seconds = CMTimeGetSeconds(duration)
                            if seconds.isFinite {
                                self.duration = seconds
                            }
                        }
                    case .failed:
                        self.isLoading = false
                        self.bufferingState = .failed("播放失败")
                    default:
                        break
                    }
                }
                .store(in: &cancellables)
            
            // 开始播放
            player?.play()
            isPlaying = true
            isLoading = false
            
            // 更新锁屏信息（本地歌曲）
            updateLocalNowPlayingInfo(track: track)
        }
    }
    
    /// 更新本地歌曲锁屏信息
    private func updateLocalNowPlayingInfo(track: LocalTrack) {
        var info = [String: Any]()
        
        info[MPMediaItemPropertyTitle] = track.displayTitle
        info[MPMediaItemPropertyArtist] = track.artistName
        info[MPMediaItemPropertyAlbumTitle] = track.albumName
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // 设置封面
        if let artworkImage = track.artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    /// 设置本地歌曲播放列表
    func setLocalPlaylist(_ tracks: [LocalTrack], startAt index: Int) {
        // 将本地歌曲转换为 Track 用于播放列表管理
        playlist = tracks.map { $0.toTrack() }
        currentIndex = index
        if index < tracks.count {
            Task {
                await play(localTrack: tracks[index])
            }
        }
    }
    
    /// 带重试的播放逻辑
    private func playWithRetry(track: Track) async {
        #if DEBUG
        print("🟢 [playWithRetry] 开始播放: \(track.name), id: \(track.id)")
        #endif
        
        do {
            // 获取歌曲URL（优先使用缓存）
            let urlString = try await getSongUrl(id: track.id)

            #if DEBUG
            print("🔗 获取到音频 URL: \(urlString.prefix(80))...")
            #endif

            guard let url = URL(string: urlString) else {
                throw AudioPlayerError.invalidURL
            }

            await MainActor.run {
                bufferingState = .buffering(progress: 0.3)
            }

            // 使用 AVPlayer 播放
            await setupPlayer(with: url, track: track)

        } catch {
            await handlePlaybackError(error, track: track)
        }
    }
    
    /// 设置播放器
    private func setupPlayer(with url: URL, track: Track) async {
        #if DEBUG
        print("🎶 setupPlayer 被调用: \(track.name)")
        #endif
        
        await MainActor.run {
            // 移除旧的观察者
            cleanupObservers()
            
            // 使用 Track 元数据中的时长作为初始值（比流媒体报告的更准确）
            self.duration = track.durationSeconds > 0 ? track.durationSeconds : 0
            self.currentTime = 0
            
            // 创建带请求头的 AVURLAsset（解决网易云音乐防盗链问题）
            let headers = [
                "Referer": "https://music.163.com/",
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 CloudMusic/1.0",
                "Origin": "https://music.163.com"
            ]
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem)
            
            // 设置缓冲策略
            playerItem?.preferredForwardBufferDuration = 10  // 预缓冲10秒
            
            // 添加时间观察者（4fps 基础更新）
            // 注意：currentTime 的 @Published 更新会触发所有观察者重绘
            // 所以我们只在时间变化超过 1 秒时才更新 currentTime
            // onTimeUpdate 回调仍然保持 0.25 秒的频率，供需要高频更新的视图使用
            let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    // 只在时间变化超过 1 秒时才更新 @Published 的 currentTime
                    // 这样可以大幅减少不必要的视图重绘
                    if abs(seconds - self.currentTime) >= 1.0 {
                        self.currentTime = seconds
                    }
                    // 如果当前时间超过了 duration，实时更新 duration（流媒体时长可能不准）
                    if seconds > self.duration {
                        self.duration = seconds
                    }
                    // 回调保持较高频率，供需要的视图使用
                    // seek 期间跳过回调，防止旧时间导致歌词跳回
                    if !self.isSeeking {
                        self.onTimeUpdate?(seconds)
                    }
                }
            }
            
            // 监听缓冲进度
            bufferObserver = playerItem?.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                self.updateBufferProgress(item: item)
            }
            
            // 监听时长变化（播放器报告的时长更准确时覆盖 API 时长）
            durationObserver = playerItem?.observe(\.duration, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                let seconds = CMTimeGetSeconds(item.duration)
                // 如果播放器报告的时长更大，则使用播放器的时长（API 时长可能不准确）
                if seconds.isFinite && seconds > 0 && seconds > self.duration {
                    DispatchQueue.main.async {
                        self.duration = seconds
                    }
                }
            }
            
            // 监听播放结束
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerDidFinishPlaying),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
            
            // 监听播放失败
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerDidFail),
                name: .AVPlayerItemFailedToPlayToEndTime,
                object: playerItem
            )
            
            // 监听播放状态
            playerItem?.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    guard let self = self else { return }
                    switch status {
                    case .readyToPlay:
                        self.isLoading = false
                        self.bufferingState = .ready
                        // 只有当 duration 为 0 时才使用流媒体报告的时长
                        if self.duration == 0, let playerDuration = self.playerItem?.duration {
                            let seconds = CMTimeGetSeconds(playerDuration)
                            if seconds.isFinite && seconds > 0 {
                                self.duration = seconds
                            }
                        }
                    case .failed:
                        if let error = self.playerItem?.error {
                            self.handlePlaybackFailure(error: error)
                        }
                    default:
                        break
                    }
                }
                .store(in: &cancellables)
            
            // 开始播放
            player?.play()
            isPlaying = true
            isLoading = false
            
            // 更新锁屏信息
            updateNowPlayingInfo()
            
            // 批量预加载后续歌曲
            batchPreloadNextTracks()
        }
    }
    
    /// 更新缓冲进度
    private func updateBufferProgress(item: AVPlayerItem) {
        guard let timeRange = item.loadedTimeRanges.first?.timeRangeValue else { return }
        let bufferedTime = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)
        let duration = CMTimeGetSeconds(item.duration)
        
        if duration > 0 {
            let progress = min(bufferedTime / duration, 1.0)
            DispatchQueue.main.async {
                if case .buffering(let oldProgress) = self.bufferingState {
                    // 只在进度变化超过 5% 时才更新，减少不必要的 UI 刷新
                    if abs(progress - oldProgress) >= 0.05 {
                        self.bufferingState = .buffering(progress: progress)
                    }
                }
            }
        }
    }
    
    /// 处理播放错误（带重试）
    private func handlePlaybackError(_ error: Error, track: Track) async {
        currentRetryCount += 1
        
        if currentRetryCount <= maxRetryCount {
            #if DEBUG
            print(" 播放失败，重试 \(currentRetryCount)/\(maxRetryCount): \(error.localizedDescription)")
            #endif
            
            // 清除该歌曲的 URL 缓存（可能已过期）
            songCache.clearUrlCache(songId: track.id)
            preloadedURLs.removeValue(forKey: track.id)
            
            // 等待后重试（指数退避）
            let delay = pow(2.0, Double(currentRetryCount - 1))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            await playWithRetry(track: track)
        } else {
            // 重试次数用尽
            await MainActor.run {
                isLoading = false
                let playerError = AudioPlayerError.playbackFailed(error.localizedDescription)
                lastError = playerError
                bufferingState = .failed(error.localizedDescription)
                onError?(playerError)
            }
            
            #if DEBUG
            print(" 播放失败（已达最大重试次数）: \(error)")
            #endif
        }
    }
    
    /// 播放失败处理（触发重试）
    private func handlePlaybackFailure(error: Error) {
        #if DEBUG
        print(" 播放器错误: \(error)")
        #endif

        // 如果有当前歌曲，尝试重试
        if let track = currentTrack {
            Task {
                await handlePlaybackError(error, track: track)
            }
        } else {
            // 确保在主线程更新 @Published 属性
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let playerError = AudioPlayerError.playbackFailed(error.localizedDescription)
                self.lastError = playerError
                self.bufferingState = .failed(error.localizedDescription)
                self.onError?(playerError)
            }
        }
    }
    
    @objc private func playerDidFail(_ notification: Notification) {
        // 确保在主线程处理
        DispatchQueue.main.async { [weak self] in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                self?.handlePlaybackFailure(error: error)
            }
        }
    }
    
    /// 清理观察者
    private func cleanupObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        bufferObserver?.invalidate()
        bufferObserver = nil
        durationObserver?.invalidate()
        durationObserver = nil
        cancellables.removeAll()

        // 移除 playerItem 相关的通知观察者，避免重复添加
        if let item = playerItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        // 确保在主线程执行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch self.playMode {
            case .order:
                self.playNext()
            case .random:
                self.playRandomNext()
            case .repeatOne:
                self.seek(to: 0)
                self.play()
            }
        }
    }
    
    /// 播放
    func play() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
        syncWidgetPlayingState()
    }

    /// 暂停
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        syncWidgetPlayingState()
    }
    
    /// 切换播放/暂停
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            // 如果 player 为 nil 但有 currentTrack（恢复的歌曲），则开始播放
            if player == nil, let track = currentTrack {
                Task {
                    await play(track: track)
                }
            } else {
                play()
            }
        }
    }
    
    /// 播放下一首
    func playNext() {
        // 如果播放列表为空但有 currentTrack，尝试从历史记录播放下一首
        if playlist.isEmpty {
            if let currentTrack = currentTrack {
                // 从播放历史中获取下一首
                let history = LocalStorageService.shared.getHistory()
                if let currentIndex = history.firstIndex(where: { $0.id == currentTrack.id }),
                   currentIndex + 1 < history.count {
                    let nextTrack = history[currentIndex + 1]
                    Task {
                        await play(track: nextTrack)
                    }
                } else if let firstTrack = history.first, firstTrack.id != currentTrack.id {
                    // 如果当前歌曲不在历史中，播放历史第一首
                    Task {
                        await play(track: firstTrack)
                    }
                }
            }
            return
        }
        
        let nextIndex: Int
        switch playMode {
        case .order, .repeatOne:
            nextIndex = (currentIndex + 1) % playlist.count
        case .random:
            nextIndex = Int.random(in: 0..<playlist.count)
        }
        
        currentIndex = nextIndex
        Task {
            await play(track: playlist[nextIndex])
        }
    }
    
    /// 播放上一首
    func playPrevious() {
        guard !playlist.isEmpty else { return }
        
        let prevIndex: Int
        switch playMode {
        case .order, .repeatOne:
            prevIndex = (currentIndex - 1 + playlist.count) % playlist.count
        case .random:
            prevIndex = Int.random(in: 0..<playlist.count)
        }
        
        currentIndex = prevIndex
        Task {
            await play(track: playlist[prevIndex])
        }
    }
    
    /// 随机播放下一首
    private func playRandomNext() {
        guard !playlist.isEmpty else { return }
        let randomIndex = Int.random(in: 0..<playlist.count)
        currentIndex = randomIndex
        Task {
            await play(track: playlist[randomIndex])
        }
    }
    
    /// 跳转到指定时间
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        #if DEBUG
        print("🎯 [seek] 请求跳转到: \(time)s, 当前 realtimePlaybackTime: \(realtimePlaybackTime)s")
        #endif
        // 标记正在 seek，防止旧时间回调导致歌词跳回
        isSeeking = true
        currentTime = time
        // 立即触发一次回调，让歌词立刻跳到正确位置
        onTimeUpdate?(time)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                #if DEBUG
                print("🎯 [seek] 完成(finished=\(finished)), realtimePlaybackTime: \(self?.realtimePlaybackTime ?? -1)s, 目标: \(time)s")
                #endif
                self?.isSeeking = false
            }
        }
        updateNowPlayingInfo()
    }
    
    /// 切换播放模式
    func togglePlayMode() {
        switch playMode {
        case .order:
            playMode = .random
        case .random:
            playMode = .repeatOne
        case .repeatOne:
            playMode = .order
        }
    }
    
    /// 设置播放列表并开始播放
    func setPlaylist(_ tracks: [Track], startAt index: Int) {
        playlist = tracks
        currentIndex = index
        if index < tracks.count {
            Task {
                await play(track: tracks[index])
            }
        }
    }
    
    /// 将歌曲添加到当前播放位置的下一首
    func playNext(track: Track) {
        if playlist.isEmpty {
            playlist = [track]
            currentIndex = 0
        } else {
            let insertIndex = currentIndex + 1
            if insertIndex >= playlist.count {
                playlist.append(track)
            } else {
                playlist.insert(track, at: insertIndex)
            }
        }
    }
    
    /// 将歌曲添加到播放列表末尾
    func addToQueue(track: Track) {
        playlist.append(track)
        // 如果当前没有播放，设置索引
        if currentTrack == nil && !playlist.isEmpty {
            currentIndex = playlist.count - 1
        }
    }
    
    // MARK: - 锁屏信息
    // 缓存锁屏封面以避免重复加载（限制最多缓存 10 个）
    private var nowPlayingArtworkCache: [String: MPMediaItemArtwork] = [:]
    private let maxArtworkCacheCount = 10
    
    private func updateNowPlayingInfo() {
        #if DEBUG
        print("📱 updateNowPlayingInfo 被调用, currentTrack: \(currentTrack?.name ?? "nil")")
        #endif
        
        var info = [String: Any]()
        
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.name
            info[MPMediaItemPropertyArtist] = track.artistName
            info[MPMediaItemPropertyAlbumTitle] = track.albumName
        }
        
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // 优化：使用缓存加载封面图片
        if let coverUrl = currentTrack?.coverUrl, let url = URL(string: coverUrl) {
            // 先检查锁屏封面缓存
            if let cachedArtwork = nowPlayingArtworkCache[coverUrl] {
                info[MPMediaItemPropertyArtwork] = cachedArtwork
            } else {
                // 异步加载封面（优先使用ImageCache）
                loadNowPlayingArtwork(from: url, coverUrl: coverUrl)
            }
        }

        // iOS 26+ (内部版本 iOS 19.0): 设置动态封面（仅在有缓存时设置）
        if #available(iOS 19.0, *), let track = currentTrack {
            // 只有在有预加载的动态封面时才尝试设置
            if getMasterUrlCached(for: track.id) != nil {
                setAnimatedArtwork(for: track, info: &info)
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - iOS 26+ 动态封面支持

    /// iOS 26+ (内部版本 iOS 19.0): 设置锁屏动态封面
    /// 使用 MPMediaItemAnimatedArtwork API 在锁屏显示动态专辑封面
    ///
    /// 当用户在锁屏点击封面时，系统会自动播放动态封面视频
    /// 类似 QQ音乐、Apple Music 的全屏动态封面效果
    @available(iOS 19.0, *)
    private func setAnimatedArtwork(for track: Track, info: inout [String: Any]) {
        // 检查平台支持的动态封面 keys
        let supportedKeys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys

        // 优先使用 3:4，如果不支持则尝试 1:1
        let animatedArtworkKey: String
        if supportedKeys.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork) {
            animatedArtworkKey = MPNowPlayingInfoProperty3x4AnimatedArtwork
        } else if supportedKeys.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork) {
            animatedArtworkKey = MPNowPlayingInfoProperty1x1AnimatedArtwork
        } else {
            return
        }

        // 获取预加载的动态封面 URL
        guard let videoUrlString = getMasterUrlCached(for: track.id) else {
            return
        }

        #if DEBUG
        print("🎬 设置动态封面: \(track.name)")
        #endif

        let trackId = track.id
        let coverUrl = track.coverUrl
        let remoteVideoUrlString = videoUrlString
        
        // 创建唯一的 artworkID
        let artworkID = "track_\(trackId)_animated"
        
        // 创建 MPMediaItemAnimatedArtwork
        let animatedArtwork = MPMediaItemAnimatedArtwork(
            artworkID: artworkID,
            previewImageRequestHandler: { [weak self] requestedSize, completion in
                #if DEBUG
                print("🖼️ 系统请求预览图, size: \(requestedSize)")
                #endif
                
                // 返回静态封面作为预览图
                guard let coverUrl = coverUrl,
                      let url = URL(string: coverUrl) else {
                    #if DEBUG
                    print(" 无封面 URL")
                    #endif
                    completion(nil)
                    return
                }
                
                // 异步加载并裁剪为请求的宽高比
                Task {
                    do {
                        // 下载原图
                        let (data, _) = try await URLSession.shared.data(from: url)
                        guard let originalImage = UIImage(data: data) else {
                            completion(nil)
                            return
                        }
                        
                        // 裁剪为请求的宽高比 (3:4)
                        let croppedImage = self?.cropImageToAspectRatio(
                            originalImage,
                            targetWidth: requestedSize.width,
                            targetHeight: requestedSize.height
                        )
                        
                        #if DEBUG
                        print("✅ 预览图加载成功")
                        #endif
                        completion(croppedImage)
                    } catch {
                        #if DEBUG
                        print(" 预览图加载失败: \(error.localizedDescription)")
                        #endif
                        completion(nil)
                    }
                }
            },
            videoAssetFileURLRequestHandler: { [weak self] requestedSize, completion in
                #if DEBUG
                print("🎥 系统请求动态封面视频, size: \(requestedSize), trackId: \(trackId)")
                print("🎥 远程 URL: \(remoteVideoUrlString.suffix(60))")
                #endif
                
                guard let self = self else {
                    #if DEBUG
                    print("❌ self 已释放")
                    #endif
                    completion(nil)
                    return
                }
                
                // 检查是否已下载到本地（锁屏时应该已经预下载完成）
                if let localURL = self.getLocalFileCached(for: trackId) {
                    #if DEBUG
                    print("✅ 找到本地缓存记录: \(localURL.lastPathComponent)")
                    #endif

                    // 验证文件是否存在
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        #if DEBUG
                        print("✅ 文件存在，返回给系统")
                        #endif
                        completion(localURL)
                    } else {
                        #if DEBUG
                        print("⚠️ 缓存记录存在但文件不存在，清除缓存并重新下载")
                        #endif
                        DynamicCoverCache.shared.clearLocalFile(for: trackId)
                        self.downloadAndCacheVideo(remoteVideoUrlString, trackId, completion)
                    }
                    return
                }

                #if DEBUG
                print("📥 未找到本地缓存，开始下载动态封面视频...")
                #endif
                
                // 异步下载视频到本地
                self.downloadAndCacheVideo(remoteVideoUrlString, trackId, completion)
            }
        )
        
        // 设置动态封面
        info[animatedArtworkKey] = animatedArtwork
        
        #if DEBUG
        print("✅ 已设置锁屏动态封面到 NowPlayingInfo: \(track.name)")
        #endif
    }
    
    /// 下载并缓存视频的辅助方法（用于 videoAssetFileURLRequestHandler）
    @available(iOS 19.0, *)
    private func downloadAndCacheVideo(_ remoteVideoUrlString: String, _ trackId: Int, _ completion: @escaping (URL?) -> Void) {
        #if DEBUG
        print("📥 downloadAndCacheVideo 开始, trackId: \(trackId)")
        #endif
        Task {
            do {
                let localURL = try await self.downloadAnimatedArtwork(
                    from: remoteVideoUrlString,
                    trackId: trackId
                )
                await MainActor.run {
                    self.cacheLocalFile(localURL, for: trackId)
                }
                #if DEBUG
                print("✅ 动态封面视频已就绪: \(localURL.lastPathComponent)")
                #endif
                completion(localURL)
            } catch {
                #if DEBUG
                print("❌ 动态封面下载失败: \(error)")
                #endif
                completion(nil)
            }
        }
    }
    
    /// 下载动态封面视频到本地（转换为 MP4 格式）
    @available(iOS 19.0, *)
    private func downloadAnimatedArtwork(from urlString: String, trackId: Int) async throws -> URL {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw AudioPlayerError.playbackFailed("无法获取缓存目录")
        }
        let animatedArtworkDir = cacheDir.appendingPathComponent("AnimatedArtwork", isDirectory: true)
        try FileManager.default.createDirectory(at: animatedArtworkDir, withIntermediateDirectories: true)
        
        let mp4URL = animatedArtworkDir.appendingPathComponent("track_\(trackId).mp4")
        let tsURL = animatedArtworkDir.appendingPathComponent("track_\(trackId).ts")
        
        // 清理旧的 .ts 文件缓存（已不再支持）
        if FileManager.default.fileExists(atPath: tsURL.path) {
            try? FileManager.default.removeItem(at: tsURL)
        }
        
        // 检查 MP4 缓存
        if FileManager.default.fileExists(atPath: mp4URL.path) {
            // 兜底校验：历史版本如果误选到 HLS I-FRAME trick-play 流，转出来的 MP4 会像“一帧一帧”的幻灯片。
            // 这里通过 nominalFrameRate 做一个轻量校验，异常就删掉重下。
            do {
                let asset = AVURLAsset(url: mp4URL)
                let tracks = try await asset.load(.tracks)
                let fps = tracks.first(where: { $0.mediaType == .video })?.nominalFrameRate ?? 0
                if fps >= 10 {
                    #if DEBUG
                    print("✅ 动态封面使用缓存: \(mp4URL.lastPathComponent) (fps≈\(String(format: "%.1f", fps)))")
                    #endif
                    return mp4URL
                } else {
                    try FileManager.default.removeItem(at: mp4URL)
                    #if DEBUG
                    print("⚠️ 动态封面缓存疑似低帧率/异常，已删除重下: \(mp4URL.lastPathComponent) (fps≈\(String(format: "%.1f", fps)))")
                    #endif
                }
            } catch {
                try? FileManager.default.removeItem(at: mp4URL)
                #if DEBUG
                print("⚠️ 动态封面缓存校验失败，已删除重下: \(mp4URL.lastPathComponent)")
                #endif
            }
        }
        
        // HLS 流：使用 AVAssetExportSession 转换为 MP4
        if urlString.contains(".m3u8") {
            return try await exportHLSToMP4(hlsUrl: urlString, outputUrl: mp4URL)
        } else {
            // 普通视频文件：直接下载
            guard let remoteURL = URL(string: urlString) else {
                throw AudioPlayerError.invalidURL
            }
            let (tempURL, _) = try await AppleMusicNetworkSession.shared.session.download(from: remoteURL)
            if FileManager.default.fileExists(atPath: mp4URL.path) {
                try FileManager.default.removeItem(at: mp4URL)
            }
            try FileManager.default.moveItem(at: tempURL, to: mp4URL)
            return mp4URL
        }
    }
    
    /// 下载 HLS 的第一个 TS 分片并转码为 MP4
    @available(iOS 19.0, *)
    private func exportHLSToMP4(hlsUrl: String, outputUrl: URL) async throws -> URL {
        #if DEBUG
        print("🎥 exportHLSToMP4 开始, URL: \(hlsUrl)")
        #endif

        // 限制最大分辨率：锁屏/播放器都不需要拉到最高档，否则更容易掉帧。
        // 同时避免误选 I-FRAME trick-play（已在 HLSParser 里过滤）。
        let maxPixels = 1080 * 1440
        
        // Step 1: 获取变体 URL
        var variantUrl: String?
        
        if let cached = HLSVariantCache.shared.getVariant(for: hlsUrl) {
            #if DEBUG
            print("🎥 使用缓存的变体 URL: \(cached.suffix(80))")
            #endif
            variantUrl = cached
        } else {
            guard let masterURL = URL(string: hlsUrl) else {
                #if DEBUG
                print("❌ 无效的 HLS URL")
                #endif
                throw AudioPlayerError.invalidURL
            }
            #if DEBUG
            print("🎥 下载 master m3u8: \(masterURL)")
            #endif
            let (masterData, _) = try await AppleMusicNetworkSession.shared.session.data(from: masterURL)
            #if DEBUG
            print("🎥 master m3u8 下载完成, 大小: \(masterData.count) bytes")
            #endif
            guard let masterText = String(data: masterData, encoding: .utf8) else {
                throw AudioPlayerError.playbackFailed("无法解析 HLS")
            }
            variantUrl = HLSParser.shared.selectVariant(
                from: masterText,
                baseUrl: hlsUrl,
                strategy: .preferAspectRatio(width: 3, height: 4, maxPixels: maxPixels)
            )
            if let url = variantUrl {
                HLSVariantCache.shared.setVariant(url, for: hlsUrl)
            } else {
                // 某些情况下传入的 hlsUrl 本身就是变体 m3u8（没有 #EXT-X-STREAM-INF），直接按变体处理
                variantUrl = hlsUrl
            }
        }

        guard var variantUrlString = variantUrl, var variantURL = URL(string: variantUrlString) else {
            throw AudioPlayerError.playbackFailed("无法获取 HLS 变体")
        }

        // Step 2: 下载并解析变体 m3u8（兼容嵌套 master -> variant）
        var variantText: String = ""
        for attempt in 0..<2 {
            #if DEBUG
            print("🎥 下载 m3u8(\(attempt + 1)): \(variantURL)")
            #endif
            let (variantData, _) = try await AppleMusicNetworkSession.shared.session.data(from: variantURL)
            #if DEBUG
            print("🎥 m3u8 下载完成, 大小: \(variantData.count) bytes")
            #endif
            guard let text = String(data: variantData, encoding: .utf8) else {
                throw AudioPlayerError.playbackFailed("无法解析变体 m3u8")
            }
            variantText = text

            // 如果拿到的仍是 master m3u8（含 #EXT-X-STREAM-INF），继续挑一次变体
            if variantText.contains("#EXT-X-STREAM-INF:"),
               let nested = HLSParser.shared.selectVariant(
                from: variantText,
                baseUrl: variantUrlString,
                strategy: .preferAspectRatio(width: 3, height: 4, maxPixels: maxPixels)
               ),
               nested != variantUrlString,
               let nestedURL = URL(string: nested) {
                variantUrlString = nested
                variantURL = nestedURL
                continue
            }
            break
        }

        // 更新变体缓存（用于后续锁屏/复用）
        HLSVariantCache.shared.setVariant(variantUrlString, for: hlsUrl)
        
        // Step 3: 检查是否为 BYTERANGE 模式（直接引用 MP4 文件）
        if let mp4Url = extractMP4Url(from: variantText, baseUrl: variantUrlString) {
            #if DEBUG
            print("🎥 发现 BYTERANGE 模式，直接下载 MP4: \(mp4Url)")
            #endif
            
            // 直接下载 MP4 文件
            let (tempURL, _) = try await AppleMusicNetworkSession.shared.session.download(from: mp4Url)
            
            // 移动到输出位置
            if FileManager.default.fileExists(atPath: outputUrl.path) {
                try FileManager.default.removeItem(at: outputUrl)
            }
            try FileManager.default.moveItem(at: tempURL, to: outputUrl)
            
            #if DEBUG
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputUrl.path)[.size] as? Int) ?? 0
            print("✅ 动态封面已下载: \(outputUrl.lastPathComponent) (\(fileSize / 1024)KB)")
            #endif
            
            return outputUrl
        }
        
        // Step 4: 传统 TS 分片模式
        let tsURLs = extractTSUrls(from: variantText, baseUrl: variantUrlString)
        guard !tsURLs.isEmpty else {
            throw AudioPlayerError.playbackFailed("未找到可用的媒体分片")
        }
        
        #if DEBUG
        print("🎬 找到 \(tsURLs.count) 个 TS 分片，下载全部并合并...")
        #endif
        
        // 下载所有 TS 分片并合并
        var allTSData = Data()
        for (index, tsURL) in tsURLs.enumerated() {
            let (tsData, _) = try await AppleMusicNetworkSession.shared.session.data(from: tsURL)
            allTSData.append(tsData)
            #if DEBUG
            if index == 0 || index == tsURLs.count - 1 {
                print("📥 下载 TS[\(index)]: \(tsData.count / 1024)KB")
            }
            #endif
        }
        
        // 保存为临时 TS 文件
        let tempTSUrl = outputUrl.deletingLastPathComponent().appendingPathComponent("temp_\(UUID().uuidString).ts")
        try allTSData.write(to: tempTSUrl)
        
        defer {
            try? FileManager.default.removeItem(at: tempTSUrl)
        }
        
        // 使用 AVAssetWriter 转码为 MP4
        let mp4Url = try await convertTSToMP4(tsUrl: tempTSUrl, outputUrl: outputUrl)
        
        #if DEBUG
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: mp4Url.path)[.size] as? Int) ?? 0
        print("✅ 动态封面已转码: \(mp4Url.lastPathComponent) (\(fileSize / 1024)KB)")
        #endif
        
        return mp4Url
    }
    
    /// 从 m3u8 内容提取 MP4 URL（BYTERANGE 模式）
    private func extractMP4Url(from m3u8Content: String, baseUrl: String) -> URL? {
        guard let baseURL = URL(string: baseUrl) else { return nil }

        // 查找 EXT-X-MAP 或直接引用的 .mp4 文件
        for line in m3u8Content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // EXT-X-MAP:URI="xxx.mp4"
            if trimmed.hasPrefix("#EXT-X-MAP:") {
                if let uriRange = trimmed.range(of: "URI=\""),
                   let endRange = trimmed.range(of: "\"", range: uriRange.upperBound..<trimmed.endIndex) {
                    let uri = String(trimmed[uriRange.upperBound..<endRange.lowerBound])
                    if uri.hasSuffix(".mp4") {
                        return URL(string: uri, relativeTo: baseURL)?.absoluteURL
                    }
                }
            }
            
            // 直接引用的 .mp4 文件
            if !trimmed.hasPrefix("#") && trimmed.hasSuffix(".mp4") {
                return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
            }
        }
        
        return nil
    }
    
    /// 从 m3u8 内容提取 TS URL 列表
    private func extractTSUrls(from m3u8Content: String, baseUrl: String) -> [URL] {
        guard let baseURL = URL(string: baseUrl) else { return [] }
        var tsURLs: [URL] = []
        
        for line in m3u8Content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            // 这是一个 TS 分片 URL
            if let tsURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
                tsURLs.append(tsURL)
            }
        }
        
        return tsURLs
    }
    
    /// 使用 AVAssetReader/Writer 将 TS 转码为 MP4
    private func convertTSToMP4(tsUrl: URL, outputUrl: URL) async throws -> URL {
        let asset = AVURLAsset(url: tsUrl)
        
        // 加载 tracks
        let tracks = try await asset.load(.tracks)
        guard !tracks.isEmpty else {
            throw AudioPlayerError.playbackFailed("TS 文件无有效轨道")
        }
        
        // 删除已存在的输出文件
        if FileManager.default.fileExists(atPath: outputUrl.path) {
            try FileManager.default.removeItem(at: outputUrl)
        }
        
        // 创建 AssetReader
        let reader = try AVAssetReader(asset: asset)
        
        // 创建 AssetWriter
        let writer = try AVAssetWriter(outputURL: outputUrl, fileType: .mp4)
        
        // 设置视频轨道
        if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            
            let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
            
            if reader.canAdd(readerOutput) {
                reader.add(readerOutput)
            }
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: naturalSize.width,
                AVVideoHeightKey: naturalSize.height
            ]
            
            let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            writerInput.transform = transform
            writerInput.expectsMediaDataInRealTime = false
            
            if writer.canAdd(writerInput) {
                writer.add(writerInput)
            }
        }
        
        // 开始读写
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        // 处理视频数据
        return try await withCheckedThrowingContinuation { continuation in
            let videoInput = writer.inputs.first { $0.mediaType == .video }
            let videoOutput = reader.outputs.first { $0.mediaType == .video }
            
            guard let input = videoInput, let output = videoOutput else {
                continuation.resume(throwing: AudioPlayerError.playbackFailed("无法创建视频输入/输出"))
                return
            }
            
            let queue = DispatchQueue(label: "com.neteasemusic.videoconvert")
            
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if let sampleBuffer = output.copyNextSampleBuffer() {
                        input.append(sampleBuffer)
                    } else {
                        input.markAsFinished()
                        
                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume(returning: outputUrl)
                            } else {
                                continuation.resume(throwing: AudioPlayerError.playbackFailed("写入失败: \(writer.error?.localizedDescription ?? "未知错误")"))
                            }
                        }
                        return
                    }
                }
            }
        }
    }
    
    // MARK: - 缓存访问方法（使用 DynamicCoverCache）

    /// 获取歌曲的 master m3u8 URL
    private func getMasterUrlCached(for trackId: Int) -> String? {
        return DynamicCoverCache.shared.getMasterUrl(for: trackId)
    }

    /// 缓存歌曲的 master m3u8 URL
    private func cacheMasterUrl(_ url: String, for trackId: Int) {
        DynamicCoverCache.shared.cacheMasterUrl(url, for: trackId)
    }

    /// 获取歌曲的本地文件 URL
    private func getLocalFileCached(for trackId: Int) -> URL? {
        return DynamicCoverCache.shared.getLocalFile(for: trackId)
    }

    /// 缓存歌曲的本地文件 URL
    private func cacheLocalFile(_ fileUrl: URL, for trackId: Int) {
        DynamicCoverCache.shared.cacheLocalFile(fileUrl, for: trackId)
    }

    /// 裁剪图片为指定宽高比
    private func cropImageToAspectRatio(_ image: UIImage, targetWidth: CGFloat, targetHeight: CGFloat) -> UIImage? {
        let targetAspectRatio = targetWidth / targetHeight  // 3:4 = 0.75
        let imageAspectRatio = image.size.width / image.size.height
        
        var cropRect: CGRect
        
        if imageAspectRatio > targetAspectRatio {
            // 图片过宽，裁剪左右
            let newWidth = image.size.height * targetAspectRatio
            let xOffset = (image.size.width - newWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: image.size.height)
        } else {
            // 图片过高，裁剪上下
            let newHeight = image.size.width / targetAspectRatio
            let yOffset = (image.size.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: image.size.width, height: newHeight)
        }
        
        // 执行裁剪
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        // 缩放到目标尺寸
        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        croppedImage.draw(in: CGRect(origin: .zero, size: targetSize))
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return finalImage
    }
    
    /// 异步加载锁屏封面（优化：使用ImageCache，避免阻塞主线程）
    private func loadNowPlayingArtwork(from url: URL, coverUrl: String) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            // 优先从 ImageCache 获取
            let targetSize = CGSize(width: 300, height: 300)
            if let cachedImage = ImageCache.shared.getFromMemory(url, targetSize: targetSize) {
                await self.setNowPlayingArtwork(cachedImage, for: coverUrl)
                return
            }
            
            // 尝试从磁盘缓存获取
            if let diskImage = ImageCache.shared.getFromDisk(url, targetSize: targetSize) {
                await self.setNowPlayingArtwork(diskImage, for: coverUrl)
                return
            }
            
            // 网络加载（后台线程）
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                // 下采样优化
                if let image = ImageCache.shared.downsample(data: data, to: targetSize) {
                    // 保存到缓存
                    ImageCache.shared.saveToMemory(image, for: url, targetSize: targetSize)
                    ImageCache.shared.saveToDisk(data, for: url)
                    await self.setNowPlayingArtwork(image, for: coverUrl)
                }
            } catch {
                #if DEBUG
                print(" 锁屏封面加载失败: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// 设置锁屏封面（主线程）
    @MainActor
    private func setNowPlayingArtwork(_ image: UIImage, for coverUrl: String) {
        // 限制缓存大小，超出时清理最早的
        if nowPlayingArtworkCache.count >= maxArtworkCacheCount {
            if let firstKey = nowPlayingArtworkCache.keys.first {
                nowPlayingArtworkCache.removeValue(forKey: firstKey)
            }
        }

        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        nowPlayingArtworkCache[coverUrl] = artwork

        var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        updatedInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
    }
    
    // MARK: - 获取歌曲URL（多级缓存）
    private func getSongUrl(id: Int) async throws -> String {
        // 先尝试普通音源
        if let url = try? await getNeteaseUrl(id: id) {
            return url
        }
        // 回退：尝试网易云官方接口（支持云盘歌曲）
        return try await getCloudDiskSongUrl(id: id)
    }
    
    // 获取云盘歌曲URL（通过官方API带cookie）
    private func getCloudDiskSongUrl(id: Int) async throws -> String {
        let quality = sourceConfig.quality
        let br: Int
        switch quality {
        case .standard: br = 128000
        case .exhigh: br = 320000
        default: br = 999000
        }
        
        guard let url = URL(string: "\(APIConfig.baseURL)/song/url?id=\(id)&br=\(br)") else {
            throw AudioPlayerError.invalidURL
        }
        
        let (data, _) = try await NetworkService.shared.requestWithCookie(url: url, method: "GET")
        let response = try JSONDecoder().decode(SongUrlResponse.self, from: data)
        
        if let songUrl = response.data?.first?.url, !songUrl.isEmpty {
            #if DEBUG
            print("☁️ 云盘歌曲URL获取成功: \(id)")
            #endif
            preloadedURLs[id] = songUrl
            songCache.cacheUrl(songId: id, url: songUrl, quality: quality.rawValue)
            return songUrl
        }
        
        throw AudioPlayerError.noAvailableSource
    }
    
    // 获取网易云音乐URL
    private func getNeteaseUrl(id: Int) async throws -> String {
        let quality = sourceConfig.quality.rawValue
        
        // 1. 先检查内存预加载缓存
        if let cachedUrl = preloadedURLs[id] {
            #if DEBUG
            print(" 使用预加载缓存: \(id)")
            #endif
            return cachedUrl
        }
        
        // 2. 检查持久化缓存
        if let cachedUrl = songCache.getCachedUrl(songId: id, quality: quality) {
            preloadedURLs[id] = cachedUrl
            return cachedUrl
        }
        
        // 3. 网络请求
        #if DEBUG
        print(" 请求音质: \(quality)")
        #endif

        if let resultUrl = try await KumoneMusicClient.shared.songURL(id: id, level: quality),
           !resultUrl.isEmpty {
            await MainActor.run {
                self.actualQuality = quality
            }
            preloadedURLs[id] = resultUrl
            songCache.cacheUrl(songId: id, url: resultUrl, quality: quality)
            return resultUrl
        }

        throw AudioPlayerError.noAvailableSource
    }
    
    // MARK: - 预加载（批量预加载优化）
    
    /// 批量预加载后续歌曲（默认预加载3首）
    private func batchPreloadNextTracks(count: Int = 3) {
        guard !playlist.isEmpty else { return }
        
        for offset in 1...count {
            let nextIndex = (currentIndex + offset) % playlist.count
            let nextTrack = playlist[nextIndex]
            preloadTrack(nextTrack)
        }
    }
    
    /// 预加载单首歌曲
    private func preloadTrack(_ track: Track) {
        // 已经预加载过则跳过
        if preloadedURLs[track.id] != nil { return }
        preloadNeteaseTrack(track)
    }
    
    private func preloadNeteaseTrack(_ track: Track) {
        let quality = sourceConfig.quality.rawValue

        // 检查持久化缓存
        if let cachedUrl = songCache.getCachedUrl(songId: track.id, quality: quality) {
            preloadedURLs[track.id] = cachedUrl
            #if DEBUG
            print(" 预加载(缓存命中): \(track.name)")
            #endif
            return
        }

        // 清理过多的预加载缓存（保留播放列表中的歌曲）
        if preloadedURLs.count >= maxPreloadCacheCount {
            let playlistIds = Set(playlist.map { $0.id })
            let keysToRemove = preloadedURLs.keys.filter { !playlistIds.contains($0) }
            for key in keysToRemove.prefix(preloadedURLs.count - maxPreloadCacheCount / 2) {
                preloadedURLs.removeValue(forKey: key)
            }
        }

        // 取消已有的预加载任务
        preloadTasks[track.id]?.cancel()
        
        // 创建新的预加载任务
        let task = Task(priority: .utility) { [weak self] in
            guard let self = self else { return }

            do {
                if Task.isCancelled { return }

                let resultUrl = try await KumoneMusicClient.shared.songURL(id: track.id, level: quality)

                if Task.isCancelled { return }

                if let resultUrl, !resultUrl.isEmpty {
                    await MainActor.run {
                        self.preloadedURLs[track.id] = resultUrl
                    }
                    self.songCache.cacheUrl(songId: track.id, url: resultUrl, quality: quality)
                    
                    #if DEBUG
                    print(" 预加载完成: \(track.name)")
                    #endif
                }
            } catch {
                if !Task.isCancelled {
                    #if DEBUG
                    print(" 预加载失败: \(track.name) - \(error.localizedDescription)")
                    #endif
                }
            }
            
            await MainActor.run {
                self.preloadTasks.removeValue(forKey: track.id)
            }
        }
        
        preloadTasks[track.id] = task
    }
    
    /// 预加载单首（兼容旧方法）
    private func preloadNextTrack() {
        batchPreloadNextTracks(count: 1)
    }
    
    // MARK: - 动态封面预加载
    
    /// 预加载动态封面（播放歌曲时调用）
    /// 包括：1) 获取 Apple Music 动态封面 URL  2) 预加载 HLS 变体  3) iOS 19+ 下载本地文件用于锁屏
    private func preloadDynamicCover(for track: Track) {
        let trackId = track.id
        
        // 检查是否已缓存 master URL
        if let cachedUrl = getMasterUrlCached(for: trackId) {
            // 已有 URL，检查是否需要下载本地文件（iOS 19+）
            if #available(iOS 19.0, *), getLocalFileCached(for: trackId) == nil {
                downloadLocalFileIfNeeded(url: cachedUrl, trackId: trackId)
            }
            return
        }
        
        // 取消之前的预加载任务
        dynamicCoverTask?.cancel()
        
        dynamicCoverTask = Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            do {
                #if DEBUG
                print("🎬 预加载动态封面: \(track.name)")
                #endif
                
                // Step 1: 获取 Apple Music 动态封面 URL
                guard let videoUrl = try await self.musicService.getAppleMusicAnimatedCover(
                    songName: track.name,
                    artistName: track.artistName
                ) else {
                    #if DEBUG
                    print("⚠️ 未找到动态封面: \(track.name)")
                    #endif
                    return
                }
                
                // Step 2: 缓存 URL 并预加载 HLS 变体
                await MainActor.run {
                    self.cacheMasterUrl(videoUrl, for: trackId)
                }
                HLSVariantCache.shared.preload(masterUrl: videoUrl)
                
                // Step 3: 更新锁屏信息
                await MainActor.run {
                    if self.currentTrack?.id == trackId {
                        self.updateNowPlayingInfo()
                    }
                }
                
                // Step 4: iOS 19+ 下载本地文件用于锁屏
                if #available(iOS 19.0, *) {
                    await self.downloadLocalFileForLockScreen(url: videoUrl, trackId: trackId)
                }
                
            } catch {
                if !Task.isCancelled {
                    #if DEBUG
                    print("❌ 动态封面预加载失败: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }
    
    /// iOS 19+ 下载动态封面本地文件（用于锁屏播放）
    @available(iOS 19.0, *)
    private func downloadLocalFileForLockScreen(url: String, trackId: Int) async {
        do {
            let localURL = try await downloadAnimatedArtwork(from: url, trackId: trackId)
            
            await MainActor.run {
                self.cacheLocalFile(localURL, for: trackId)
                if self.currentTrack?.id == trackId {
                    self.updateNowPlayingInfo()
                }
            }
            
            #if DEBUG
            print("✅ 锁屏动态封面已下载: \(localURL.lastPathComponent)")
            #endif
        } catch {
            #if DEBUG
            print("❌ 锁屏动态封面下载失败: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// 按需下载本地文件（当已缓存 URL 但未下载本地文件时）
    @available(iOS 19.0, *)
    private func downloadLocalFileIfNeeded(url: String, trackId: Int) {
        Task(priority: .utility) { [weak self] in
            await self?.downloadLocalFileForLockScreen(url: url, trackId: trackId)
        }
    }
    
    /// 获取预加载的动态封面URL
    func getDynamicCoverURL(for trackId: Int) -> String? {
        return getMasterUrlCached(for: trackId)
    }

    /// 缓存动态封面 URL（仅缓存，不触发下载）
    /// 下载逻辑统一由 `preloadDynamicCover` 方法负责
    func cacheDynamicCoverURL(_ url: String, for trackId: Int) {
        cacheMasterUrl(url, for: trackId)
        
        #if DEBUG
        print("💾 缓存动态封面 URL: trackId=\(trackId)")
        #endif
    }

    /// 清除预加载缓存
    func clearPreloadCache() {
        // 取消所有预加载任务
        for (_, task) in preloadTasks {
            task.cancel()
        }
        preloadTasks.removeAll()
        preloadedURLs.removeAll()
        dynamicCoverTask?.cancel()
        
        // 清理动态封面缓存
        DynamicCoverCache.shared.clearAll()
        
        #if DEBUG
        print("🗑️ 预加载缓存已清除")
        #endif
    }
    
    /// 取消所有预加载任务
    func cancelAllPreloads() {
        for (_, task) in preloadTasks {
            task.cancel()
        }
        preloadTasks.removeAll()
    }
    
    deinit {
        stopLyricsDisplayLink()
        cleanupObservers()
        cancelAllPreloads()
        dynamicCoverTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 辅助方法
    
    /// 获取缓冲进度（0-1）
    var bufferProgress: Double {
        if case .buffering(let progress) = bufferingState {
            return progress
        }
        return bufferingState == .ready ? 1.0 : 0.0
    }
    
    /// 重置错误状态
    func resetError() {
        lastError = nil
        bufferingState = .idle
    }
    
    /// 保存缓存到磁盘（App 进入后台时调用）
    func saveCacheToDisk() {
        songCache.saveToDisk()
    }

    // MARK: - Widget 同步

    /// 更新歌词到 Widget（由 PlayerView 调用）
    func updateLyricsForWidget(currentLyric: String, nextLyric: String) {
        currentLyricText = currentLyric
        nextLyricText = nextLyric

        let progress = duration > 0 ? Float(currentTime / duration) : 0
        widgetService.updateLyrics(
            currentLyric: currentLyric,
            nextLyric: nextLyric,
            progress: progress,
            currentTime: currentTime
        )

        // 节流：限制 Widget 刷新频率（系统有限流）
        let now = Date()
        if now.timeIntervalSince(lastWidgetRefreshTime) >= widgetRefreshInterval {
            lastWidgetRefreshTime = now
            WidgetCenter.shared.reloadTimelines(ofKind: "LyricHomeWidget")
        }
    }

    /// 同步完整播放状态到 Widget
    func syncWidgetPlaybackState(coverImage: UIImage? = nil) {
        guard let track = currentTrack else {
            widgetService.clearPlaybackData()
            WidgetCenter.shared.reloadTimelines(ofKind: "LyricHomeWidget")
            return
        }

        let progress = duration > 0 ? Float(currentTime / duration) : 0

        widgetService.updatePlaybackState(
            songName: track.name,
            artistName: track.artistName,
            albumName: track.albumName,
            coverImage: coverImage,
            currentLyric: currentLyricText,
            nextLyric: nextLyricText,
            isPlaying: isPlaying,
            progress: progress,
            currentTime: currentTime,
            duration: duration
        )

        // 触发 Widget 刷新
        WidgetCenter.shared.reloadTimelines(ofKind: "LyricHomeWidget")
    }

    /// 仅同步播放状态
    private func syncWidgetPlayingState() {
        widgetService.updatePlayingState(isPlaying: isPlaying)
        WidgetCenter.shared.reloadTimelines(ofKind: "LyricHomeWidget")
    }

    /// 异步加载封面并同步到 Widget
    private func syncWidgetWithCover(track: Track) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            var coverImage: UIImage? = nil

            // 加载封面图片
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    coverImage = UIImage(data: data)
                } catch {
                    #if DEBUG
                    print("⚠️ Widget 封面加载失败: \(error.localizedDescription)")
                    #endif
                }
            }

            // 同步到 Widget
            await MainActor.run {
                self.syncWidgetPlaybackState(coverImage: coverImage)
            }
        }
    }
}
