import Foundation
import UIKit

// MARK: - 下载任务状态
enum DownloadStatus: Equatable {
    case idle
    case waiting
    case downloading(progress: Double)
    case completed
    case failed(String)
    
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

// MARK: - 下载任务
struct DownloadTask: Identifiable {
    let id: Int  // Track ID
    let track: Track
    var status: DownloadStatus
    var progress: Double
    var localURL: URL?
}

// MARK: - 歌曲下载服务
@MainActor
final class SongDownloadService: ObservableObject {
    static let shared = SongDownloadService()
    
    // MARK: - Published
    @Published var downloadTasks: [Int: DownloadTask] = [:]
    @Published var downloadQueue: [Int] = []  // 下载队列
    
    // MARK: - 配置
    private let maxConcurrentDownloads = 3
    private var activeDownloads = 0
    
    private let sourceConfig = MusicSourceConfig.shared
    private let localMusicService = LocalMusicService.shared
    
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600  // 10分钟超时
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    // MARK: - 公开 API
    
    /// 检查歌曲是否已下载
    func isDownloaded(trackId: Int) -> Bool {
        return localMusicService.localTracks.contains { $0.sourceTrackId == trackId }
    }
    
    /// 获取下载状态
    func getStatus(trackId: Int) -> DownloadStatus {
        return downloadTasks[trackId]?.status ?? .idle
    }
    
    /// 下载歌曲
    func download(track: Track) {
        // 检查是否已下载
        if isDownloaded(trackId: track.id) {
            #if DEBUG
            print("⚠️ 歌曲已下载: \(track.name)")
            #endif
            return
        }
        
        // 检查是否已在下载队列
        if downloadTasks[track.id] != nil {
            #if DEBUG
            print("⚠️ 歌曲已在下载队列: \(track.name)")
            #endif
            return
        }
        
        // 创建下载任务
        let task = DownloadTask(
            id: track.id,
            track: track,
            status: .waiting,
            progress: 0
        )
        downloadTasks[track.id] = task
        downloadQueue.append(track.id)
        
        #if DEBUG
        print("📥 添加到下载队列: \(track.name)")
        #endif
        
        // 开始处理队列
        processQueue()
    }
    
    /// 批量下载
    func downloadBatch(tracks: [Track]) {
        for track in tracks {
            download(track: track)
        }
    }
    
    /// 取消下载
    func cancel(trackId: Int) {
        downloadTasks.removeValue(forKey: trackId)
        downloadQueue.removeAll { $0 == trackId }
        
        #if DEBUG
        print("❌ 取消下载: \(trackId)")
        #endif
    }
    
    /// 重试下载
    func retry(track: Track) {
        downloadTasks.removeValue(forKey: track.id)
        download(track: track)
    }
    
    // MARK: - 私有方法
    
    /// 处理下载队列
    private func processQueue() {
        guard activeDownloads < maxConcurrentDownloads else { return }
        
        // 找到下一个等待中的任务
        guard let trackId = downloadQueue.first(where: { id in
            if let task = downloadTasks[id] {
                return task.status == .waiting
            }
            return false
        }) else {
            return
        }
        
        guard var task = downloadTasks[trackId] else { return }
        
        task.status = .downloading(progress: 0)
        downloadTasks[trackId] = task
        activeDownloads += 1
        
        // 开始下载
        Task {
            await startDownload(task: task)
        }
    }
    
    /// 开始下载任务
    private func startDownload(task: DownloadTask) async {
        let track = task.track
        
        do {
            let quality = sourceConfig.quality.rawValue

            #if DEBUG
            print("📥 开始下载: \(track.name)")
            #endif

            updateProgress(trackId: track.id, progress: 0.05)

            guard let audioUrlString = try await KumoneMusicClient.shared.songURL(id: track.id, level: quality),
                  !audioUrlString.isEmpty,
                  let audioUrl = URL(string: audioUrlString) else {
                throw DownloadError.noAudioURL
            }
            
            #if DEBUG
            print("📥 音频URL: \(audioUrlString.prefix(80))...")
            #endif
            
            updateProgress(trackId: track.id, progress: 0.1)
            
            // 2. 下载音频文件
            var request = URLRequest(url: audioUrl)
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com", forHTTPHeaderField: "Origin")
            
            let (tempURL, response) = try await urlSession.download(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw DownloadError.downloadFailed
            }
            
            updateProgress(trackId: track.id, progress: 0.7)
            
            // 3. 确定文件扩展名
            let fileExtension = getFileExtension(from: httpResponse, url: audioUrl)
            
            // 4. 下载封面图片
            var coverData: Data?
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                coverData = try? await downloadCoverImage(from: url)
            }
            
            updateProgress(trackId: track.id, progress: 0.85)
            
            // 5. 保存到本地音乐库
            let localTrack = try await localMusicService.saveDownloadedTrack(
                tempFileURL: tempURL,
                track: track,
                fileExtension: fileExtension,
                coverData: coverData
            )
            
            updateProgress(trackId: track.id, progress: 1.0)
            
            // 更新状态
            await MainActor.run {
                var updatedTask = downloadTasks[track.id]
                updatedTask?.status = .completed
                updatedTask?.localURL = localTrack.fileURL
                downloadTasks[track.id] = updatedTask
                
                // 从队列移除
                downloadQueue.removeAll { $0 == track.id }
                activeDownloads -= 1
            }
            
            #if DEBUG
            print("✅ 下载完成: \(track.name)")
            #endif
            
            // 继续处理队列
            await MainActor.run {
                processQueue()
            }
            
        } catch {
            await MainActor.run {
                var updatedTask = downloadTasks[track.id]
                updatedTask?.status = .failed(error.localizedDescription)
                downloadTasks[track.id] = updatedTask
                
                downloadQueue.removeAll { $0 == track.id }
                activeDownloads -= 1
                
                processQueue()
            }
            
            #if DEBUG
            print("❌ 下载失败: \(track.name) - \(error.localizedDescription)")
            #endif
        }
    }
    
    /// 更新下载进度
    private func updateProgress(trackId: Int, progress: Double) {
        Task { @MainActor in
            if var task = downloadTasks[trackId] {
                task.progress = progress
                task.status = .downloading(progress: progress)
                downloadTasks[trackId] = task
            }
        }
    }
    
    /// 下载封面图片
    private func downloadCoverImage(from url: URL) async throws -> Data {
        let (data, _) = try await urlSession.data(from: url)
        return data
    }
    
    /// 根据响应确定文件扩展名
    private func getFileExtension(from response: HTTPURLResponse, url: URL) -> String {
        let urlPath = url.path.lowercased()
        
        if urlPath.contains(".flac") { return "flac" }
        if urlPath.contains(".m4a") { return "m4a" }
        if urlPath.contains(".mp3") { return "mp3" }
        if urlPath.contains(".aac") { return "m4a" }
        if urlPath.contains(".ogg") { return "ogg" }
        if urlPath.contains(".wav") { return "wav" }
        
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
            if contentType.contains("audio/flac") { return "flac" }
            if contentType.contains("audio/mp4") || contentType.contains("audio/aac") { return "m4a" }
            if contentType.contains("audio/ogg") { return "ogg" }
            if contentType.contains("audio/wav") { return "wav" }
            if contentType.contains("audio/mpeg") { return "mp3" }
        }
        
        return "m4a"  // 默认
    }
}

// MARK: - 下载错误
enum DownloadError: Error, LocalizedError {
    case invalidURL
    case noAudioURL
    case downloadFailed
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的URL"
        case .noAudioURL: return "无法获取音频地址"
        case .downloadFailed: return "下载失败"
        case .saveFailed: return "保存失败"
        }
    }
}
