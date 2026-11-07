import Foundation
import UIKit

// MARK: - 缓存类型
enum CacheType: String, CaseIterable, Identifiable {
    case image = "图片缓存"
    case audio = "音频缓存"
    case dynamicCover = "动态封面"
    case downloaded = "已下载歌曲"
    case all = "全部缓存"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .image: return "photo.stack"
        case .audio: return "waveform"
        case .dynamicCover: return "sparkles.rectangle.stack"
        case .downloaded: return "arrow.down.circle.fill"
        case .all: return "trash"
        }
    }
    
    var description: String {
        switch self {
        case .image: return "专辑封面、艺人头像等"
        case .audio: return "播放时的音频流缓存"
        case .dynamicCover: return "Apple Music 动态封面"
        case .downloaded: return "手动下载的离线歌曲"
        case .all: return "清除所有缓存数据"
        }
    }
}

// MARK: - 存储详情
struct StorageDetail: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let icon: String
    let type: CacheType
}

struct CachePreviewItem: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let subtitle: String?
}

// MARK: - 缓存管理器
final class CacheManager: ObservableObject {
    static let shared = CacheManager()
    
    @Published var totalCacheSize: Int64 = 0
    @Published var storageDetails: [StorageDetail] = []
    @Published var isCalculating: Bool = false
    @Published var isClearing: Bool = false
    
    private let fileManager = FileManager.default
    
    private init() {
        calculateTotalSize()
    }
    
    // MARK: - 计算缓存大小

    func calculateTotalSize() {
        isCalculating = true

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            var total: Int64 = 0
            var details: [StorageDetail] = []

            // 1. 图片缓存 (Caches/ImageCache)
            let imageSize = self.calculateDirectorySize(name: "ImageCache", inCaches: true)
            if imageSize > 0 {
                details.append(StorageDetail(name: "图片缓存", size: imageSize, icon: "photo.stack", type: .image))
            }
            total += imageSize

            // 2. 音频流缓存 (Caches/AudioCache)
            let audioSize = self.calculateDirectorySize(name: "AudioCache", inCaches: true)
            if audioSize > 0 {
                details.append(StorageDetail(name: "音频缓存", size: audioSize, icon: "waveform", type: .audio))
            }
            total += audioSize

            // 3. 动态封面缓存
            let animatedSize = self.calculateDirectorySize(name: "AnimatedArtwork", inCaches: true)
            let dynamicSize = self.calculateDirectorySize(name: "DynamicCovers", inCaches: true)
            let hlsSize = self.calculateDirectorySize(name: "AppleMusicHLSCache", inCaches: true)
            let totalDynamicCover = animatedSize + dynamicSize + hlsSize
            if totalDynamicCover > 0 {
                details.append(StorageDetail(name: "动态封面", size: totalDynamicCover, icon: "sparkles.rectangle.stack", type: .dynamicCover))
            }
            total += totalDynamicCover

            // 4. 已下载歌曲 (Documents/LocalMusic)
            let downloadedSize = self.calculateDirectorySize(name: "LocalMusic", inCaches: false)
            if downloadedSize > 0 {
                details.append(StorageDetail(name: "已下载歌曲", size: downloadedSize, icon: "arrow.down.circle.fill", type: .downloaded))
            }
            total += downloadedSize

            // 5. URLCache (系统级)
            let urlCacheSize = Int64(URLCache.shared.currentDiskUsage)
            if urlCacheSize > 0 {
                details.append(StorageDetail(name: "网络缓存", size: urlCacheSize, icon: "network", type: .audio))
            }
            total += urlCacheSize

            // 6. tmp 临时目录 (AVFoundation HLS 流缓存)
            let tmpSize = self.calculateTmpDirectorySize()
            if tmpSize > 0 {
                details.append(StorageDetail(name: "临时文件", size: tmpSize, icon: "clock.arrow.circlepath", type: .audio))
            }
            total += tmpSize

            // 7. fsCachedData (URLSession 文件系统缓存)
            let fsCacheSize = self.calculateDirectorySize(name: "fsCachedData", inCaches: true)
            if fsCacheSize > 0 {
                details.append(StorageDetail(name: "流媒体缓存", size: fsCacheSize, icon: "play.circle", type: .audio))
            }
            total += fsCacheSize

            // 8. 其他 Caches 目录内容
            let otherCacheSize = self.calculateOtherCachesSize(excluding: ["ImageCache", "AudioCache", "AnimatedArtwork", "DynamicCovers", "AppleMusicHLSCache", "fsCachedData"])
            if otherCacheSize > 0 {
                details.append(StorageDetail(name: "其他缓存", size: otherCacheSize, icon: "folder", type: .all))
            }
            total += otherCacheSize

            // 按大小排序
            details.sort { $0.size > $1.size }

            await MainActor.run {
                self.totalCacheSize = total
                self.storageDetails = details
                self.isCalculating = false
            }
        }
    }

    /// 计算 tmp 临时目录大小
    private func calculateTmpDirectorySize() -> Int64 {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        return calculateSize(of: tmpDir)
    }
    
    private func calculateDirectorySize(name: String, inCaches: Bool) -> Int64 {
        let baseDir: URL?
        if inCaches {
            baseDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        } else {
            baseDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        
        guard let base = baseDir else { return 0 }
        let directory = base.appendingPathComponent(name)
        return calculateSize(of: directory)
    }
    
    private func calculateOtherCachesSize(excluding: [String]) -> Int64 {
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        
        var total: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
            for item in contents {
                let name = item.lastPathComponent
                if !excluding.contains(name) {
                    total += calculateSize(of: item)
                }
            }
        } catch {
            #if DEBUG
            print("❌ 计算其他缓存失败: \(error)")
            #endif
        }
        
        return total
    }
    
    private func calculateSize(of url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        
        var size: Int64 = 0
        
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        
        return size
    }
    
    func previewItems(for type: CacheType, limit: Int = 40) -> [CachePreviewItem] {
        switch type {
        case .image:
            return listItems(inCachesDirectories: ["ImageCache"], limit: limit)
        case .audio:
            var items = listItems(inCachesDirectories: ["AudioCache", "fsCachedData"], limit: limit)
            items.append(contentsOf: listTemporaryItems(limit: max(0, limit - items.count)))
            if URLCache.shared.currentDiskUsage > 0 {
                items.insert(
                    CachePreviewItem(
                        name: "系统网络缓存",
                        size: Int64(URLCache.shared.currentDiskUsage),
                        subtitle: "URLCache"
                    ),
                    at: 0
                )
            }
            return Array(items.prefix(limit))
        case .dynamicCover:
            return listItems(inCachesDirectories: ["AnimatedArtwork", "DynamicCovers", "AppleMusicHLSCache"], limit: limit)
        case .downloaded:
            return downloadedSongPreviewItems(limit: limit)
        case .all:
            var items: [CachePreviewItem] = []
            items.append(contentsOf: previewItems(for: .image, limit: 12))
            items.append(contentsOf: previewItems(for: .audio, limit: 12))
            items.append(contentsOf: previewItems(for: .dynamicCover, limit: 12))
            let otherSize = storageDetails.first(where: { $0.name == "其他缓存" })?.size ?? 0
            if otherSize > 0 {
                items.append(CachePreviewItem(name: "其他缓存", size: otherSize, subtitle: "Caches 剩余目录"))
            }
            return Array(items.prefix(limit))
        }
    }

    func previewSummary(for type: CacheType) -> (count: Int, size: Int64) {
        let matching = storageDetails.filter { detail in
            switch type {
            case .all:
                return detail.type != .downloaded
            default:
                return detail.type == type
            }
        }
        let size = matching.reduce(Int64(0)) { $0 + $1.size }
        return (matching.count, size)
    }

    private func listItems(inCachesDirectories names: [String], limit: Int) -> [CachePreviewItem] {
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return [] }
        var items: [CachePreviewItem] = []
        for name in names {
            let directory = cacheDir.appendingPathComponent(name)
            items.append(contentsOf: listFiles(in: directory, fallbackName: name, limit: max(0, limit - items.count)))
            if items.count >= limit { break }
        }
        return items
    }

    private func listTemporaryItems(limit: Int) -> [CachePreviewItem] {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        return listFiles(in: tmpDir, fallbackName: "临时文件", limit: limit)
    }

    private func downloadedSongPreviewItems(limit: Int) -> [CachePreviewItem] {
        listItems(inDocumentDirectories: ["LocalMusic"], limit: limit)
    }

    private func listItems(inDocumentDirectories names: [String], limit: Int) -> [CachePreviewItem] {
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        var items: [CachePreviewItem] = []
        for name in names {
            items.append(contentsOf: listFiles(in: docs.appendingPathComponent(name), fallbackName: name, limit: max(0, limit - items.count)))
            if items.count >= limit { break }
        }
        return items
    }

    private func listFiles(in directory: URL, fallbackName: String, limit: Int) -> [CachePreviewItem] {
        guard limit > 0, fileManager.fileExists(atPath: directory.path) else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [(name: String, size: Int64, date: Date)] = []
        for url in contents {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                let size = calculateSize(of: url)
                if size > 0 {
                    files.append((url.lastPathComponent, size, values?.contentModificationDate ?? .distantPast))
                }
            } else {
                let size = Int64(values?.fileSize ?? 0)
                if size > 0 {
                    files.append((url.lastPathComponent, size, values?.contentModificationDate ?? .distantPast))
                }
            }
        }
        files.sort { $0.size > $1.size }
        return files.prefix(limit).map {
            CachePreviewItem(name: $0.name.isEmpty ? fallbackName : $0.name, size: $0.size, subtitle: fallbackName)
        }
    }

    // MARK: - 清除缓存
    
    func clearCache(type: CacheType) async -> Bool {
        await MainActor.run {
            isClearing = true
        }
        
        defer {
            Task { @MainActor in
                isClearing = false
                calculateTotalSize()
            }
        }
        
        switch type {
        case .image:
            return await clearImageCache()
        case .audio:
            return await clearAudioCache()
        case .dynamicCover:
            return await clearDynamicCoverCache()
        case .downloaded:
            return await clearDownloadedSongs()
        case .all:
            let results = await withTaskGroup(of: Bool.self) { group in
                group.addTask { await self.clearImageCache() }
                group.addTask { await self.clearAudioCache() }
                group.addTask { await self.clearDynamicCoverCache() }
                // 注意：不自动清除已下载歌曲，需要用户单独确认
                
                var allSuccess = true
                for await result in group {
                    if !result { allSuccess = false }
                }
                return allSuccess
            }
            
            // 清除 API 缓存和 URLCache
            await APICache.shared.clearAll()
            URLCache.shared.removeAllCachedResponses()
            SongCacheService.shared.clearAll()
            
            return results
        }
    }
    
    private func clearImageCache() async -> Bool {
        // 清除内存缓存
        ImageCache.shared.clearMemoryCache()
        
        // 清除磁盘缓存
        return clearDirectory(name: "ImageCache", inCaches: true)
    }
    
    private func clearAudioCache() async -> Bool {
        // 清除音频流缓存
        _ = clearDirectory(name: "AudioCache", inCaches: true)

        // 清除 fsCachedData (URLSession 文件系统缓存)
        _ = clearDirectory(name: "fsCachedData", inCaches: true)

        // 清除 tmp 临时目录
        clearTmpDirectory()

        // 清除 URLCache
        URLCache.shared.removeAllCachedResponses()

        // 清除歌曲 URL 缓存
        SongCacheService.shared.clearAll()

        return true
    }

    /// 清除 tmp 临时目录
    private func clearTmpDirectory() {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())

        do {
            let contents = try fileManager.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
            for item in contents {
                try? fileManager.removeItem(at: item)
            }
            #if DEBUG
            print("✅ 已清除临时目录: \(contents.count) 个项目")
            #endif
        } catch {
            #if DEBUG
            print("❌ 清除临时目录失败: \(error)")
            #endif
        }
    }
    
    private func clearDynamicCoverCache() async -> Bool {
        // 清除动态封面缓存
        DynamicCoverCache.shared.clearAll()
        
        // 清除相关目录
        _ = clearDirectory(name: "AnimatedArtwork", inCaches: true)
        _ = clearDirectory(name: "DynamicCovers", inCaches: true)
        _ = clearDirectory(name: "AppleMusicHLSCache", inCaches: true)
        
        return true
    }
    
    private func clearDownloadedSongs() async -> Bool {
        // 清除已下载的歌曲
        // 注意：这会删除用户下载的所有歌曲！
        let success = clearDirectory(name: "LocalMusic", inCaches: false)
        
        if success {
            // 清除本地音乐服务的记录
            await MainActor.run {
                LocalMusicService.shared.clearAllTracks()
            }
        }
        
        return success
    }
    
    private func clearDirectory(name: String, inCaches: Bool) -> Bool {
        let baseDir: URL?
        if inCaches {
            baseDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        } else {
            baseDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        
        guard let base = baseDir else { return false }
        
        let directory = base.appendingPathComponent(name)
        
        guard fileManager.fileExists(atPath: directory.path) else {
            return true // 目录不存在也算成功
        }
        
        do {
            try fileManager.removeItem(at: directory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            #if DEBUG
            print("✅ 已清除缓存目录: \(name)")
            #endif
            return true
        } catch {
            #if DEBUG
            print("❌ 清除缓存失败: \(name), \(error)")
            #endif
            return false
        }
    }
    
    // MARK: - 格式化大小
    
    static func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
