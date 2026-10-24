import SwiftUI
import UniformTypeIdentifiers

// MARK: - 本地音乐视图
struct LocalMusicView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var localMusicService = LocalMusicService.shared
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @State private var showingFilePicker = false
    @State private var showingDeleteAlert = false
    @State private var trackToDelete: LocalTrack?
    @State private var isRefreshing = false
    @State private var sortOrder: SortOrder = .dateAdded
    @Environment(\.colorScheme) var colorScheme
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .green }
    
    enum SortOrder: String, CaseIterable {
        case dateAdded = "添加时间"
        case title = "标题"
        case artist = "艺术家"
    }
    
    var sortedTracks: [LocalTrack] {
        switch sortOrder {
        case .dateAdded:
            return localMusicService.localTracks.sorted { $0.addedDate > $1.addedDate }
        case .title:
            return localMusicService.localTracks.sorted { $0.displayTitle.localizedCompare($1.displayTitle) == .orderedAscending }
        case .artist:
            return localMusicService.localTracks.sorted { $0.artistName.localizedCompare($1.artistName) == .orderedAscending }
        }
    }
    
    var body: some View {
        ZStack {
            ThemedBackground()
                .environmentObject(themeManager)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection

                    if localMusicService.isImporting {
                        importProgressSection
                    }

                    if localMusicService.localTracks.isEmpty {
                        emptyStateView
                    } else {
                        controlSection
                        trackListSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        }
        .immersiveNavigationChrome()
        .navigationTitle("本地歌曲")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showingFilePicker = true }) {
                        Label("导入音乐", systemImage: "plus.circle")
                    }
                    
                    Button(action: refreshLibrary) {
                        Label("刷新库", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: localMusicService.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result)
        }
        .alert("删除歌曲", isPresented: $showingDeleteAlert, presenting: trackToDelete) { track in
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                localMusicService.deleteTrack(track)
            }
        } message: { track in
            Text("确定要删除「\(track.displayTitle)」吗？文件将从设备中移除。")
        }
    }
    
    // MARK: - 头部统计
    private var headerSection: some View {
        HStack(spacing: 16) {
            // 歌曲数量
            StatCard(
                icon: "music.note",
                iconColor: .green,
                title: "歌曲",
                value: "\(localMusicService.localTracks.count)"
            )
            
            // 总时长
            StatCard(
                icon: "clock",
                iconColor: .blue,
                title: "总时长",
                value: totalDurationText
            )
            
            // 存储空间
            StatCard(
                icon: "internaldrive",
                iconColor: .purple,
                title: "占用",
                value: totalSizeText
            )
        }
        .padding(.top, 8)
    }
    
    // MARK: - 导入进度
    private var importProgressSection: some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : nil)
                Text("正在导入...")
                    .font(.subheadline)
                    .foregroundColor(secondaryTextColor)
                Spacer()
                Text("\(Int(localMusicService.importProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }
            
            ProgressView(value: localMusicService.importProgress)
                .tint(accentColor)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isStrangerTheme ? Color(red: 0.08, green: 0.04, blue: 0.12) : Color(.secondarySystemBackground))
        )
    }
    
    // MARK: - 空状态
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.house")
                .font(.system(size: 60))
                .foregroundColor(secondaryTextColor.opacity(0.5))
            
            Text("暂无本地歌曲")
                .font(.headline)
                .foregroundColor(secondaryTextColor)
            
            Text("点击下方按钮从「文件」App 导入音乐")
                .font(.subheadline)
                .foregroundColor(secondaryTextColor.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Button(action: { showingFilePicker = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("导入音乐")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: isStrangerTheme 
                            ? [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]
                            : [.green, .green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
            }
            
            // 支持格式提示
            VStack(spacing: 4) {
                Text("支持的格式")
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
                Text("MP3 • M4A • FLAC • WAV • AIFF • OGG")
                    .font(.caption2)
                    .foregroundColor(secondaryTextColor.opacity(0.7))
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .padding(.vertical, 60)
    }
    
    // MARK: - 控制区
    private var controlSection: some View {
        HStack {
            // 播放全部
            Button(action: playAll) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text("播放全部")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: isStrangerTheme 
                            ? [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.1, blue: 0.2)]
                            : [.green, .green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
            }
            
            Spacer()
            
            // 排序
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(action: { sortOrder = order }) {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOrder.rawValue)
                }
                .font(.system(size: 13))
                .foregroundColor(secondaryTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isStrangerTheme ? Color(red: 0.1, green: 0.05, blue: 0.15) : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                )
            }
        }
    }
    
    // MARK: - 歌曲列表
    private var trackListSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                LocalTrackRow(
                    track: track,
                    index: index + 1,
                    isPlaying: audioPlayer.currentLocalTrack?.id == track.id,
                    isStrangerTheme: isStrangerTheme,
                    onTap: { playTrack(track, index: index) },
                    onDelete: {
                        trackToDelete = track
                        showingDeleteAlert = true
                    },
                    onShare: {
                        localMusicService.shareTrack(track)
                    }
                )
                
                if index < sortedTracks.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
        .glassEffectRounded(cornerRadius: 16)
    }
    
    // MARK: - 计算属性
    private var totalDurationText: String {
        let total = localMusicService.localTracks.reduce(0) { $0 + $1.duration }
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        } else {
            return "\(minutes)分钟"
        }
    }
    
    private var totalSizeText: String {
        let total = localMusicService.localTracks.reduce(Int64(0)) { $0 + $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: total)
    }
    
    // MARK: - 操作方法
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                _ = await localMusicService.importAudioFiles(from: urls)
            }
        case .failure(let error):
            #if DEBUG
            print("文件选择失败: \(error.localizedDescription)")
            #endif
        }
    }
    
    private func playAll() {
        guard !sortedTracks.isEmpty else { return }
        audioPlayer.setLocalPlaylist(sortedTracks, startAt: 0)
    }
    
    private func playTrack(_ track: LocalTrack, index: Int) {
        audioPlayer.setLocalPlaylist(sortedTracks, startAt: index)
    }
    
    private func refreshLibrary() {
        isRefreshing = true
        Task {
            await localMusicService.refreshLibrary()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}

// MARK: - 统计卡片
struct StatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassEffectRounded(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.22), .clear]
                            : [.white.opacity(0.55), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
    }
}

// MARK: - 本地歌曲行
struct LocalTrackRow: View {
    let track: LocalTrack
    let index: Int
    let isPlaying: Bool
    var isStrangerTheme: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .green }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 序号
                Text("\(index)")
                    .font(.system(size: 14))
                    .foregroundColor(isPlaying ? accentColor : secondaryTextColor)
                    .frame(width: 28)
                
                // 封面
                if let artwork = track.artworkImage {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .cornerRadius(8)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: isStrangerTheme 
                                        ? [Color(red: 1.0, green: 0.2, blue: 0.3).opacity(0.3), Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.3)]
                                        : [.green.opacity(0.3), .blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(width: 48, height: 48)
                }
                
                // 歌曲信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(track.displayTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isPlaying ? accentColor : textColor)
                            .lineLimit(1)
                        
                        // 格式标签
                        Text(track.formatBadge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(formatColor(track.format))
                            )
                        
                        // 歌词标签
                        if track.hasLyrics {
                            Text("词")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .stroke(Color.orange, lineWidth: 1)
                                )
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Text(track.artistName)
                            .foregroundColor(secondaryTextColor)
                        
                        Text("•")
                            .foregroundColor(secondaryTextColor.opacity(0.5))
                        
                        Text(track.durationText)
                            .foregroundColor(secondaryTextColor.opacity(0.7))
                    }
                    .font(.caption)
                    .lineLimit(1)
                }
                
                Spacer()
                
                // 播放动画
                if isPlaying {
                    if #available(iOS 17.0, *) {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(accentColor)
                            .symbolEffect(.variableColor.iterative)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 14))
                            .foregroundColor(accentColor)
                    }
                }
                
                // 更多按钮
                Menu {
                    Button(action: onTap) {
                        Label("播放", systemImage: "play.fill")
                    }

                    Button(action: onShare) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive, action: onDelete) {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(secondaryTextColor)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func formatColor(_ format: String) -> Color {
        switch format.lowercased() {
        case "flac", "alac":
            return .purple
        case "wav", "aiff":
            return .blue
        case "mp3":
            return .green
        case "m4a", "aac":
            return .orange
        default:
            return .gray
        }
    }
}

#Preview {
    NavigationStack {
        LocalMusicView()
    }
}
