import SwiftUI
import Combine
import ImageIO

// MARK: - 图片缓存管理器
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let ioQueue = DispatchQueue(label: "com.neteasemusic.imagecache", qos: .utility)
    private let displayScale: CGFloat

    // 磁盘缓存限制
    private let maxDiskCacheSize: Int64 = 200 * 1024 * 1024  // 200MB
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60  // 7天

    private init() {
        if Thread.isMainThread {
            displayScale = UIScreen.main.scale
        } else {
            displayScale = DispatchQueue.main.sync { UIScreen.main.scale }
        }
        // 根据设备内存动态设置缓存限制
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryFraction = totalMemory / 8  // 使用 1/8 物理内存
        let maxMemoryCache = min(memoryFraction, 100 * 1024 * 1024)  // 最多 100MB

        cache.countLimit = totalMemory > 4 * 1024 * 1024 * 1024 ? 100 : 50  // 4GB 以上 100 张，否则 50 张
        cache.totalCostLimit = Int(maxMemoryCache)

        // 设置磁盘缓存目录
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache")

        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // 启动时清理过期缓存
        cleanExpiredDiskCache()
    }
    
    @objc private func handleMemoryWarning() {
        clearMemoryCache()
    }
    
    // MARK: - 内存缓存
    func getFromMemory(_ url: URL, targetSize: CGSize? = nil) -> UIImage? {
        let key = cacheKey(for: url, targetSize: targetSize)
        return cache.object(forKey: key as NSString)
    }
    
    func saveToMemory(_ image: UIImage, for url: URL, targetSize: CGSize? = nil) {
        let key = cacheKey(for: url, targetSize: targetSize)
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    private func cacheKey(for url: URL, targetSize: CGSize?) -> String {
        if let size = targetSize {
            return "\(url.absoluteString)_\(Int(size.width))x\(Int(size.height))"
        }
        return url.absoluteString
    }
    
    // MARK: - 磁盘缓存
    func getFromDisk(_ url: URL, targetSize: CGSize? = nil) -> UIImage? {
        let filePath = diskCachePath(for: url)
        guard let data = try? Data(contentsOf: filePath) else {
            return nil
        }

        // 如果指定了目标尺寸，进行下采样
        let image: UIImage?
        if let size = targetSize {
            image = downsample(data: data, to: size)
        } else {
            image = UIImage(data: data)
        }

        // 同时加载到内存缓存
        if let img = image {
            saveToMemory(img, for: url, targetSize: targetSize)
        }
        return image
    }

    /// 异步从磁盘读取图片（避免阻塞主线程）
    func getFromDiskAsync(_ url: URL, targetSize: CGSize? = nil) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                let filePath = self.diskCachePath(for: url)
                guard let data = try? Data(contentsOf: filePath) else {
                    continuation.resume(returning: nil)
                    return
                }

                // 如果指定了目标尺寸，进行下采样
                let image: UIImage?
                if let size = targetSize {
                    image = self.downsample(data: data, to: size)
                } else {
                    image = UIImage(data: data)
                }

                // 同时加载到内存缓存
                if let img = image {
                    self.saveToMemory(img, for: url, targetSize: targetSize)
                }
                continuation.resume(returning: image)
            }
        }
    }
    
    func saveToDisk(_ data: Data, for url: URL) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let filePath = self.diskCachePath(for: url)
            try? data.write(to: filePath)
        }
    }
    
    private func diskCachePath(for url: URL) -> URL {
        let fileName = url.absoluteString.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(200)
        return cacheDirectory.appendingPathComponent(String(fileName))
    }
    
    // MARK: - 图片下采样（减少内存占用）
    func downsample(data: Data, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return UIImage(data: data)
        }
        
        let maxDimension = max(targetSize.width, targetSize.height) * displayScale
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return UIImage(data: data)
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - 清理缓存
    func clearMemoryCache() {
        cache.removeAllObjects()
    }
    
    func clearDiskCache() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.cacheDirectory)
            try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - 缓存大小
    func diskCacheSize() -> Int64 {
        var size: Int64 = 0
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        return size
    }

    // MARK: - 磁盘缓存清理（LRU 策略）
    func cleanExpiredDiskCache() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }

            let resourceKeys: Set<URLResourceKey> = [.contentAccessDateKey, .fileSizeKey]
            guard let files = try? self.fileManager.contentsOfDirectory(
                at: self.cacheDirectory,
                includingPropertiesForKeys: Array(resourceKeys)
            ) else { return }

            let expirationDate = Date().addingTimeInterval(-self.maxCacheAge)
            var currentCacheSize: Int64 = 0
            var filesToDelete: [URL] = []
            var cachedFiles: [(url: URL, accessDate: Date, size: Int64)] = []

            // 遍历文件，标记过期文件并计算总大小
            for fileURL in files {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                    continue
                }

                let accessDate = resourceValues.contentAccessDate ?? Date.distantPast
                let fileSize = Int64(resourceValues.fileSize ?? 0)

                // 过期文件直接删除
                if accessDate < expirationDate {
                    filesToDelete.append(fileURL)
                } else {
                    cachedFiles.append((url: fileURL, accessDate: accessDate, size: fileSize))
                    currentCacheSize += fileSize
                }
            }

            // 删除过期文件
            for fileURL in filesToDelete {
                try? self.fileManager.removeItem(at: fileURL)
            }

            // 如果超出大小限制，按 LRU 删除最旧的文件
            if currentCacheSize > self.maxDiskCacheSize {
                // 按访问时间排序（最旧的在前）
                let sortedFiles = cachedFiles.sorted { $0.accessDate < $1.accessDate }
                var sizeToDelete = currentCacheSize - (self.maxDiskCacheSize / 2)  // 清理到 50%

                for file in sortedFiles {
                    if sizeToDelete <= 0 { break }
                    try? self.fileManager.removeItem(at: file.url)
                    sizeToDelete -= file.size
                }
            }

            #if DEBUG
            print("🗑️ 图片缓存清理完成，删除 \(filesToDelete.count) 个过期文件")
            #endif
        }
    }
}

// MARK: - 缓存图片加载器
@MainActor
final class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var loadFailed = false  // 新增：标记加载失败

    private var cancellable: AnyCancellable?
    private let cache = ImageCache.shared
    private var targetSize: CGSize?
    private var currentURL: URL?
    private var retryCount = 0
    private let maxRetries = 2  // 减少重试次数
    private var loadTask: Task<Void, Never>?

    func load(from url: URL, targetSize: CGSize? = nil) {
        // 如果是同一个 URL，不重复加载
        let sameRequest = isSameRequest(url: url, targetSize: targetSize)
        if sameRequest && (image != nil || isLoading) {
            return
        }

        // 先取消旧任务，避免旧请求回写覆盖新图片
        loadTask?.cancel()
        loadTask = nil

        let requestChanged = !sameRequest
        self.targetSize = targetSize
        self.currentURL = url
        self.retryCount = 0
        self.loadFailed = false
        if requestChanged {
            self.image = nil
            self.isLoading = false
        }

        // 1. 先检查内存缓存（同步）
        if let cached = cache.getFromMemory(url, targetSize: targetSize) {
            self.image = cached
            return
        }

        // 2. 异步检查磁盘缓存和网络加载
        loadTask = Task { [weak self] in
            guard let self = self else { return }

            // 检查磁盘缓存（异步读取，避免阻塞）
            if let cached = await self.cache.getFromDiskAsync(url, targetSize: targetSize) {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard self.isSameRequest(url: url, targetSize: targetSize) else { return }
                    self.image = cached
                    self.isLoading = false
                }
                return
            }

            // 3. 网络加载
            await MainActor.run {
                guard self.isSameRequest(url: url, targetSize: targetSize) else { return }
                self.isLoading = true
            }

            await self.loadFromNetworkAsync(url: url, targetSize: targetSize)
        }
    }

    private func loadFromNetworkAsync(url: URL, targetSize: CGSize?) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // 检查任务是否被取消
            if Task.isCancelled { return }
            
            // 保存原始数据到磁盘
            cache.saveToDisk(data, for: url)
            
            // 下采样后返回
            let loadedImage: UIImage?
            if let size = targetSize {
                loadedImage = cache.downsample(data: data, to: size)
            } else {
                loadedImage = UIImage(data: data)
            }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                guard self.isSameRequest(url: url, targetSize: targetSize) else { return }
                self.isLoading = false
                if let image = loadedImage {
                    self.cache.saveToMemory(image, for: url, targetSize: targetSize)
                    self.image = image
                } else {
                    self.loadFailed = true
                }
            }
        } catch {
            if Task.isCancelled { return }
            
            // 重试逻辑
            if retryCount < maxRetries {
                retryCount += 1
                let delay = pow(2.0, Double(retryCount - 1))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                if !Task.isCancelled {
                    await loadFromNetworkAsync(url: url, targetSize: targetSize)
                }
            } else {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    guard self.isSameRequest(url: url, targetSize: targetSize) else { return }
                    self.isLoading = false
                    self.loadFailed = true
                }
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        cancellable?.cancel()
        isLoading = false
    }

    func reset() {
        cancel()
        image = nil
        loadFailed = false
        targetSize = nil
        currentURL = nil
        retryCount = 0
    }

    private func isSameRequest(url: URL, targetSize: CGSize?) -> Bool {
        currentURL == url && self.targetSize == targetSize
    }
}

// MARK: - 缓存异步图片视图
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @StateObject private var loader = CachedImageLoader()

    init(
        url: URL?,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
            } else if loader.loadFailed {
                // 加载失败时显示默认封面图标
                defaultCoverView
            } else {
                placeholder()
            }
        }
        .task(id: requestKey) {
            reloadImage()
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var requestKey: String {
        let urlKey = url?.absoluteString ?? "nil"
        let sizeKey: String
        if let targetSize = targetSize {
            sizeKey = "\(Int(targetSize.width))x\(Int(targetSize.height))"
        } else {
            sizeKey = "original"
        }
        return "\(urlKey)|\(sizeKey)"
    }

    private func reloadImage() {
        if let url = url {
            loader.load(from: url, targetSize: targetSize)
        } else {
            loader.reset()
        }
    }

    // 默认封面视图（加载失败时显示）
    private var defaultCoverView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray4), Color(.systemGray5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - 便捷初始化器
extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(url: url, content: content, placeholder: { ProgressView() })
    }
}

extension CachedAsyncImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?) {
        self.init(url: url, content: { $0 }, placeholder: { ProgressView() })
    }
}
