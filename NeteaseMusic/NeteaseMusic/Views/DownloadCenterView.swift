import SwiftUI

// MARK: - 下载中心视图
struct DownloadCenterView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var downloadService = SongDownloadService.shared
    @StateObject private var localMusicService = LocalMusicService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // 主题相关
    private var isStrangerTheme: Bool { themeManager.isStrangerTheme }
    private var textColor: Color { themeManager.textColor }
    private var secondaryTextColor: Color { themeManager.secondaryTextColor }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .green }

    
    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground()
                    .environmentObject(themeManager)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        if !downloadService.downloadQueue.isEmpty {
                            downloadingSection
                        }
                        downloadedSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
            }
            .immersiveNavigationChrome()
            .navigationTitle("下载中心")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(isStrangerTheme ? accentColor : nil)
                }
            }
        }
    }
    
    // MARK: - 下载中区域
    private var downloadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(accentColor)
                Text("下载中")
                    .font(.headline)
                    .foregroundColor(textColor)
                Spacer()
                Text("\(downloadService.downloadQueue.count) 首")
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }
            
            VStack(spacing: 0) {
                ForEach(downloadService.downloadQueue, id: \.self) { trackId in
                    if let task = downloadService.downloadTasks[trackId] {
                        DownloadingRow(task: task, isStrangerTheme: isStrangerTheme) {
                            downloadService.cancel(trackId: trackId)
                        }
                        
                        if trackId != downloadService.downloadQueue.last {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
            }
            .glassEffectRounded(cornerRadius: 12)
        }
    }
    
    // MARK: - 已下载区域
    private var downloadedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(accentColor)
                Text("已下载")
                    .font(.headline)
                    .foregroundColor(textColor)
                Spacer()
                Text("\(localMusicService.localTracks.filter { $0.sourceTrackId != nil }.count) 首")
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }
            
            let downloadedTracks = localMusicService.localTracks.filter { $0.sourceTrackId != nil }
            
            if downloadedTracks.isEmpty {
                emptyDownloadedView
            } else {
                VStack(spacing: 0) {
                    ForEach(downloadedTracks) { track in
                        DownloadedRow(track: track, isStrangerTheme: isStrangerTheme) {
                            localMusicService.deleteTrack(track)
                        }
                        
                        if track.id != downloadedTracks.last?.id {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .glassEffectRounded(cornerRadius: 12)
            }
        }
    }
    
    // MARK: - 空状态
    private var emptyDownloadedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(secondaryTextColor.opacity(0.5))
            
            Text("暂无已下载歌曲")
                .font(.subheadline)
                .foregroundColor(secondaryTextColor)
            
            Text("在播放器或歌单中长按歌曲即可下载")
                .font(.caption)
                .foregroundColor(secondaryTextColor.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassEffectRounded(cornerRadius: 12)
    }
}

// MARK: - 下载中行
struct DownloadingRow: View {
    let task: DownloadTask
    var isStrangerTheme: Bool = false
    let onCancel: () -> Void
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .green }
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let coverUrl = task.track.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(width: 48, height: 48)
                .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(task.track.name)
                    .font(.subheadline)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                
                Text(task.track.artistName)
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // 进度
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                
                Circle()
                    .trim(from: 0, to: task.progress)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                if case .downloading = task.status {
                    Text("\(Int(task.progress * 100))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accentColor)
                } else if case .waiting = task.status {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(secondaryTextColor)
                } else if case .failed = task.status {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                }
            }
            .frame(width: 32, height: 32)
            
            // 取消按钮
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(secondaryTextColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - 已下载行
struct DownloadedRow: View {
    let track: LocalTrack
    var isStrangerTheme: Bool = false
    let onDelete: () -> Void
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    
    private var textColor: Color { isStrangerTheme ? .white : .primary }
    private var secondaryTextColor: Color { isStrangerTheme ? .white.opacity(0.6) : .secondary }
    private var accentColor: Color { isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .green }
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            if let artworkImage = track.artworkImage {
                Image(uiImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .cornerRadius(6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
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
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(width: 48, height: 48)
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(track.displayTitle)
                        .font(.subheadline)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    
                    Text(track.formatBadge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(formatColor(track.format)))
                }
                
                HStack(spacing: 4) {
                    Text(track.artistName)
                    Text("•")
                    Text(track.fileSizeText)
                }
                .font(.caption)
                .foregroundColor(secondaryTextColor)
                .lineLimit(1)
            }
            
            Spacer()
            
            // 播放按钮
            Button {
                audioPlayer.setLocalPlaylist([track], startAt: 0)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(accentColor)
            }
            
            // 删除菜单
            Menu {
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
    }
    
    private func formatColor(_ format: String) -> Color {
        switch format.lowercased() {
        case "flac", "alac": return .purple
        case "wav", "aiff": return .blue
        case "mp3": return isStrangerTheme ? Color(red: 1.0, green: 0.2, blue: 0.3) : .green
        case "m4a", "aac": return .orange
        default: return .gray
        }
    }
}

#Preview {
    DownloadCenterView()
}
